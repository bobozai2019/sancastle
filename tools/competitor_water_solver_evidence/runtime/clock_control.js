'use strict';
// Controlled public engine API experiment. No game classes, methods or business flow.
(() => {
 const cfg=globalThis.CLOCK_CONTROL_CONFIG;
 const state={installed:false,errors:0,source_returns:0,actions:0,armed:false},keep=[],kernels=new Map();
 let epoch=null,seq=0,offset=null,enabled=true,targetScale=null,insideSetter=false;
 state.scale_setter_returns=0;state.reassertions=0;
 const k32=Process.getModuleByName('kernel32.dll'),counter=Memory.alloc(8),frequency=Memory.alloc(8);
 const qpc=new NativeFunction(k32.getExportByName('QueryPerformanceCounter'),'bool',['pointer'],{scheduling:'exclusive'});
 new NativeFunction(k32.getExportByName('QueryPerformanceFrequency'),'bool',['pointer'])(frequency);
 const freq=Number(frequency.readS64());
 function stamp(){qpc(counter);return counter.readS64().toString();}
 function emit(kind,data={}){send({kind:'clock_control',event:{seq:++seq,kind,qpc:stamp(),thread:Process.getCurrentThreadId(),...data}});}
 function fail(where,error){state.errors++;emit('control_error',{where,error:String(error)});}
 function managedText(p){const n=p.add(16).readS32();if(n<0||n>4096)throw Error('String length');return p.add(20).readUtf16String(n);}
 function install(module){
  try {
   const api=(n,r,a)=>new NativeFunction(module.getExportByName('il2cpp_'+n),r,a);
   const resolve=api('resolve_icall','pointer',['pointer']),domain=api('domain_get','pointer',[]),assemblies=api('domain_get_assemblies','pointer',['pointer','pointer']),image=api('assembly_get_image','pointer',['pointer']),find=api('class_from_name','pointer',['pointer','pointer','pointer']);
   const methods=api('class_get_methods','pointer',['pointer','pointer']),methodName=api('method_get_name','pointer',['pointer']),paramCount=api('method_get_param_count','uint',['pointer']),param=api('method_get_param','pointer',['pointer','uint']),typeName=api('type_get_name','pointer',['pointer']);
   function cls(name){const count=Memory.alloc(8),list=assemblies(domain(),count),n=Number(count.readU64());if(n>10000)throw Error('Assembly count');for(let i=0;i<n;i++){const c=find(image(list.add(i*8).readPointer()),Memory.allocUtf8String('UnityEngine'),Memory.allocUtf8String(name));if(!c.isNull())return c;}throw Error('Missing UnityEngine.'+name);}
   const field=api('class_get_field_from_name','pointer',['pointer','pointer']),fieldOffset=api('field_get_offset','int',['pointer']);
   const f=field(cls('Object'),Memory.allocUtf8String('m_CachedPtr'));if(f.isNull())throw Error('Object identity');offset=fieldOffset(f);
   function icall(signature,ret,args){const target=resolve(Memory.allocUtf8String(signature)),m=target.isNull()?null:Process.findModuleByAddress(target);emit('control_icall',{signature,target:String(target),module:m?m.path:null,module_offset:m?String(target.sub(m.base)):null});if(target.isNull())throw Error('Public icall unavailable: '+signature);return new NativeFunction(target,ret,args,{exceptions:'propagate'});}
   const setScale=icall('UnityEngine.Time::set_timeScale(System.Single)','void',['float']);
   const getScale=icall('UnityEngine.Time::get_timeScale()','float',[]);
   const getFixed=icall('UnityEngine.Time::get_fixedDeltaTime()','float',[]);
   const inFixed=icall('UnityEngine.Time::get_inFixedTimeStep()','bool',[]);
   const setterAddress=resolve(Memory.allocUtf8String('UnityEngine.Time::set_timeScale(System.Single)'));
   keep.push(Interceptor.attach(setterAddress,{onLeave(){
    if(!enabled||insideSetter)return;
    try{state.scale_setter_returns++;const observed=getScale();
     if(cfg.hold_scale&&targetScale!==null&&observed!==targetScale){
      const begin=stamp();insideSetter=true;try{setScale(targetScale);}finally{insideSetter=false;}
      const actual=getScale();state.reassertions++;
      emit('control_reassert',{setter_return_index:state.scale_setter_returns,begin_qpc:begin,observed_scale:observed,requested_scale:targetScale,readback_scale:actual,meaning:'Explicit experiment holds public engine time scale against subsequent setters; not natural game behavior'});
      if(actual!==targetScale)throw Error('Reassert readback mismatch');
     }
    }catch(e){fail('scale_setter_return',e);}
   }}));
   const it=Memory.alloc(8);it.writePointer(ptr(0));let foundFind=false,foundDispatch=false;
   for(;;){const mi=methods(cls('ComputeShader'),it);if(mi.isNull())break;const name=methodName(mi).readUtf8String(),n=paramCount(mi),types=Array.from({length:n},(_,i)=>typeName(param(mi,i)).readUtf8String()),target=mi.readPointer();
    if(name==='FindKernel'&&types.join()==='System.String'){
     foundFind=true;keep.push(Interceptor.attach(target,{onEnter(a){if(!enabled)return;try{this.object=String(a[0].add(offset).readPointer());this.kernelName=managedText(a[1]);}catch(e){fail('FindKernel',e);}},onLeave(ret){if(this.kernelName){if(!kernels.has(this.object))kernels.set(this.object,{});kernels.get(this.object)[ret.toInt32()]=this.kernelName;}}}));
    } else if(name==='Dispatch'&&types.join()==='System.Int32,System.Int32,System.Int32,System.Int32'){
     foundDispatch=true;keep.push(Interceptor.attach(target,{onEnter(a){if(!enabled)return;try{const o=String(a[0].add(offset).readPointer()),names=kernels.get(o)||{};this.source=['UpdateFloor','VelocityIntegration','HeightIntegration','Advection','UpdateAmount','UpdateTangent'].every(n=>Object.values(names).includes(n))&&names[a[1].toInt32()]==='UpdateAmount';}catch(e){fail('Dispatch',e);}},onLeave(){if(!enabled||!this.source)return;try{state.source_returns++;if(epoch===null)return;const now=stamp(),elapsed=(Number(now)-Number(epoch))/freq;
      const action=cfg.actions[state.actions];if(!action||elapsed<action.at_seconds)return;
      const begin=stamp(),old=getScale(),fixed=getFixed(),fixedContext=inFixed();
      if(!fixedContext)throw Error('Control action requires observed fixed-step submission thread');
      targetScale=action.scale;insideSetter=true;try{setScale(action.scale);}finally{insideSetter=false;}const actual=getScale();state.actions++;
      emit('control_action',{action_index:state.actions-1,scheduled_seconds:action.at_seconds,elapsed_seconds:elapsed,begin_qpc:begin,old_scale:old,requested_scale:action.scale,readback_scale:actual,fixed_delta_time:fixed,in_fixed_step:fixedContext,source_return_index:state.source_returns,meaning:'Public Unity Time setter intervention after source CPU Dispatch; not game UI input or GPU completion'});
      if(actual!==action.scale)throw Error('Scale readback mismatch');
     }catch(e){fail('control_action',e);}}}));
    }
   }
   if(!foundFind||!foundDispatch)throw Error('Required engine boundary unavailable');state.installed=true;emit('control_installed',{cached_pointer_offset:offset,config:cfg});
  }catch(e){fail('install',e);}
 }
 keep.push(Process.attachModuleObserver({onAdded(m){if(m.name.toLowerCase()==='gameassembly.dll'){keep.push(Interceptor.attach(m.getExportByName('il2cpp_init'),{onLeave(){install(m);}}));}}}));
 rpc.exports={arm(){epoch=stamp();state.armed=true;emit('control_arm',{epoch_qpc:epoch,qpc_frequency:String(freq)});return {...state,epoch_qpc:epoch};},status(){return {...state,last_seq:seq};},finish(){enabled=false;emit('control_finish',{...state});return {...state,last_seq:seq};}};
 emit('control_loaded',{qpc_frequency:String(freq),scope:'Owned public Unity Time API experiment only'});
})();
