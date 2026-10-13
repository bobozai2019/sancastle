'use strict';let installed=false,reported=false;
Process.attachModuleObserver({onAdded(m){
 if(installed||m.name.toLowerCase()!=='gameassembly.dll')return;installed=true;
 const nil=ptr(0),api=(n,r,a)=>new NativeFunction(m.getExportByName('il2cpp_'+n),r,a);
 const cls=api('object_get_class','pointer',['pointer']),method=api('class_get_method_from_name','pointer',['pointer','pointer','int']),invoke=api('runtime_invoke','pointer',['pointer','pointer','pointer','pointer']),unbox=api('object_unbox','pointer',['pointer']);
 const domain=api('domain_get','pointer',[]),assemblies=api('domain_get_assemblies','pointer',['pointer','pointer']),image=api('assembly_get_image','pointer',['pointer']),find=api('class_from_name','pointer',['pointer','pointer','pointer']);
 function call(k,o,n,args=[]){const mi=method(k,Memory.allocUtf8String(n),args.length);if(mi.isNull())throw Error(n+' unavailable');const e=Memory.alloc(8);e.writePointer(nil);const a=args.length?Memory.alloc(args.length*8):nil;args.forEach((x,i)=>a.add(i*8).writePointer(x));const r=invoke(mi,o,a,e);if(!e.readPointer().isNull())throw Error(n+' exception');return r;}
 function findCamera(){const np=Memory.alloc(8),list=assemblies(domain(),np);for(let i=0;i<Number(np.readU64());i++){const k=find(image(list.add(8*i).readPointer()),Memory.allocUtf8String('UnityEngine'),Memory.allocUtf8String('Camera'));if(!k.isNull())return k;}throw Error('Camera missing');}
 Interceptor.attach(m.base.add(0x4943f0),{onLeave(){
  if(reported)return;reported=true;
  try{const c=ptr(globalThis.PROBE_TARGET),vp=c.add(0x48).readPointer(),n=c.add(0x50).readS32();if(n<=0||n>1000000)throw Error('count_limit');let lo=[Infinity,Infinity,Infinity],hi=[-Infinity,-Infinity,-Infinity];for(let i=0;i<n;i++)for(let j=0;j<3;j++){const f=vp.add(i*12+j*4).readFloat();lo[j]=Math.min(lo[j],f);hi[j]=Math.max(hi[j],f);}
   const tr=call(cls(c),c,'get_transform'),matrix=unbox(call(cls(tr),tr,'get_localToWorldMatrix'));const center=lo.map((x,i)=>(x+hi[i])/2),world=Memory.alloc(12);for(let j=0;j<3;j++)world.add(4*j).writeFloat(matrix.add(j*4).readFloat()*center[0]+matrix.add((4+j)*4).readFloat()*center[1]+matrix.add((8+j)*4).readFloat()*center[2]+matrix.add((12+j)*4).readFloat());
   const k=findCamera(),cam=call(k,nil,'get_main'),screen=unbox(call(k,cam,'WorldToScreenPoint',[world]));send({kind:'locator',chunk:String(c),unity_screen:[0,1,2].map(j=>screen.add(j*4).readFloat()),pixel_width:unbox(call(k,cam,'get_pixelWidth')).readS32(),pixel_height:unbox(call(k,cam,'get_pixelHeight')).readS32(),thread:Process.getCurrentThreadId(),scope:'candidate cursor location only; verticesOS is not bound-mesh capture'});
  }catch(e){send({kind:'locator_error',message:String(e)});}
 }});
 send({kind:'locator_installed',trigger:'PlayerControls.GetHitInfo onLeave; no worker-thread Unity calls'});
}});
