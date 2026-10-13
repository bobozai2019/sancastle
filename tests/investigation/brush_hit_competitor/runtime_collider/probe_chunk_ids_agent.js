'use strict';
// Read-only current Ground membership -> collider GetInstanceID map, on game's main update thread.
let installed=false,done=false;
Process.attachModuleObserver({onAdded(m){
 if(installed||m.name.toLowerCase()!=='gameassembly.dll')return;installed=true;
 const api=(n,r,a)=>new NativeFunction(m.getExportByName('il2cpp_'+n),r,a);
 const cls=api('object_get_class','pointer',['pointer']),method=api('class_get_method_from_name','pointer',['pointer','pointer','int']),invoke=api('runtime_invoke','pointer',['pointer','pointer','pointer','pointer']),unbox=api('object_unbox','pointer',['pointer']),alen=api('array_length','uint64',['pointer']),header=api('array_object_header_size','uint',[])();
 const domain=api('domain_get','pointer',[]),assemblies=api('domain_get_assemblies','pointer',['pointer','pointer']),image=api('assembly_get_image','pointer',['pointer']),find=api('class_from_name','pointer',['pointer','pointer','pointer']);
 function findClass(n){const np=Memory.alloc(8),list=assemblies(domain(),np);for(let i=0;i<Number(np.readU64());i++){const k=find(image(list.add(i*8).readPointer()),Memory.allocUtf8String('UnityEngine'),Memory.allocUtf8String(n));if(!k.isNull())return k;}throw Error('missing '+n);}
 function call(k,o,n,args=[]){const mi=method(k,Memory.allocUtf8String(n),args.length),ex=Memory.alloc(8);ex.writePointer(ptr(0));if(mi.isNull())throw Error('missing method '+n);const av=args.length?Memory.alloc(args.length*8):ptr(0);args.forEach((x,i)=>av.add(i*8).writePointer(x));const r=invoke(mi,o,av,ex);if(!ex.readPointer().isNull())throw Error('invoke failed '+n);return r;}
 function ints(n){const p=Memory.alloc(4);p.writeS32(n);return p;}
 function fs(p,n){return Array.from({length:n},(_,i)=>p.add(i*4).readFloat());}
 send({kind:'module',pid:Process.id,path:m.path,base:String(m.base),size:m.size});
 Interceptor.attach(m.base.add(0x44ff60),{onEnter(args){
  if(done)return;done=true;
  try{
   const g=args[0],array=g.add(0xa0).readPointer();if(array.isNull())throw Error('Ground array null');const n=Number(alen(array));if(n<=0||n>1024)throw Error('count limit');const chunks=[];
   for(let i=0;i<n;i++){
    const c=array.add(header+i*8).readPointer(),collider=c.add(0x40).readPointer();if(collider.isNull())throw Error('null collider');
    const mi=method(cls(collider),Memory.allocUtf8String('GetInstanceID'),0);if(mi.isNull())throw Error('GetInstanceID unavailable');const ex=Memory.alloc(8);ex.writePointer(ptr(0));const r=invoke(mi,collider,ptr(0),ex);if(!ex.readPointer().isNull()||r.isNull())throw Error('GetInstanceID failed');
    chunks.push({index:i,chunk:String(c),collider:String(collider),collider_instance_id:unbox(r).readS32()});
   }
   send({kind:'collider_identity_map',ground:String(g),array:String(array),chunks,thread:Process.getCurrentThreadId(),selector:'current Ground.Run; actual MeshCollider.GetInstanceID runtime_invoke; no mutation'});
   const camera=call(findClass('Camera'),ptr(0),'get_main'),w=unbox(call(cls(camera),camera,'get_pixelWidth')).readS32(),h=unbox(call(cls(camera),camera,'get_pixelHeight')).readS32(),sp=Memory.alloc(12);sp.writeFloat(w/2);sp.add(4).writeFloat(h/2);sp.add(8).writeFloat(0);
   const ray=unbox(call(cls(camera),camera,'ScreenPointToRay',[sp])),hit=Memory.alloc(44);hit.writeByteArray(new Uint8Array(44));const max=Memory.alloc(4);max.writeFloat(100);
   const yes=unbox(call(findClass('Physics'),ptr(0),'Raycast',[ray,ray.add(12),hit,max,ints(65),ints(2)])).readU8()!==0;
   send({kind:'centre_ray_query',screen_position:[w/2,h/2],pixel_width:w,pixel_height:h,origin_ws:fs(ray,3),direction_ws:fs(ray.add(12),3),hit_bool:yes,hit_collider_instance_id:yes?hit.add(40).readS32():null,point_ws:yes?fs(hit,3):null,layer_mask:65,query_trigger_interaction:2,max_distance:100,thread:Process.getCurrentThreadId(),selector:'actual current Camera.ScreenPointToRay viewport center -> Physics.Raycast; no input sent'},hit.readByteArray(44));
  }catch(e){send({kind:'error',code:'mapping_failed',message:String(e)});}
 }});
}});
