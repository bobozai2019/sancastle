'use strict';
// Unity engine API boundaries only. No game method/RVA inspection or invocation.
const keep=[],stats={installed:false,events:0,dropped:0,errors:0,dispatches:0,inflight:0,command_clears:0},kernels=new Map(),params=new Map(),bindings=new Map(),globals={},names=new Map(),hooked=new Set(),unsupported=new Map(),reportedUnsupported=new Set();
let queue=[],seq=0,accepting=true,callId=0,cachedOffset=null;
const traceConfig=globalThis.TRACE_CONFIG||{},paramVersions=new Map(),bindingVersions=new Map(),snapshotCache=new Map();let globalVersion=0,nextSnapshot=0;
const hotListeners=[],hotReplacements=[],hotSpecifications=[];let diagnosticFragment=0;
let clockGetters=[],sourceCalls=0;
const scalarTargets={};let scalarBridge=null;
const k32=Process.getModuleByName('kernel32.dll'),qpc=new NativeFunction(k32.getExportByName('QueryPerformanceCounter'),'bool',['pointer'],{scheduling:'exclusive'}),qpf=new NativeFunction(k32.getExportByName('QueryPerformanceFrequency'),'bool',['pointer'],{scheduling:'exclusive'});
const counter=Memory.alloc(8),frequency=Memory.alloc(8);qpf(frequency);
function stamp(){qpc(counter);return counter.readS64().toString();}
function emit(kind,data={}){const timestamp=stamp(),thread=Process.getCurrentThreadId();if(queue.length>=8192){stats.dropped++;return;}const event={seq:++seq,kind,qpc:timestamp,thread,...data};queue.push(event);stats.events++;}
function flush(){if(queue.length){const events=queue;queue=[];send({kind:'water_trace',events});}}
function fail(where,e){stats.errors++;emit('hook_error',{where,message:String(e)});}
function text(p){if(p.isNull())return null;const n=p.add(16).readS32();if(n<0||n>4096)throw Error('Invalid managed string length');return p.add(20).readUtf16String(n);}
function values(p,n){return Array.from({length:n},(_,i)=>{const v=p.add(i*4).readFloat();return Number.isFinite(v)?v:String(v);});}
function equalValue(a,b){return Array.isArray(a)&&Array.isArray(b)?a.length===b.length&&a.every((v,i)=>Object.is(v,b[i])):Object.is(a,b);}
function equalRecord(a,b){return !!a&&a.kind===b.kind&&a.property===b.property&&equalValue(a.value,b.value)&&a.object===b.object&&a.byte_offset===b.byte_offset&&a.byte_size===b.byte_size&&a.mip===b.mip&&a.value_bits===b.value_bits&&(!('value_since_qpc' in b)||a.value_since_qpc===b.value_since_qpc);}
function setParam(key,id,value){const previous=params.get(key)||{};if(equalRecord(previous[id],value))return;params.set(key,{...previous,[id]:value});paramVersions.set(key,(paramVersions.get(key)||0)+1);}
function setBinding(key,kernel,id,value){const previous=bindings.get(key)||{},perKernel=previous[kernel]||{};if(equalRecord(perKernel[id],value))return;bindings.set(key,{...previous,[kernel]:{...perKernel,[id]:value}});bindingVersions.set(key,(bindingVersions.get(key)||0)+1);}
function setGlobal(id,value){if(equalRecord(globals[id],value))return;globals[id]={...value,value_since_qpc:value.value_since_qpc||stamp()};globalVersion++;}
function synchronizeScalars(){if(!scalarBridge)return;const rows=scalarBridge.drain();for(const row of rows){const value={kind:row.kind===1?'SetFloat_Injected':'SetGlobalFloatImpl',property:names.get(row.property_id)||null,value:row.value,value_bits:row.value_bits,value_since_qpc:row.qpc};if(row.kind===1)setParam(row.object,row.property_id,value);else if(row.kind===2)setGlobal(row.property_id,value);else throw Error('Invalid native scalar kind');}const status=scalarBridge.status();stats.native_scalar=status;if(status.overflow)throw Error('NATIVE_SCALAR_OVERFLOW');}
function snapshot(scope,key,version,data){const cacheKey=scope+':'+key,previous=snapshotCache.get(cacheKey);if(previous&&previous.version===version)return previous.id;const id=++nextSnapshot;emit('state_snapshot',{snapshot_id:id,scope,key,version,values:scope==='global_parameters'?{...data}:data});snapshotCache.set(cacheKey,{version,id});return id;}
function object(o){return String(cachedOffset===null?o:o.add(cachedOffset).readPointer());} // Native Unity object pointer; lifetime/reuse not inferred.
function state(map,o){const key=object(o);if(!map.has(key))map.set(key,{});return map.get(key);}
function water(o,k){const found=kernels.get(object(o))||{},required=['UpdateFloor','VelocityIntegration','HeightIntegration','Advection','UpdateAmount','UpdateTangent'];return required.every(n=>Object.values(found).includes(n))&&required.includes(found[k]);}
function nativeWater(o){const found=kernels.get(String(o))||{};return ['UpdateFloor','VelocityIntegration','HeightIntegration','Advection','UpdateAmount','UpdateTangent'].every(n=>Object.values(found).includes(n));}
function install(module){
 if(stats.installed)return;stats.installed=true;
 try{
 const api=(n,r,a)=>new NativeFunction(module.getExportByName('il2cpp_'+n),r,a);
 const domain=api('domain_get','pointer',[]),assemblies=api('domain_get_assemblies','pointer',['pointer','pointer']),image=api('assembly_get_image','pointer',['pointer']),find=api('class_from_name','pointer',['pointer','pointer','pointer']);
 const methods=api('class_get_methods','pointer',['pointer','pointer']),methodName=api('method_get_name','pointer',['pointer']),paramCount=api('method_get_param_count','uint',['pointer']),param=api('method_get_param','pointer',['pointer','uint']),typeName=api('type_get_name','pointer',['pointer']);
 const returnType=api('method_get_return_type','pointer',['pointer']);
 const field=api('class_get_field_from_name','pointer',['pointer','pointer']),offset=api('field_get_offset','int',['pointer']);
 const resolve=api('resolve_icall','pointer',['pointer']);
 {const cp=Memory.alloc(8),list=assemblies(domain(),cp),count=Number(cp.readU64());if(count>10000)throw Error('Assembly count');for(let i=0;i<count;i++){const cls=find(image(list.add(i*8).readPointer()),Memory.allocUtf8String('UnityEngine'),Memory.allocUtf8String('Object'));if(!cls.isNull()){const f=field(cls,Memory.allocUtf8String('m_CachedPtr'));if(f.isNull())throw Error('Missing m_CachedPtr');cachedOffset=offset(f);break;}}if(cachedOffset===null)throw Error('Unity object identity unavailable');emit('object_identity_layout',{cached_pointer_offset:cachedOffset});}
 function rows(ns,name){
  const cp=Memory.alloc(8),list=assemblies(domain(),cp),count=Number(cp.readU64());if(count>10000)throw Error('Assembly count out of bounds');let cls=ptr(0);
  for(let i=0;i<count;i++){cls=find(image(list.add(i*8).readPointer()),Memory.allocUtf8String(ns),Memory.allocUtf8String(name));if(!cls.isNull())break;}
  if(cls.isNull()){emit('class_missing',{ns,name});return [];}
  const it=Memory.alloc(8);it.writePointer(ptr(0));const result=[];
  for(;;){const mi=methods(cls,it);if(mi.isNull())break;const n=paramCount(mi);result.push({pointer:mi.readPointer(),name:methodName(mi).readUtf8String(),return_type:typeName(returnType(mi)).readUtf8String(),types:Array.from({length:n},(_,i)=>typeName(param(mi,i)).readUtf8String())});}
  emit('method_inventory',{class:ns+'.'+name,methods:result.map(r=>({...r,pointer:String(r.pointer)}))});return result;
 }
 function hook(r,label,callbacks){
  if(r.pointer.isNull()){emit('method_unavailable',{label});return;}
  if(hooked.has(String(r.pointer))){emit('hook_alias_skipped',{label,pointer:String(r.pointer)});return;}
  hotListeners.push(Interceptor.attach(r.pointer,callbacks));hotSpecifications.push({address:r.pointer,callbacks});hooked.add(String(r.pointer));emit('hook_installed',{label,types:r.types,pointer:String(r.pointer)});
 }
 function nativeRow(r,cls){const signature=cls+'::'+r.name+'('+r.types.join(',')+')',target=resolve(Memory.allocUtf8String(signature)),mod=target.isNull()?null:Process.findModuleByAddress(target);emit('engine_icall_resolution',{signature,wrapper:String(r.pointer),target:String(target),module:mod?mod.path:null,module_base:mod?String(mod.base):null,module_offset:mod?String(target.sub(mod.base)):null});return {...r,pointer:target};}
 if(traceConfig.clock_sample_every>0){
  const wanted=['get_time','get_unscaledTime','get_fixedTime','get_realtimeSinceStartup','get_deltaTime','get_unscaledDeltaTime','get_fixedDeltaTime','get_maximumDeltaTime','get_timeScale','get_frameCount','get_inFixedTimeStep'];
  const found=new Set();for(const row of rows('UnityEngine','Time'))if(wanted.includes(row.name)&&row.types.length===0){
   found.add(row.name);const r=nativeRow(row,'UnityEngine.Time'),ret=({'System.Single':'float','System.Double':'double','System.Int32':'int','System.Boolean':'bool'})[row.return_type];
   if(r.pointer.isNull()||!ret){emit('clock_getter_unavailable',{name:row.name,return_type:row.return_type});continue;}
   clockGetters.push({name:row.name,read:new NativeFunction(r.pointer,ret,[],{exceptions:'propagate'})});
  }
  for(const name of wanted)if(!found.has(name)){
   const ret=({'get_fixedTime':'float','get_maximumDeltaTime':'float','get_timeScale':'float','get_inFixedTimeStep':'bool'})[name];
   if(!ret){emit('clock_getter_unavailable',{name,reason:'Absent from metadata; no public signature registered for this probe'});continue;}
   const signature='UnityEngine.Time::'+name+'()',target=resolve(Memory.allocUtf8String(signature)),mod=target.isNull()?null:Process.findModuleByAddress(target);
   emit('clock_getter_public_resolution',{name,signature,return_type:ret,target:String(target),module:mod?mod.path:null,module_offset:mod?String(target.sub(mod.base)):null,signature_source:'UnityCsReference Runtime/Export/Time/Time.bindings.cs; actual runtime icall registry is authoritative',metadata_wrapper_present:false});
   if(target.isNull()){emit('clock_getter_unavailable',{name,reason:'Public engine signature absent from actual icall registry'});continue;}
   clockGetters.push({name,read:new NativeFunction(target,ret,[],{exceptions:'propagate'})});
  }
 }
 for(const r of rows('UnityEngine','ComputeShader')){
  const n=r.name,t=r.types.join();
  if(n.endsWith('_Injected')){
   const signature='UnityEngine.ComputeShader::'+n+'('+r.types.join(',')+')',target=resolve(Memory.allocUtf8String(signature));
   emit('engine_icall_resolution',{signature,wrapper:String(r.pointer),target:String(target)});
   if(target.isNull())continue;r.pointer=target;
  }
  if(n==='FindKernel'&&t==='System.String')hook(r,'ComputeShader.FindKernel',{
   onEnter(a){try{this.o=object(a[0]);this.name=text(a[1]);}catch(e){fail(n,e);}},
   onLeave(ret){if(this.name){if(!kernels.has(this.o))kernels.set(this.o,{});const id=ret.toInt32(),changed=kernels.get(this.o)[id]!==this.name;kernels.get(this.o)[id]=this.name;if(changed)emit('kernel_identity',{shader:this.o,kernel:id,name:this.name,identity_kind:'Engine name set only; original DXBC mapping unproven'});}}
  });
  else if(n==='Dispatch'&&t==='System.Int32,System.Int32,System.Int32,System.Int32')hook(r,'ComputeShader.Dispatch',{
   onEnter(a){if(!accepting)return;try{const k=a[1].toInt32(),o=object(a[0]);if(!water(a[0],k))return;synchronizeScalars();if(unsupported.has(o)&&!reportedUnsupported.has(o)){reportedUnsupported.add(o);stats.errors++;emit('unsupported_water_parameter_path',{shader:o,paths:unsupported.get(o),meaning:'Fail closed; raw path observation is not decoded parameter coverage'});}this.id=++callId;stats.inflight++;stats.dispatches++;const refs={parameters:snapshot('parameters',o,paramVersions.get(o)||0,params.get(o)||{}),bindings:snapshot('bindings',o,bindingVersions.get(o)||0,bindings.get(o)||{}),global_parameters:snapshot('global_parameters','global',globalVersion,globals)};emit('dispatch_enter',{call_id:this.id,shader:o,kernel:k,kernel_name:kernels.get(o)[k],groups:[a[2].toInt32(),a[3].toInt32(),a[4].toInt32()],state_refs:refs});if(traceConfig.shadow_every>0&&this.id%traceConfig.shadow_every===0)emit('state_shadow',{call_id:this.id,parameters:params.get(o)||{},bindings:bindings.get(o)||{},global_parameters:{...globals}});if(kernels.get(o)[k]==='UpdateAmount'&&traceConfig.clock_sample_every>0){sourceCalls++;if(sourceCalls===1||sourceCalls%traceConfig.clock_sample_every===0){const begin=stamp(),readings={};for(const getter of clockGetters)readings[getter.name]=getter.read();emit('engine_clock_sample',{call_id:this.id,source_call_index:sourceCalls,begin_qpc:begin,values:readings,meaning:'Read-only Unity Time native getters on the intercepted CPU submission thread; not GPU completion'});}}}catch(e){fail(n,e);}},
   onLeave(){if(this.id){emit('dispatch_return',{call_id:this.id,meaning:'CPU API return; not GPU completion'});stats.inflight--;}}
  });
  else if(n==='SetFloat_Injected'&&t==='System.IntPtr,System.Int32,System.Single'){
   if(traceConfig.native_scalars){scalarTargets.compute=r;continue;}
   if(hooked.has(String(r.pointer))||r.pointer.isNull())continue;
   const original=new NativeFunction(r.pointer,'void',['pointer','int','float']);
   const callback=new NativeCallback((o,id,v)=>{try{setParam(String(o),id,{kind:n,property:names.get(id)||null,value:Number.isFinite(v)?v:String(v)});}catch(e){fail(n,e);}original(o,id,v);},'void',['pointer','int','float']);
   keep.push(callback);Interceptor.replace(r.pointer,callback);hotReplacements.push({address:r.pointer,callback});hooked.add(String(r.pointer));emit('hook_installed',{label:'ComputeShader.SetFloat_Injected native icall',types:r.types,abi:'Typed Win64 float; native icall has no MethodInfo'});
  }
  else if(['SetInt_Injected','SetVector_Injected','SetMatrix_Injected','Internal_SetBuffer_Injected','SetTexture_Injected'].includes(n)&&r.types[0]==='System.IntPtr')hook(r,'ComputeShader.'+n+'('+t+')',{
   onEnter(a){try{
    const key=String(a[0]);
    if(['Internal_SetBuffer_Injected','SetTexture_Injected'].includes(n)){const k=a[1].toInt32(),id=a[2].toInt32();setBinding(key,k,id,{kind:n,property:names.get(id)||null,object:String(a[3]),...(n==='SetTexture_Injected'?{mip:a[4].toInt32()}:{})});}
    else{const id=a[1].toInt32(),v=n==='SetInt_Injected'?a[2].toInt32():values(a[2],n==='SetVector_Injected'?4:16);setParam(key,id,{kind:n,property:names.get(id)||null,value:v});}
   }catch(e){fail(n,e);}}
  });
  else if(n==='SetConstantComputeBuffer_Injected')hook(r,'ComputeShader.'+n,{
   onEnter(a){try{setParam(String(a[0]),a[1].toInt32(),{kind:n,property:names.get(a[1].toInt32())||null,object:String(a[2]),byte_offset:a[3].toUInt32(),byte_size:a[4].toUInt32()});}catch(e){fail(n,e);}}
  });
  else if(n.endsWith('_Injected')&&n.startsWith('Set')&&r.types[0]==='System.IntPtr')hook(r,'ComputeShader.unmodeled.'+n,{
   onEnter(a){const key=String(a[0]);if(!unsupported.has(key))unsupported.set(key,[]);if(!unsupported.get(key).includes(n))unsupported.get(key).push(n);}
  });
 }
 for(const r of rows('UnityEngine','Shader')){
  if(r.name==='PropertyToID'&&r.types.join()==='System.String')hook(r,'Shader.PropertyToID',{
   onEnter(a){try{this.name=text(a[0]);}catch(e){fail(r.name,e);}},onLeave(ret){if(this.name){const id=ret.toInt32(),changed=names.get(id)!==this.name;names.set(id,this.name);if(changed)emit('property_identity',{id,name:this.name});}}
  });
  else if(r.name==='SetGlobalFloatImpl'&&r.types.join()==='System.Int32,System.Single'){
   const nr=nativeRow(r,'UnityEngine.Shader');if(nr.pointer.isNull())continue;
   if(traceConfig.native_scalars){scalarTargets.global=nr;continue;}
   const original=new NativeFunction(nr.pointer,'void',['int','float']);
   const callback=new NativeCallback((id,v)=>{setGlobal(id,{kind:r.name,property:names.get(id)||null,value:Number.isFinite(v)?v:String(v)});original(id,v);},'void',['int','float']);keep.push(callback);Interceptor.replace(nr.pointer,callback);hotReplacements.push({address:nr.pointer,callback});hooked.add(String(nr.pointer));emit('hook_installed',{label:'Shader.SetGlobalFloatImpl native icall',types:r.types});
  }
  else if(['SetGlobalVectorImpl_Injected','SetGlobalTextureImpl_Injected','SetGlobalBufferImpl_Injected','SetGlobalConstantBufferImpl_Injected'].includes(r.name)){
   const nr=nativeRow(r,'UnityEngine.Shader');hook(nr,'Shader.'+r.name,{
    onEnter(a){try{const id=a[0].toInt32();setGlobal(id,{kind:r.name,property:names.get(id)||null,value:r.name==='SetGlobalVectorImpl_Injected'?values(a[1],4):String(a[1])});}catch(e){fail(r.name,e);}}
   });
  }
 }
 if(traceConfig.native_scalars){
  if(!scalarTargets.compute||!scalarTargets.global)throw Error('Native scalar targets unavailable');
  scalarBridge=makeScalarBridge(scalarTargets.compute.pointer,scalarTargets.global.pointer);keep.push(scalarBridge);
  hook(scalarTargets.compute,'ComputeShader.SetFloat native XMM onEnter',{onEnter:scalarBridge.computeEnter});
  hook(scalarTargets.global,'Shader.SetGlobalFloat native XMM onEnter',{onEnter:scalarBridge.globalEnter});
  emit('native_scalar_bridge_installed',{platform:Process.platform,arch:Process.arch,scope:'Native scalar cache only; other hooks remain JS; overflow invalidates trace',capacity:8192});
 }
 const cmdState=new Map();
 for(const r of rows('UnityEngine.Rendering','CommandBuffer')){
  if(!r.name.endsWith('_Injected'))continue;
  if(['Clear_Injected','ReleaseBuffer_Injected'].includes(r.name)){
   const nr=nativeRow(r,'UnityEngine.Rendering.CommandBuffer');hook(nr,'CommandBuffer.'+r.name,{onEnter(a){stats.command_clears++;const cmd=String(a[0]);if(cmdState.has(cmd))emit('command_lifecycle',{method:r.name,command_buffer:cmd});cmdState.delete(cmd);}});
  }
  else if(r.name==='SetComputeFloatParam_Injected'){
   const nr=nativeRow(r,'UnityEngine.Rendering.CommandBuffer');if(nr.pointer.isNull())continue;
   const original=new NativeFunction(nr.pointer,'void',['pointer','pointer','int','float']);
   const callback=new NativeCallback((cmd,shader,id,v)=>{if(accepting&&nativeWater(shader)){cmdState.set(String(cmd),true);emit('command_record',{command_buffer:String(cmd),shader:String(shader),method:r.name,property_id:id,property:names.get(id)||null,value:Number.isFinite(v)?v:String(v),meaning:'Recorded command; not execution'});}original(cmd,shader,id,v);},'void',['pointer','pointer','int','float']);keep.push(callback);Interceptor.replace(nr.pointer,callback);hotReplacements.push({address:nr.pointer,callback});hooked.add(String(nr.pointer));emit('hook_installed',{label:'CommandBuffer.'+r.name,types:r.types});
  }
  else if(r.name.includes('Compute')&&r.types[0]==='System.IntPtr'&&r.types[1]==='System.IntPtr'&&(r.name.includes('SetCompute')||r.name.includes('ComputeFloat')||r.name.includes('ComputeInt'))&&!['SetComputeIntParam_Injected','SetComputeVectorParam_Injected','SetComputeMatrixParam_Injected','Internal_SetComputeBufferParam_Injected','Internal_SetComputeGraphicsBufferParam_Injected','Internal_SetComputeTextureParam_Injected','Internal_SetComputeConstantComputeBufferParam_Injected','Internal_SetComputeConstantGraphicsBufferParam_Injected'].includes(r.name)){
   const nr=nativeRow(r,'UnityEngine.Rendering.CommandBuffer');hook(nr,'CommandBuffer.unmodeled.'+r.name,{onEnter(a){if(accepting&&nativeWater(a[1])){stats.errors++;emit('unsupported_water_command_path',{method:r.name,command_buffer:String(a[0]),shader:String(a[1]),meaning:'Fail closed; unmodeled command'});}}});
  }
  else if(['SetComputeIntParam_Injected','SetComputeVectorParam_Injected','SetComputeMatrixParam_Injected','Internal_DispatchCompute_Injected','Internal_DispatchComputeIndirect_Injected','Internal_DispatchComputeIndirectGraphicsBuffer_Injected','Internal_SetComputeBufferParam_Injected','Internal_SetComputeGraphicsBufferParam_Injected','Internal_SetComputeTextureParam_Injected','Internal_SetComputeConstantComputeBufferParam_Injected','Internal_SetComputeConstantGraphicsBufferParam_Injected'].includes(r.name)){
   const nr=nativeRow(r,'UnityEngine.Rendering.CommandBuffer');hook(nr,'CommandBuffer.'+r.name,{
    onEnter(a){if(!accepting||!nativeWater(a[1]))return;try{cmdState.set(String(a[0]),true);const detail={command_buffer:String(a[0]),shader:String(a[1]),method:r.name,meaning:'Recorded command; not execution'};
     if(r.name==='Internal_DispatchCompute_Injected'){detail.kernel=a[2].toInt32();detail.groups=[a[3].toInt32(),a[4].toInt32(),a[5].toInt32()];}
     else if(r.name==='SetComputeIntParam_Injected'){detail.property_id=a[2].toInt32();detail.value=a[3].toInt32();}
     else if(r.name==='SetComputeVectorParam_Injected'||r.name==='SetComputeMatrixParam_Injected'){detail.property_id=a[2].toInt32();detail.value=values(a[3],r.name==='SetComputeVectorParam_Injected'?4:16);}
     else{detail.arguments=Array.from({length:r.types.length},(_,i)=>String(a[i]));detail.decoding='Raw pointer/integer argument slots; compound structures not decoded';}
     emit('command_record',detail);
    }catch(e){fail(r.name,e);}}
   });
  }
 }
 for(const [ns,cls] of [['UnityEngine','Graphics'],['UnityEngine.Rendering','ScriptableRenderContext']]){
  for(const r of rows(ns,cls))if(r.name.includes('ExecuteCommandBuffer')&&r.name.endsWith('_Injected')){
   const nr=nativeRow(r,ns+'.'+cls);hook(nr,cls+'.'+r.name,{onEnter(a){if(!accepting)return;const cmd=String(a[cls==='Graphics'?0:1]);emit('command_execute_api',{method:cls+'.'+r.name,command_buffer:cmd,water_record_seen:cmdState.has(cmd),meaning:'CPU execution/submission API; not GPU completion. Tracking reset at Clear/ReleaseBuffer'});}});
  }
 }
 emit('coverage_limit',{uncovered:['Arrays/keywords fail closed if used by selected water object','CommandBuffer compound binding structures retain raw arguments','Object pointer reuse beyond observed lifecycle','Direct DispatchIndirect if absent from stripped metadata'],scope:'Full six-name-set object filter; only observed direct path can be accepted after GPU correspondence. Unmodeled paths fail closed'});
 emit('observer_installed',{module:module.path,base:String(module.base),qpc_frequency:frequency.readS64().toString()});flush();
 }catch(e){fail('install',e);flush();}
}
keep.push(Process.attachModuleObserver({onAdded(m){if(m.name.toLowerCase()==='gameassembly.dll'){
 emit('engine_module',{path:m.path,base:String(m.base)});
 try{Interceptor.attach(m.getExportByName('il2cpp_init'),{onLeave(){install(m);}});}catch(e){fail('il2cpp_init',e);}
}}}));
setInterval(flush,100);
emit('observer_loaded',{qpc_frequency:frequency.readS64().toString(),trace_schema:'2.0',state_encoding:'Immutable value snapshots with preceding IDs; unchanged setters do not advance value version',shadow_every:traceConfig.shadow_every||0});
rpc.exports={finish(){if(accepting){accepting=false;emit('window_close',{...stats});}flush();return {...stats,last_seq:seq};},detachhot(){if(accepting||stats.inflight)throw Error('Close and drain API calls before detaching');for(const listener of hotListeners)listener.detach();hotListeners.length=0;for(const item of hotReplacements)Interceptor.revert(item.address);Interceptor.flush();stats.hot_detached=true;emit('water_hooks_detached',{fragment:diagnosticFragment,meaning:'Diagnostic unobserved segment begins; not a full formal trace'});flush();return {...stats,last_seq:seq};},attachhot(){if(!stats.hot_detached||stats.inflight)throw Error('Only reattach a detached drained diagnostic probe');for(const item of hotSpecifications)hotListeners.push(Interceptor.attach(item.address,item.callbacks));for(const item of hotReplacements)Interceptor.replace(item.address,item.callback);Interceptor.flush();stats.hot_detached=false;accepting=true;diagnosticFragment++;emit('water_hooks_reattached',{fragment:diagnosticFragment,meaning:'Diagnostic timing only; parameter/binding changes during the gap are unknown, not a formal trajectory'});flush();return {...stats,last_seq:seq};},status(){return {...stats,last_seq:seq};}};
