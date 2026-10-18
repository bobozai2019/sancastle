'use strict';
// Engine/API boundaries only. The two Readback publication RVAs are hash-gated
// by capture.py and checked against the actual runtime class/fields before use.
const cfg = globalThis.PROBE_CONFIG;
const nil = ptr(0);
let events = [], nextEvent = 0, rawBytes = 0, lastPaint = 0;
let phase = 'unlabelled', phaseSerial = 0, installed = false;
let captureCount = 0, lastCapture = 0, capturePending = false;
let rdTrigger = null;
const stats = {dispatch:0, paint:0, readback:0, upload:0, dropped_events:0};
const replacements = [];
function emit(kind, data={}) {
  if (events.length >= 8192) { stats.dropped_events++; return; }
  events.push({id:++nextEvent, kind, utc_ms:Date.now(), phase, phase_serial:phaseSerial,
    thread:Process.getCurrentThreadId(), ...data});
}
function flush() { if(events.length) {const batch=events;events=[];send({kind:'events',events:batch});} }
function error(where,e) {send({kind:'hook_error',where,message:String(e)});}
function raw(kind, p, bytes, detail={}) {
  if(bytes<=0 || bytes>8*1024*1024 || rawBytes+bytes>cfg.max_raw_bytes) {
    emit('raw_skipped',{payload_kind:kind,bytes,reason:'bounded raw budget'});return null;
  }
  const id=++nextEvent;
  const data=p.readByteArray(bytes); rawBytes+=bytes;
  flush();
  send({kind:'raw',id,payload_kind:kind,utc_ms:Date.now(),phase,phase_serial:phaseSerial,
    bytes,address:String(p),thread:Process.getCurrentThreadId(),...detail},data);
  return id;
}
function utf16(p) {if(p.isNull())return null;const n=p.add(16).readS32();if(n<0||n>2048)throw Error('string length '+n);return p.add(20).readUtf16String(n);}
function floats(p,n){return Array.from({length:n},(_,i)=>p.add(i*4).readFloat());}
function ints(p,n){return Array.from({length:n},(_,i)=>p.add(i*4).readS32());}
function cleanFloats(v){return v.map(x=>Number.isFinite(x)?x:String(x));}

// RenderDoc 1.6 API indices are from the local renderdoc_app.h, copied into the
// evidence manifest by the host. Captures request subsequent PRESENT frames.
if(cfg.renderdoc) {
  try {
    const lib=Process.getModuleByName('renderdoc.dll'), output=Memory.alloc(8);
    const get=new NativeFunction(lib.getExportByName('RENDERDOC_GetAPI'),'int',['int','pointer']);
    if(get(10600,output)!==1)throw Error('RENDERDOC API 1.6 unavailable');
    const api=output.readPointer();
    const fn=(i,r,a)=>new NativeFunction(api.add(i*8).readPointer(),r,a);
    fn(11,'void',['pointer'])(Memory.allocUtf8String(cfg.capture_prefix));
    fn(6,'void',['pointer','int'])(nil,0); // Only bounded explicit captures.
    fn(8,'void',['uint','uint'])(0,0); // Hide capture overlay, not game UI.
    rdTrigger=fn(22,'void',['uint']);
    send({kind:'renderdoc_ready',api:10600,path:lib.path,capture_prefix:cfg.capture_prefix});
  }catch(e){send({kind:'renderdoc_unavailable',message:String(e)});}
}
function requestCapture(reason) {
  if(!rdTrigger || captureCount>=cfg.max_captures || Date.now()-lastCapture<8000)return false;
  rdTrigger(2);captureCount+=2;lastCapture=Date.now();
  emit('capture_requested',{reason,frames:2,total_requested:captureCount,
    timing:'next two present frames; may miss a single-frame edit'});return true;
}

// Passive input sampling is restricted to this process's foreground window.
let input=null, keys={};
try {
  const u=Process.getModuleByName('user32.dll');
  const fg=new NativeFunction(u.getExportByName('GetForegroundWindow'),'pointer',[]);
  const owner=new NativeFunction(u.getExportByName('GetWindowThreadProcessId'),'uint',['pointer','pointer']);
  const key=new NativeFunction(u.getExportByName('GetAsyncKeyState'),'int16',['int']);
  const cursor=new NativeFunction(u.getExportByName('GetCursorPos'),'bool',['pointer']);
  const client=new NativeFunction(u.getExportByName('ScreenToClient'),'bool',['pointer','pointer']);
  const ip=Memory.alloc(4),pos=Memory.alloc(8);let old='';
  setInterval(()=>{
    const window=fg();owner(window,ip);
    if(ip.readU32()!==Process.id){if(input){input=null;emit('input_focus_lost');}return;}
    cursor(pos);client(window,pos);
    const down=k=>(key(k)&0x8000)!==0;
    const next={x:pos.readS32(),y:pos.add(4).readS32(),left:down(1),right:down(2),middle:down(4)};
    const encoded=JSON.stringify(next);input=next;
    if(encoded!==old){old=encoded;emit('input',next);}
    for(const [vk,label] of [[117,'dig'],[118,'fill'],[119,'trowel'],[120,'baseline'],[121,'capture']]){
      const pressed=down(vk);
      if(pressed&&!keys[vk]){
        if(label==='capture')requestCapture('manual_F10');
        else{phase=label;phaseSerial++;capturePending=label!=='baseline';
          emit('phase_marker',{label,source:'user F6/F7/F8/F9'});}
      }
      keys[vk]=pressed;
    }
  },40);
}catch(e){send({kind:'input_unavailable',message:String(e)});}

function install(m) {
 if(installed)return;installed=true;
 try {
  const api=(n,r,a)=>new NativeFunction(m.getExportByName('il2cpp_'+n),r,a);
  const domain=api('domain_get','pointer',[]),assemblies=api('domain_get_assemblies','pointer',['pointer','pointer']);
  const image=api('assembly_get_image','pointer',['pointer']),find=api('class_from_name','pointer',['pointer','pointer','pointer']);
  const cls=api('object_get_class','pointer',['pointer']),className=api('class_get_name','pointer',['pointer']);
  const methods=api('class_get_methods','pointer',['pointer','pointer']),methodName=api('method_get_name','pointer',['pointer']);
  const paramCount=api('method_get_param_count','uint',['pointer']),param=api('method_get_param','pointer',['pointer','uint']);
  const typeName=api('type_get_name','pointer',['pointer']),getMethod=api('class_get_method_from_name','pointer',['pointer','pointer','int']);
  const invoke=api('runtime_invoke','pointer',['pointer','pointer','pointer','pointer']);
  const field=api('class_get_field_from_name','pointer',['pointer','pointer']),offset=api('field_get_offset','int',['pointer']);
  const arrayHeader=api('array_object_header_size','uint',[])();
  const q=Process.getModuleByName('kernel32.dll');
  const qpc=new NativeFunction(q.getExportByName('QueryPerformanceCounter'),'bool',['pointer']);
  const qpf=new NativeFunction(q.getExportByName('QueryPerformanceFrequency'),'bool',['pointer']);
  const qp=Memory.alloc(8),fp=Memory.alloc(8);qpf(fp);
  function stamp(){qpc(qp);return qp.readS64().toString();}
  const classes=new Map();
  function findClass(ns,name){const id=ns+'.'+name;if(classes.has(id))return classes.get(id);
    const p=Memory.alloc(8),list=assemblies(domain(),p),count=Number(p.readU64());
    if(count>10000)throw Error('assembly count');
    for(let i=0;i<count;i++){const k=find(image(list.add(i*8).readPointer()),Memory.allocUtf8String(ns),Memory.allocUtf8String(name));if(!k.isNull()){classes.set(id,k);return k;}}
    throw Error('class unavailable '+id);
  }
  function getOffset(k,name){const f=field(k,Memory.allocUtf8String(name));if(f.isNull())throw Error('field unavailable '+name);return offset(f);}
  const objectClass=findClass('UnityEngine','Object');
  const cachedOffset=getOffset(objectClass,'m_CachedPtr');
  const getName=getMethod(objectClass,Memory.allocUtf8String('get_name'),0);
  function objectName(o){const exc=Memory.alloc(8);exc.writePointer(nil);const r=invoke(getName,o,nil,exc);if(!exc.readPointer().isNull())return '<name unavailable>';return utf16(r);}
  const shaderMap=new Map(),buffers=new Map(),propertyNames=new Map(),hooked=new Set();
  function shader(o){const native=o.add(cachedOffset).readPointer().toString();let s=shaderMap.get(native);
    if(!s){s={object:String(o),native,name:objectName(o),kernels:{},parameters:{},bindings:{}};shaderMap.set(native,s);emit('shader_identity',{object:s.object,native,name:s.name});}return s;}
  function bufferKey(o){return String(o);}
  function signature(k){const it=Memory.alloc(8);it.writePointer(nil);const list=[];
    for(;;){const mi=methods(k,it);if(mi.isNull())break;const name=methodName(mi).readUtf8String(),n=paramCount(mi);
      const types=Array.from({length:n},(_,i)=>typeName(param(mi,i)).readUtf8String());
      list.push({mi,pointer:mi.readPointer(),name,types});}return list;
  }
  function hook(row,callbacks,label){const p=row.pointer;if(p.isNull())return;
    if(hooked.has(String(p))){emit('hook_alias_skipped',{label,pointer:String(p)});return;}
    const range=Process.findRangeByAddress(p);if(!range||!range.protection.includes('x'))throw Error('method pointer not executable '+label);
    Interceptor.attach(p,callbacks);hooked.add(String(p));emit('hook_installed',{label,name:row.name,types:row.types,pointer:String(p)});
  }
  const shaderMethods=signature(findClass('UnityEngine','ComputeShader'));
  send({kind:'method_inventory',class:'UnityEngine.ComputeShader',methods:shaderMethods.map(x=>({name:x.name,types:x.types,pointer:String(x.pointer)}))});
  for(const row of shaderMethods){
    const n=row.name,t=row.types;
    if(n==='FindKernel'&&t.join() === 'System.String')hook(row,{
      onEnter(args){try{this.s=shader(args[0]);this.kernel=utf16(args[1]);}catch(e){error(n,e);}},
      onLeave(ret){if(this.s){this.s.kernels[ret.toInt32()]=this.kernel;emit('kernel_identity',{shader:this.s.native,name:this.s.name,kernel:ret.toInt32(),kernel_name:this.kernel});}}
    },'ComputeShader.FindKernel');
    else if(n==='Dispatch'&&t.join()==='System.Int32,System.Int32,System.Int32,System.Int32')hook(row,{
      onEnter(args){try{this.started=stamp();this.s=shader(args[0]);this.k=args[1].toInt32();
        const kernel=this.s.kernels[this.k]||'<unresolved>';const paint=/paint/i.test(kernel);this.paint=paint;stats.dispatch++;
        if(paint){lastPaint=Date.now();stats.paint++;if(capturePending && requestCapture('first_paint_after_phase_marker'))capturePending=false;}
        const bindingSnapshot=paint?JSON.parse(JSON.stringify(this.s.bindings)):undefined;
        if(paint)for(const b of Object.values(bindingSnapshot))for(const v of Object.values(b))v.upload=buffers.get(v.object)||v.upload;
        emit('dispatch',{qpc:this.started,shader:this.s.native,name:this.s.name,kernel:this.k,kernel_name:kernel,
          groups:[args[2].toInt32(),args[3].toInt32(),args[4].toInt32()],
          input,parameters:paint?{...this.s.parameters}:undefined,
          bindings:bindingSnapshot});
      }catch(e){error(n,e);}},
      onLeave(){if(this.paint)emit('dispatch_return',{shader:this.s.native,kernel:this.k,qpc:stamp(),entry_qpc:this.started,
        meaning:'CPU submission return; NOT GPU completion'});}
    },'ComputeShader.Dispatch');
    else if(n==='SetFloat'&&t.join()==='System.Int32,System.Single'){
      // Forward the typed Win64 float and hidden MethodInfo unchanged. Native
      // callbacks expose XMM values correctly; args[2] would be an integer slot.
      const original=new NativeFunction(row.pointer,'void',['pointer','int','float','pointer']);
      const callback=new NativeCallback((o,id,value,mi)=>{
        try{shader(o).parameters[id]={property:propertyNames.get(id)||null,kind:'SetFloat',value:Number.isFinite(value)?value:String(value)};}catch(e){error('SetFloat',e);}
        original(o,id,value,mi);
      },'void',['pointer','int','float','pointer']);
      replacements.push(callback);Interceptor.replace(row.pointer,callback);hooked.add(String(row.pointer));
      emit('hook_installed',{label:'ComputeShader.SetFloat',types:t,abi:'Win64 typed float; MethodInfo forwarded'});
    }
    else if(['SetVector','SetMatrix','SetInt','SetBool','SetFloats','SetInts','SetBuffer','SetTexture','SetConstantBuffer'].includes(n)&&t[0]==='System.Int32')hook(row,{
      onEnter(args){try{const s=shader(args[0]);let id=args[1].toInt32(),value=null;
        if(n==='SetConstantBuffer'){
          s.parameters[id]={property:propertyNames.get(id)||null,kind:n,object:String(args[2]),byte_offset:args[3].toInt32(),byte_size:args[4].toInt32()};return;
        }
        if(n==='SetBuffer'||n==='SetTexture'){
          if(t[1]!=='System.Int32')return;
          const kernel=id;id=args[2].toInt32();const object=String(args[3]);
          if(!s.bindings[kernel])s.bindings[kernel]={};
          s.bindings[kernel][id]={kind:n,object,upload:buffers.get(object)||null};
          emit('binding',{shader:s.native,kernel,property_id:id,property:propertyNames.get(id),binding_kind:n,object});return;
        }
        if(n==='SetInt'||n==='SetBool')value=args[2].toInt32();
        else if(n==='SetVector')value=cleanFloats(floats(args[2],4));
        else if(n==='SetMatrix')value=cleanFloats(floats(args[2],16));
        else {const len=Number(args[2].add(arrayHeader-8).readU64());if(len>256)return;
          value=n==='SetFloats'?cleanFloats(floats(args[2].add(arrayHeader),len)):ints(args[2].add(arrayHeader),len);}
        s.parameters[id]={property:propertyNames.get(id)||null,kind:n,value};
      }catch(e){error(n,e);}}
    },'ComputeShader.'+n+'('+t.join(',')+')');
  }
  // Strings are mapped at the engine's PropertyToID boundary.
  for(const row of signature(findClass('UnityEngine','Shader'))){if(row.name==='PropertyToID'&&row.types.join()==='System.String')hook(row,{
    onEnter(args){try{this.name=utf16(args[0]);}catch(e){}},onLeave(ret){if(this.name){propertyNames.set(ret.toInt32(),this.name);emit('property_identity',{id:ret.toInt32(),name:this.name});}}
  },'Shader.PropertyToID');}
  for(const classLabel of ['ComputeBuffer','GraphicsBuffer']){
    const rows=signature(findClass('UnityEngine',classLabel));
    send({kind:'method_inventory',class:'UnityEngine.'+classLabel,methods:rows.map(x=>({name:x.name,types:x.types,pointer:String(x.pointer)}))});
    for(const row of rows){if(!['InternalSetData','InternalSetNativeData'].includes(row.name))continue;
      if(row.types.length!==5 || row.types.slice(1).join()!=='System.Int32,System.Int32,System.Int32,System.Int32')continue;
      hook(row,{onEnter(args){try{
        const key=bufferKey(args[0]),start=args[2].toInt32(),dst=args[3].toInt32(),count=args[4].toInt32(),stride=args[5].toInt32();
        if(start<0||dst<0||count<0||stride<=0||stride>4096)return;
        stats.upload++;if(count*stride>4096)return;
        const p=args[1].add(row.name==='InternalSetData'?arrayHeader:0).add(start*stride);
        const detail={buffer:key,api:classLabel+'.'+row.name,source_start:start,destination_start:dst,count,stride,qpc:stamp()};
        const id=raw('buffer_upload',p,count*stride,detail);
        buffers.set(key,{raw_id:id,...detail});emit('buffer_upload',{raw_id:id,...detail});
      }catch(e){error(classLabel+'.'+row.name,e);}}},classLabel+'.'+row.name);
    }
  }
  const rbClass=findClass('','Readback');
  const arrOff=getOffset(rbClass,'readbackCells'),ptrOff=getOffset(rbClass,'readbackCellsPtr');
  send({kind:'readback_layout',class:'Readback',array_offset:arrOff,pointer_offset:ptrOff,stride:32,
    fields:{velocity:0,ground_tangent:8,water_amount:16,sand_amount:20,ground_height:24,crest_spawn:28},
    verification:'published CPU cache; not an isolated GPU Paint output'});
  const rbStates=new Map();
  for(const [rva,label] of [[0x4653e0,'async_callback'],[0x4654b0,'synchronous_GetData']]){
    Interceptor.attach(m.base.add(rva),{
      onEnter(args){try{this.o=args[0];if(!cls(this.o).equals(rbClass)){this.o=null;return;}
        this.key=String(this.o);let state=rbStates.get(this.key);if(!state){state={seq:0,depth:0,last:0};rbStates.set(this.key,state);}state.depth++;this.start=stamp();
      }catch(e){this.o=null;error('readback_enter',e);}},
      onLeave(){if(!this.o)return;try{const state=rbStates.get(this.key);state.depth--;state.seq++;stats.readback++;
        const now=Date.now(),active=(input&&(input.left||input.right))||now-lastPaint<1500;
        if(state.depth!==0||now-state.last<(active?cfg.snapshot_active_ms:cfg.snapshot_idle_ms))return;
        state.last=now;const p=this.o.add(arrOff).readPointer(),n=this.o.add(arrOff+8).readS32(),p2=this.o.add(ptrOff).readPointer();
        if(p.isNull()||!p.equals(p2)||n<=0||n>262144)throw Error('readback pointer/count mismatch');
        const id=raw('readback_cells',p,n*32,{readback:this.key,writer:label,copy_seq:state.seq,
          count:n,stride:32,entry_qpc:this.start,published_qpc:stamp(),active,input});
        emit('readback_published',{raw_id:id,readback:this.key,copy_seq:state.seq,count:n,active});
      }catch(e){error('readback_leave',e);}}
    });
    emit('hook_installed',{label:'Readback.'+label,rva:'0x'+rva.toString(16)});
  }
  send({kind:'hooks_ready',pid:Process.id,module:m.path,base:String(m.base),array_header:arrayHeader,
    cached_pointer_offset:cachedOffset,qpc_frequency:fp.readS64().toString(),hook_count:hooked.size+2,
    limitations:['Readback is downsampled published cache',
      'CPU dispatch return is not GPU completion','RenderDoc captures affect frame latency']});
 }catch(e){send({kind:'install_error',message:String(e),stack:e.stack});}
}
let observed=false;
Process.attachModuleObserver({onAdded(m){
 if(observed||m.name.toLowerCase()!=='gameassembly.dll')return;observed=true;
 send({kind:'module',pid:Process.id,path:m.path,base:String(m.base),size:m.size});
 Interceptor.attach(m.getExportByName('il2cpp_init'),{onLeave(){install(m);}});
}});
setInterval(flush,250);
setInterval(()=>send({kind:'heartbeat',utc_ms:Date.now(),phase,phase_serial:phaseSerial,
  stats:{...stats},raw_bytes:rawBytes,capture_count:captureCount,hooks_attempted:installed}),2000);
rpc.exports={flush(){flush();return {...stats};}};
