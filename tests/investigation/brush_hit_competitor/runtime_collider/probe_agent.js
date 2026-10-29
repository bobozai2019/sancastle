'use strict';
// Calls only collision/mesh getters from the game's own update completion thread.
let installed=false, samples=0;
const nul=ptr(0);
function install(m) {
  if(installed || m.name.toLowerCase()!=='gameassembly.dll') return;
  installed=true;
  send({kind:'module',path:m.path,base:m.base.toString(),size:m.size,pid:Process.id});
  const api=(name,ret,args)=>new NativeFunction(m.getExportByName('il2cpp_'+name),ret,args);
  const klass=api('object_get_class','pointer',['pointer']);
  const method=api('class_get_method_from_name','pointer',['pointer','pointer','int']);
  const invoke=api('runtime_invoke','pointer',['pointer','pointer','pointer','pointer']);
  const unbox=api('object_unbox','pointer',['pointer']);
  const name=api('class_get_name','pointer',['pointer']);
  function call(o,n,params=[]) {
    const k=klass(o), mi=method(k,Memory.allocUtf8String(n),params.length);
    if(mi.isNull()) throw Error('api_unavailable '+name(k).readUtf8String()+'.'+n);
    const exc=Memory.alloc(8);exc.writePointer(nul);
    const argv=params.length?Memory.alloc(params.length*8):nul;
    params.forEach((p,i)=>argv.add(i*8).writePointer(p));
    const result=invoke(mi,o,argv,exc);
    if(!exc.readPointer().isNull()) throw Error('API exception '+n+' '+exc.readPointer());
    return result;
  }
  Interceptor.attach(m.base.add(0x45f120),{
    onEnter(args){this.chunk=args[0];},
    onLeave(){
      if(samples>=1) return;
      try {
        const c=this.chunk, collider=c.add(0x40).readPointer(), meshC=c.add(0x68).readPointer();
        const bound=call(collider,'get_sharedMesh');
        if(bound.isNull()) { send({kind:'error',code:'mesh_unbound'});return; }
        const vc=unbox(call(bound,'get_vertexCount')).readS32();
        send({kind:'getter_sample',chunk:c.toString(),collider:collider.toString(),meshC:meshC.toString(),bound:bound.toString(),vertex_count:vc,thread:Process.getCurrentThreadId(),class:name(klass(c)).readUtf8String(),same_mesh:bound.equals(meshC)});
        samples++;
      } catch(e){send({kind:'error',code:'runtime_unavailable',message:String(e),stack:e.stack});samples++;}
    }
  });
  send({kind:'hook_installed',rva:'0x45f120'});
}
Process.attachModuleObserver({onAdded:install});
