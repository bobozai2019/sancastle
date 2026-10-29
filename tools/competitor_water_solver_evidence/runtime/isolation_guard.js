'use strict';
// Process-local test isolation, not an OS sandbox or an adversarial boundary.
const iso=globalThis.ISOLATION_CONFIG;
const held=[],state={ready:false,denied:0,writes:0,folder_redirects:0,errors:[]};
const norm=s=>{
 s=String(s).replace(/\//g,'\\').toLowerCase().replace(/^\\\?\?\\/,'').replace(/^\\\\\?\\/,'');
 if(s.startsWith('pipe\\'))s='\\device\\namedpipe\\'+s.slice(5);
 for(const [native,dos] of Object.entries(iso.volumes))if(s.startsWith(native.toLowerCase()+'\\'))s=dos.toLowerCase()+s.slice(native.length);
 if(/^[a-z]:\\/.test(s)){const parts=[];for(const x of s.slice(3).split('\\')){if(x==='..')parts.pop();else if(x&&x!=='.')parts.push(x);}s=s.slice(0,3)+parts.join('\\');}
 return s.replace(/\\$/,'');
};
const allowed=iso.allowed_roots.map(norm);
const inside=p=>allowed.some(r=>p===r||p.startsWith(r+'\\'));
function event(kind,data){send({kind:'isolation_'+kind,...data});}
function api(mod,name,ret,args){return new NativeFunction(Process.getModuleByName(mod).getExportByName(name),ret,args);}
Process.setExceptionHandler(details=>{
 const mod=Process.findModuleByAddress(details.address);
 event('native_exception',{type:details.type,address:String(details.address),module:mod?mod.name:null,
  module_offset:mod?String(details.address.sub(mod.base)):null,memory:details.memory,
  context_pc:String(details.context.pc)});
 return false;
});
try{
 Module.load('shell32.dll');Module.load('ole32.dll');Module.load('advapi32.dll');
 const malloc=api('ole32.dll','CoTaskMemAlloc','pointer',['size_t']);
 const folders=iso.folder_guids;
 const guid=p=>Array.from(new Uint8Array(p.readByteArray(16)),x=>x.toString(16).padStart(2,'0')).join('');
 const known=Process.getModuleByName('shell32.dll').getExportByName('SHGetKnownFolderPath');
 const originalKnown=new NativeFunction(known,'int',['pointer','uint','pointer','pointer']);
 const folderCallback=new NativeCallback((id,flags,token,result)=>{
  const target=folders[guid(id)];if(!target)return originalKnown(id,flags,token,result);
  const text=Memory.allocUtf16String(target),dest=malloc((target.length+1)*2);if(dest.isNull())return -2147024882;
  Memory.copy(dest,text,(target.length+1)*2);result.writePointer(dest);state.folder_redirects++;event('folder',{path:target});return 0;
 },'int',['pointer','uint','pointer','pointer']);held.push(folderCallback);Interceptor.replace(known,folderCallback);
 const legacy=Process.getModuleByName('shell32.dll').getExportByName('SHGetFolderPathW');
 const legacyOriginal=new NativeFunction(legacy,'int',['pointer','int','pointer','uint','pointer']);
 const legacyCallback=new NativeCallback((hwnd,csidl,token,flags,result)=>{
  const target=({26:iso.roaming,28:iso.local,40:iso.profile})[csidl&255];
  if(!target)return legacyOriginal(hwnd,csidl,token,flags,result);
  if(target.length>=260)return -2147024774;result.writeUtf16String(target);state.folder_redirects++;return 0;
 },'int',['pointer','int','pointer','uint','pointer']);held.push(legacyCallback);Interceptor.replace(legacy,legacyCallback);
 const regLoad=api('advapi32.dll','RegLoadAppKeyW','int',['pointer','pointer','uint','uint','uint']);
 const regOverride=api('advapi32.dll','RegOverridePredefKey','int',['pointer','pointer']);
 const handle=Memory.alloc(Process.pointerSize);handle.writePointer(ptr(0));
 const loadResult=regLoad(Memory.allocUtf16String(iso.hive),handle,0xf003f,1,0);
 if(loadResult!==0)throw Error('RegLoadAppKey '+loadResult);
 const overrideResult=regOverride(ptr('0xffffffff80000001'),handle.readPointer());
 if(overrideResult!==0)throw Error('RegOverridePredefKey '+overrideResult);
 held.push(handle);event('registry',{hive:iso.hive,load_result:loadResult,override_result:overrideResult,scope:'Calling process HKCU only'});
 const finalName=api('kernel32.dll','GetFinalPathNameByHandleW','uint',['pointer','pointer','uint','uint']);
 const attributes=api('kernel32.dll','GetFileAttributesW','uint',['pointer']);
 const fileType=api('kernel32.dll','GetFileType','uint',['pointer']);
 const queryObject=api('ntdll.dll','NtQueryObject','int',['pointer','int','pointer','uint','pointer']);
 function nativeHandleName(h){const data=Memory.alloc(65536),length=Memory.alloc(4);if(queryObject(h,1,data,65536,length)!==0)return null;const n=data.readU16(),text=data.add(8).readPointer();return n&&!text.isNull()?norm(text.readUtf16String(n/2)):null;}
 function handlePath(h){const b=Memory.alloc(65536),n=finalName(h,b,32768,0);return n>0&&n<32768?norm(b.readUtf16String(n)):nativeHandleName(h);}
 function noReparse(path){
  if(!path||!(/^[a-z]:\\/.test(path)))return false;
  const pieces=path.split('\\');let current=pieces.shift()+'\\';
  for(const part of pieces){current+=part;const a=attributes(Memory.allocUtf16String(current));if(a===0xffffffff)break;if(a&0x400)return false;current+='\\';}
  return true;
 }
 function objectPath(oa){
  const root=oa.add(8).readPointer(),us=oa.add(16).readPointer();if(us.isNull())return null;
  const len=us.readU16(),buffer=us.add(8).readPointer();if(len===0&&!root.isNull())return handlePath(root);if(len>32766||buffer.isNull())return null;
  let name=buffer.readUtf16String(len/2);
  if(!root.isNull()&&!name.startsWith('\\')){const b=Memory.alloc(65536),n=finalName(root,b,32768,0);if(n===0||n>=32768)return null;name=b.readUtf16String(n)+'\\'+name;}
  return norm(name);
 }
 for(const [name,types] of [['NtCreateFile',['pointer','uint','pointer','pointer','pointer','uint','uint','uint','uint','pointer','uint']],
                          ['NtOpenFile',['pointer','uint','pointer','pointer','uint','uint']]]){
  const address=Process.getModuleByName('ntdll.dll').getExportByName(name),original=new NativeFunction(address,'int',types);
  const callback=new NativeCallback(function(...args){
   const redirected=[];
   let path=null;try{path=objectPath(args[2]);}catch(e){state.errors.push(String(e));}
   for(const mapping of iso.path_redirects||[]){
    const from=norm(mapping.from),to=norm(mapping.to);
    if(path&&(path===from||path.startsWith(from+'\\'))){
     const destination=to+path.slice(from.length),text=Memory.allocUtf16String('\\??\\'+destination),us=Memory.alloc(16),oa=Memory.alloc(48);
     us.writeU16(('\\??\\'+destination).length*2);us.add(2).writeU16(('\\??\\'+destination).length*2+2);us.add(8).writePointer(text);
     Memory.copy(oa,args[2],48);oa.add(8).writePointer(ptr(0));oa.add(16).writePointer(us);args[2]=oa;
     redirected.push(text,us,oa);
     event('path_redirect',{api:name,from:path,to:destination});path=destination;break;
    }
   }
   const mask=0x520d0156,write=((args[1]>>>0)&mask)!==0||(name==='NtCreateFile'&&args[7]!==1);
   if(write){
    const device=path&&path.startsWith('\\device\\')&&!path.startsWith('\\device\\harddiskvolume')&&!path.startsWith('\\device\\mup\\');
    if(!device&&(!path||!inside(path)||!noReparse(path))){
     state.denied++;event('denied',{api:name,path,desired_access:args[1],reason:'Outside explicit owned roots'});
     try{args[0].writePointer(ptr(0));args[3].writeU32(0xc0000022);args[3].add(8).writeU64(0);}catch(e){}
     return -1073741790;
    }
    if(!device){state.writes++;event('write_open',{api:name,path,desired_access:args[1]});}
   }
   const result=original(...args);redirected.length=0;return result;
  },'int',types);held.push(callback);Interceptor.replace(address,callback);
 }
 const ntQueryKey=api('ntdll.dll','NtQueryKey','int',['pointer','int','pointer','uint','pointer']);
 function keyPath(h){
  const length=Memory.alloc(4);ntQueryKey(h,3,ptr(0),0,length);const size=length.readU32();
  if(size<4||size>65536)return null;const data=Memory.alloc(size);if(ntQueryKey(h,3,data,size,length)!==0)return null;
  return data.add(4).readUtf16String(data.readU32()/2).toLowerCase();
 }
 const privateRegistry=keyPath(handle.readPointer());
 if(!privateRegistry)throw Error('Cannot identify private application hive');
 event('private_registry_path',{path:privateRegistry});
 const privateKey=p=>p&&(p===privateRegistry||p.startsWith(privateRegistry+'\\'));
 for(const [name,types] of [['NtSetValueKey',['pointer','pointer','uint','uint','pointer','uint']],
 ['NtDeleteValueKey',['pointer','pointer']],['NtDeleteKey',['pointer']],['NtRenameKey',['pointer','pointer']]]){
  const address=Process.getModuleByName('ntdll.dll').getExportByName(name),original=new NativeFunction(address,'int',types);
  const callback=new NativeCallback(function(...args){const path=keyPath(args[0]);if(!privateKey(path)){state.denied++;event('denied',{api:name,path,reason:'Outside private registry hive'});return -1073741790;}return original(...args);},'int',types);
  held.push(callback);Interceptor.replace(address,callback);
 }
 const createKeyAddress=Process.getModuleByName('ntdll.dll').getExportByName('NtCreateKey');
 const keyTypes=['pointer','uint','pointer','uint','pointer','uint','pointer'],createKeyOriginal=new NativeFunction(createKeyAddress,'int',keyTypes);
 const keyCallback=new NativeCallback(function(...args){
  const oa=args[2],root=oa.add(8).readPointer(),us=oa.add(16).readPointer();let path=null;
  if(!us.isNull()){const name=us.add(8).readPointer().readUtf16String(us.readU16()/2);path=root.isNull()?name.toLowerCase():((keyPath(root)||'')+'\\'+name.toLowerCase());}
  if(!privateKey(path)){state.denied++;event('denied',{api:'NtCreateKey',path,reason:'Outside private registry hive'});args[0].writePointer(ptr(0));return -1073741790;}
  return createKeyOriginal(...args);
 },'int',keyTypes);held.push(keyCallback);Interceptor.replace(createKeyAddress,keyCallback);
 for(const [name,types] of [['NtWriteFile',['pointer','pointer','pointer','pointer','pointer','pointer','uint','pointer','pointer']],
                          ['NtSetInformationFile',['pointer','pointer','pointer','uint','uint']]]){
  const address=Process.getModuleByName('ntdll.dll').getExportByName(name),original=new NativeFunction(address,'int',types);
  const callback=new NativeCallback(function(...args){
   if(name==='NtSetInformationFile'&&[14,16].includes(args[4]))return original(...args); // file position/mode, not storage mutation
   const path=handlePath(args[0]),device=fileType(args[0]);let acceptable=(path&&inside(path))||device===2||device===3||!!(path&&path.startsWith('\\device\\')&&!path.startsWith('\\device\\harddiskvolume')&&!path.startsWith('\\device\\mup\\'));
   if(name==='NtSetInformationFile'&&[10,11,65,72].includes(args[4])){
    const data=args[2],root=data.add(8).readPointer(),length=data.add(16).readU32();let destination=null;
    if(length>0&&length<32768){destination=data.add(20).readUtf16String(length/2);if(!root.isNull()&&!destination.startsWith('\\'))destination=(handlePath(root)||'')+'\\'+destination;destination=norm(destination);}
    acceptable=acceptable&&inside(destination||'')&&noReparse(destination);
    if(!acceptable)event('rename_destination_denied',{path,destination});
   }
   if(!acceptable){state.denied++;event('denied',{api:name,path,reason:'Handle or rename destination outside owned roots'});return -1073741790;}
   return original(...args);
  },'int',types);held.push(callback);Interceptor.replace(address,callback);
 }
 const processAddress=Process.getModuleByName('ntdll.dll').getExportByName('NtCreateUserProcess');
 const processTypes=['pointer','pointer','uint','uint','pointer','pointer','uint','uint','pointer','pointer','pointer'];
 const denyChild=new NativeCallback(function(...args){state.denied++;event('child_denied',{api:'NtCreateUserProcess'});args[0].writePointer(ptr(0));args[1].writePointer(ptr(0));return -1073741790;},'int',processTypes);
 held.push(denyChild);Interceptor.replace(processAddress,denyChild);
 api('kernel32.dll','SetEnvironmentVariableW','bool',['pointer','pointer'])(Memory.allocUtf16String('CODEX_WATER_GUARD_READY'),Memory.allocUtf16String('1'));
 state.ready=true;event('ready',{pid:Process.id,allowed_roots:iso.allowed_roots,
  limitations:['Native device/pipe handles allowed','Not an OS sandbox; other-process brokers and untested persistence APIs are not claimed covered','Child process creation denied; registry mutations restricted to the private hive']});
}catch(e){state.errors.push(String(e));event('failed',{message:String(e)});}
rpc.exports={isolationstatus(){return state;}};
