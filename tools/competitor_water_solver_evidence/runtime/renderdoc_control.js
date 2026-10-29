'use strict';
// DLL must already have been injected externally while the owned process was suspended.
const config=globalThis.CAPTURE_CONFIG,m=Process.getModuleByName('renderdoc.dll'),out=Memory.alloc(8);
const get=new NativeFunction(m.getExportByName('RENDERDOC_GetAPI'),'int',['int','pointer'],{exceptions:'propagate'});
if(get(10600,out)!==1)throw Error('RenderDoc API 1.6 unavailable');
const table=out.readPointer(),fn=(i,r,a)=>new NativeFunction(table.add(i*8).readPointer(),r,a,{exceptions:'propagate'});
fn(11,'void',['pointer'])(Memory.allocUtf8String(config.prefix));
fn(5,'void',['pointer','int'])(ptr(0),0);fn(6,'void',['pointer','int'])(ptr(0),0);fn(8,'void',['uint','uint'])(0,0);
const trigger=fn(15,'void',[]),count=fn(13,'uint',[]),getCapture=fn(14,'uint',['uint','pointer','pointer','pointer']);
send({kind:'renderdoc_control_ready',module:m.path,base:String(m.base),api:10600});
rpc.exports={trigger(){trigger();return {requested:true,meaning:'Next Present frame, not an immediate GPU snapshot'};},status(){
 const captures=[];for(let i=0;i<count();i++){const len=Memory.alloc(4),time=Memory.alloc(8);len.writeU32(0);getCapture(i,ptr(0),len,time);const n=len.readU32();if(n<1||n>32768)throw Error('Capture path length');const name=Memory.alloc(n);if(getCapture(i,name,len,time))captures.push({path:name.readUtf8String(),timestamp:time.readU64().toString()});}
 return {count:captures.length,captures};
}};
