'use strict';
const nil=ptr(0);let installed=false,target=null,seq=0,captures=0,busy=false;
let groundReady=false,armed=false,beforeBytes=null;
let bindingCounter=0,lastBinding=null;
let currentGround=null,currentArray=null,located=false;
let generation=0,negativeChecked=false,edgeChoice=null;
const cacheState=new Map();
let phaseLabel='automatic',inputScope=0,inputPosition=null,inputSampleAt=0,inputCounter=0;
rpc.exports={arm(){armed=true;send({kind:'edit_armed',utc_ms:Date.now()});return true;},phase(label){if(!/^[a-z0-9_]{1,40}$/.test(label))throw Error('invalid phase');phaseLabel=label;captures=0;armed=false;beforeBytes=null;send({kind:'phase_requested',phase:label,utc_ms:Date.now()});return true;}};
function install(m){
 if(installed||m.name.toLowerCase()!=='gameassembly.dll')return;installed=true;
 send({kind:'module',pid:Process.id,path:m.path,base:String(m.base),size:m.size});
 send({kind:'module_inventory',modules:Process.enumerateModules().filter(x=>/^(GameAssembly\.dll|UnityPlayer\.dll|Sandcastle\.exe)$/i.test(x.name)).map(x=>({name:x.name,path:x.path,base:String(x.base),size:x.size}))});
 const api=(n,r,a)=>new NativeFunction(m.getExportByName('il2cpp_'+n),r,a);
 const cls=api('object_get_class','pointer',['pointer']), unbox=api('object_unbox','pointer',['pointer']);
 const pin=api('gchandle_new','pointer',['pointer','bool']),freeHandle=api('gchandle_free','void',['pointer']),handleTarget=api('gchandle_get_target','pointer',['pointer']);
 const getMethod=api('class_get_method_from_name','pointer',['pointer','pointer','int']);
 const invoke=api('runtime_invoke','pointer',['pointer','pointer','pointer','pointer']);
 const alen=api('array_length','uint64',['pointer']), ahsize=api('array_object_header_size','uint',[]);
 const param=api('method_get_param','pointer',['pointer','uint']),typename=api('type_get_name','pointer',['pointer']);
 const methods=api('class_get_methods','pointer',['pointer','pointer']),methodname=api('method_get_name','pointer',['pointer']),pc=api('method_get_param_count','uint',['pointer']);
 const header=ahsize();send({kind:'abi',array_header_bytes:header});
 const resolve=api('resolve_icall','pointer',['pointer']);
 const domain=api('domain_get','pointer',[]),assemblies=api('domain_get_assemblies','pointer',['pointer','pointer']),image=api('assembly_get_image','pointer',['pointer']),find=api('class_from_name','pointer',['pointer','pointer','pointer']);
 function findClass(ns,n){const np=Memory.alloc(8),list=assemblies(domain(),np),count=Number(np.readU64());for(let i=0;i<count;i++){const k=find(image(list.add(i*8).readPointer()),Memory.allocUtf8String(ns),Memory.allocUtf8String(n));if(!k.isNull())return k;}throw Error('class_not_found '+n);}
 const qpc=new NativeFunction(Process.getModuleByName('kernel32.dll').getExportByName('QueryPerformanceCounter'),'bool',['pointer']);
 const qpf=new NativeFunction(Process.getModuleByName('kernel32.dll').getExportByName('QueryPerformanceFrequency'),'bool',['pointer']);
 function stamp(){const p=Memory.alloc(8);qpc(p);return p.readS64().toString();}
 const fp=Memory.alloc(8);qpf(fp);const frequency=fp.readS64().toString();
 function icall(selector,ret,args,values){const p=resolve(Memory.allocUtf8String(selector));send({kind:'icall_resolution',selector,pointer:String(p)});if(p.isNull())throw Error('api_unavailable '+selector);return new NativeFunction(p,ret,args)(...values);}
 function optional(o,n,fallback){try{return n==='get_cookingOptions'?scalar(o,n):bool(o,n);}catch(e){try{return fallback();}catch(f){send({kind:'unavailable',field:n,message:String(f)});return null;}}}
 function method(k,n,count){const mi=getMethod(k,Memory.allocUtf8String(n),count);if(mi.isNull())throw Error('api_unavailable '+n);return mi;}
 function callM(mi,o,args=[]){const ex=Memory.alloc(8);ex.writePointer(nil);const argv=args.length?Memory.alloc(8*args.length):nil;args.forEach((v,i)=>argv.add(i*8).writePointer(v));const r=invoke(mi,o,argv,ex);if(!ex.readPointer().isNull())throw Error('api_exception '+ex.readPointer());return r;}
 function call(o,n,args=[]){return callM(method(cls(o),n,args.length),o,args);}
 function int(v){const p=Memory.alloc(4);p.writeS32(v);return p;}
 function scalar(o,n){return unbox(call(o,n)).readS32();}
 function bool(o,n){return unbox(call(o,n)).readU8()!==0;}
 function floats(p,n){return Array.from({length:n},(_,i)=>p.add(i*4).readFloat());}
 let inputButtonUnavailable=false;
 function leftButton(){try{const k=findClass('UnityEngine.InputSystem','Mouse'),mouse=callM(method(k,'get_current',0),nil),button=call(mouse,'get_leftButton');return bool(button,'get_isPressed');}catch(e){if(!inputButtonUnavailable){send({kind:'input_button_unavailable',message:String(e)});inputButtonUnavailable=true;}return null;}}
 const snapshotBudget=new Map();
 function blob(snapshot,kind,p,n,selector){const total=(snapshotBudget.get(snapshot)||0)+n;if(n<0||total>67108864)throw Error('count_limit');snapshotBudget.set(snapshot,total);send({kind:'raw',snapshot_id:snapshot,payload_kind:kind,address:String(p),bytes:n,selector,thread:Process.getCurrentThreadId()},p.readByteArray(n));}
 const fieldByName=api('class_get_field_from_name','pointer',['pointer','pointer']),fieldOffset=api('field_get_offset','int',['pointer']);
 function offsetOf(o,n){const f=fieldByName(cls(o),Memory.allocUtf8String(n));if(f.isNull())throw Error('field_missing '+n);return fieldOffset(f);}
 function auxiliary(id,c){
  const beach=c.add(0x20).readPointer();if(beach.isNull())throw Error('beach_missing');
  const off=offsetOf(beach,'readback'),rb=beach.add(off).readPointer();if(rb.isNull())throw Error('readback_missing');
  const arrOff=offsetOf(rb,'readbackCells'),ptrOff=offsetOf(rb,'readbackCellsPtr'),p=rb.add(arrOff).readPointer(),n=rb.add(arrOff+8).readS32(),p2=rb.add(ptrOff).readPointer();
  if(p.isNull()||!p.equals(p2)||n<=0||n>1000000)throw Error('readback_layout_invalid');
  const state=cacheState.get(String(rb))||{depth:0,seq:0};if(state.depth!==0)throw Error('readback_copy_active');const seq0=state.seq;
  blob(id,'ReadbackCells',p,n*32,'Beach.readback offset '+off+'; Readback.readbackCells offset '+arrOff+'; NativeArray<ReadbackCell> stride32');
  const after=cacheState.get(String(rb))||{depth:0,seq:0};
  send({kind:'readback_snapshot',snapshot_id:id,beach:String(beach),readback:String(rb),pointer:String(p),count:n,stride:32,copy_seq_before:seq0,copy_seq_after:after.seq,active_copy_depth:after.depth,consistency_status:after.depth===0&&after.seq===seq0?'observed_cache_writers_stable':'changed_during_capture',thread:Process.getCurrentThreadId()});
  if(after.depth!==0||after.seq!==seq0)throw Error('readback_changed_during_capture');
 }
 for(const [rva,label] of [[0x4653e0,'async_callback'],[0x4654b0,'synchronous_GetData']])Interceptor.attach(m.base.add(rva),{onEnter(args){this.rb=String(args[0]);const s=cacheState.get(this.rb)||{depth:0,seq:0};s.depth++;cacheState.set(this.rb,s);},onLeave(){const s=cacheState.get(this.rb);s.depth--;s.seq++;if(s.seq<=2)send({kind:'readback_writer',readback:this.rb,writer:label,seq:s.seq,thread:Process.getCurrentThreadId()});}});
 function arr(snapshot,kind,a,stride,limit,selector){if(a.isNull())throw Error('payload_partial '+kind);const n=Number(alen(a));if(n<=0||n>limit)throw Error('count_limit '+n);blob(snapshot,kind,a.add(header),n*stride,selector);return n;}
 if(globalThis.PROBE_CONTROLLED){
  Interceptor.attach(m.base.add(0x4943f0),{onEnter(args){inputScope++;const p=Memory.alloc(8);p.writePointer(args[1]);inputPosition=floats(p,2);},onLeave(){inputScope--;}});
  Interceptor.attach(m.base.add(0x1ce65b0),{onEnter(args){
   this.record=false;if(inputScope<=0||!this.returnAddress.equals(m.base.add(0x48c4ee)))return;
   const now=Date.now();if(now-inputSampleAt<100)return;inputSampleAt=now;this.record=true;this.hit=args[1];this.ray=floats(args[0],6);this.mask=args[3].toInt32();this.trigger=args[4].toInt32();this.position=inputPosition;this.qpc=stamp();
  },onLeave(retval){if(!this.record)return;const yes=(retval.toInt32()&255)!==0;const id='input_'+(++inputCounter);const pressed=leftButton();const result={kind:'input_physics',input_id:id,phase:phaseLabel,query_qpc:this.qpc,button_sample_qpc:stamp(),qpc_frequency:frequency,screen_position:this.position,left_button_pressed:pressed,origin_ws:this.ray.slice(0,3),direction_ws:this.ray.slice(3),layer_mask:this.mask,query_trigger_interaction:this.trigger,hit_bool:yes,source:'actual PlayerControls.GetHitInfo -> Game.Raycast -> Physics.Raycast; source-hash-specific Win64 ABI'};if(yes){result.point_ws=floats(this.hit,3);result.normal_ws=floats(this.hit.add(12),3);result.distance=this.hit.add(28).readFloat();result.hit_collider_instance_id=this.hit.add(40).readS32();result.face_id=this.hit.add(24).readU32();if(pressed===true){blob(id,'input_physics_hit',this.hit,44,'actual input Physics.Raycast raw RaycastHit while sampled leftButton.isPressed=true; field layout verified for source hash');result.raw_hit_snapshot_id=id;}}send(result);}});
 }
 function rays(id,collider,vp,vc,matrix){
  const physics=findClass('UnityEngine','Physics'),mi=method(physics,'Raycast',6);
  const sig=Array.from({length:6},(_,i)=>typename(param(mi,i)).readUtf8String());
  if(sig.join(',')!=='UnityEngine.Vector3,UnityEngine.Vector3,UnityEngine.RaycastHit&,System.Single,System.Int32,UnityEngine.QueryTriggerInteraction')throw Error('abi_unverified Physics.Raycast '+sig);
  const hitClass=findClass('UnityEngine','RaycastHit'),sizeApi=api('class_value_size','int',['pointer','pointer']);const hitSize=sizeApi(hitClass,Memory.alloc(4));
  const field=api('class_get_field_from_name','pointer',['pointer','pointer']),offset=api('field_get_offset','int',['pointer']);
  const fieldOffsets={};for(const n of ['m_Point','m_Normal','m_FaceID','m_Distance','m_Collider']){const f=field(hitClass,Memory.allocUtf8String(n));if(f.isNull())throw Error('hit_field_missing '+n);fieldOffsets[n]=offset(f);}
  const adjustment=fieldOffsets.m_Point; // IL2CPP value fields include boxed object header.
  if(hitSize<44||hitSize>128||![0,16].includes(adjustment))throw Error('hit_layout_unverified');
  send({kind:'ray_abi',signature:sig,hit_size:hitSize,field_offsets:fieldOffsets,unboxed_adjustment:adjustment});
  const world=[];for(let i=0;i<vc;i++){const v=floats(vp.add(i*12),3);world.push([0,1,2].map(j=>matrix[j]*v[0]+matrix[4+j]*v[1]+matrix[8+j]*v[2]+matrix[12+j]));}
  const lo=[0,1,2].map(j=>Math.min(...world.map(v=>v[j]))),hi=[0,1,2].map(j=>Math.max(...world.map(v=>v[j]))),cx=(lo[0]+hi[0])/2,cz=(lo[2]+hi[2])/2,y=hi[1]+10;
  function vector(v){const p=Memory.alloc(12);v.forEach((x,i)=>p.add(i*4).writeFloat(x));return p;}
  const colliderId=scalar(collider,'GetInstanceID');
  function query(test,o,d0,kind='ray'){const norm=Math.hypot(...d0),d=d0.map(x=>x/norm),hit=Memory.alloc(hitSize);hit.writeByteArray(new Uint8Array(hitSize));const distance=Memory.alloc(4);distance.writeFloat(100);const yes=unbox(callM(mi,nil,[vector(o),vector(d),hit,distance,int(-1),int(2)])).readU8()!==0;
   const data={kind,snapshot_id:id,test,origin_ws:o,direction_ws:d,max_distance:100,layer_mask:-1,query_trigger_interaction:2,query_qpc:stamp(),hit_bool:yes,target_collider_instance_id:colliderId};
   if(yes){data.point_ws=floats(hit.add(fieldOffsets.m_Point-adjustment),3);data.normal_ws=floats(hit.add(fieldOffsets.m_Normal-adjustment),3);data.distance=hit.add(fieldOffsets.m_Distance-adjustment).readFloat();data.hit_collider_instance_id=hit.add(fieldOffsets.m_Collider-adjustment).readS32();data.triangle_index=hit.add(fieldOffsets.m_FaceID-adjustment).readU32();}
   blob(id,'ray_'+test,hit,hitSize,'Physics.Raycast actual output '+test);send(data);return data;
  }
  if(edgeChoice===null){
   // First publication chooses an unobscured edge using unchanged Physics.Raycast settings.
   // Freeze X/Z for this generation: later occlusion must fail, never silently relocate.
   const dx=hi[0]-lo[0],dz=hi[2]-lo[2],ix=Math.min(.13,dx*.1),iz=Math.min(.17,dz*.1);
   const candidates=[[lo[0]+ix,lo[2]+iz],[hi[0]-ix,lo[2]+iz],[lo[0]+ix,hi[2]-iz],[hi[0]-ix,hi[2]-iz],[lo[0]+ix,cz],[hi[0]-ix,cz],[cx,lo[2]+iz],[cx,hi[2]-iz]];
   for(let i=0;i<candidates.length;i++){
    const xz=candidates[i],r=query('edge_candidate_'+i,[xz[0],y,xz[1]],[0,-1,0],'ray_candidate');
    if(r.hit_bool&&r.hit_collider_instance_id===colliderId){edgeChoice={xz,selected_snapshot:id,candidate:i};break;}
   }
   if(edgeChoice===null)edgeChoice={xz:candidates[0],selected_snapshot:id,candidate:null};
  }
  send({kind:'edge_selection',snapshot_id:id,generation,...edgeChoice,policy:'first target hit in bounded edge candidates; fixed X/Z until Ground array generation changes; all rejected candidates retained'});
  const tests=[['center',[cx,y,cz],[0,-1,0]],['oblique',[cx+2,y,cz],[ -.2,-1,0]],['edge',[edgeChoice.xz[0],y,edgeChoice.xz[1]],[0,-1,0]],['outside',[10000,y,10000],[0,-1,0]],['neighbor',[hi[0]+.3,y,cz],[0,-1,0]]];
  for(const [test,o,d0] of tests)query(test,o,d0);
  if(globalThis.PROBE_AUX&&!negativeChecked){
   negativeChecked=true;let found=false,queries=0;
   const groundLayer=scalar(call(collider,'get_gameObject'),'get_layer'),mask=~(1<<groundLayer);
   const planeType=api('class_get_type','pointer',['pointer'])(findClass('','PlaneChunk')),typeObject=api('type_get_object','pointer',['pointer'])(planeType);
   for(let x=-12;x<=12&&!found;x+=4)for(let z=-12;z<=12&&!found;z+=4){
    queries++;const h=Memory.alloc(hitSize);h.writeByteArray(new Uint8Array(hitSize));const max=Memory.alloc(4);max.writeFloat(100);
    const yes=unbox(callM(mi,nil,[vector([x,20,z]),vector([0,-1,0]),h,max,int(mask),int(2)])).readU8()!==0;if(!yes)continue;
    const hc=callM(method(hitClass,'get_collider',0),h),getComponent=method(cls(hc),'GetComponent',1);
    if(typename(param(getComponent,0)).readUtf8String()!=='System.Type')throw Error('GetComponent ABI unverified');
    const chunk=callM(getComponent,hc,[typeObject]),accepted=!chunk.isNull();
    blob(id,'negative_non_plane_hit',h,hitSize,'Physics.Raycast non-ground-layer bounded grid; actual collider then GetComponent(typeof(PlaneChunk))');
    send({kind:'non_plane_filter',snapshot_id:id,origin_ws:[x,20,z],direction_ws:[0,-1,0],layer_mask:mask,query_trigger_interaction:2,hit_collider:String(hc),hit_instance_id:scalar(hc,'GetInstanceID'),plane_chunk:String(chunk),accepted,filter_pass:!accepted,queries});found=!accepted;
   }
   if(!found)send({kind:'negative_unavailable',snapshot_id:id,case:'non_plane_filter',queries,reason:'no non-PlaneChunk collider encountered by actual bounded queries; no fixture created'});
  }
 }
 let chunkClass=nil;
 if(globalThis.PROBE_TARGET){target=globalThis.PROBE_TARGET;groundReady=true;lastBinding={collider:String(ptr(target).add(0x40).readPointer())};send({kind:'target_resume',chunk:target,collider:lastBinding.collider,source:'same owned PID Ground membership from previous attempt'});}
 Interceptor.attach(m.base.add(0x1ce39d0),{onEnter(args){this.c=String(args[0]);this.mesh=String(args[1]);},onLeave(){bindingCounter++;if(target!==null&&lastBinding&&this.c===lastBinding.collider)lastBinding={collider:this.c,mesh:this.mesh,seq:bindingCounter,qpc:stamp(),thread:Process.getCurrentThreadId()};}});
 function observeGround(g){
  const array=g.add(0xa0).readPointer();if(array.isNull())return;if(currentGround===String(g)&&currentArray===String(array))return;const n=Number(alen(array));
  if(n<=0||n>1024){send({kind:'error',code:'count_limit',field:'Ground.planeChunks'});return;}
  const chunks=[];for(let i=0;i<n;i++){const c=array.add(header+i*8).readPointer();chunks.push({index:i,chunk:String(c),collider:String(c.add(0x40).readPointer()),meshC:String(c.add(0x68).readPointer())});}
  if(globalThis.PROBE_DYNAMIC){const nx=g.add(0x88).readS32(),nz=g.add(0x8c).readS32();if(!globalThis.PROBE_TARGET)target=chunks[Math.floor(nx/2)*nz+Math.floor(nz/2)].chunk;const member=chunks.find(x=>x.chunk===target);if(!member){send({kind:'error',code:'explicit_target_not_in_current_ground',chunk:target,array:String(array)});groundReady=false;return;}seq=0;captures=0;beforeBytes=null;located=false;lastBinding={collider:member.collider};}
  currentGround=String(g);
  currentArray=String(array);
  generation++;negativeChecked=false;edgeChoice=null;armed=false;
  groundReady=true;send({kind:'ground_membership',ground:String(g),array:String(array),chunks,collider_resolution:[g.add(0x80).readS32(),g.add(0x84).readS32()],chunk_dimensions:[g.add(0x88).readS32(),g.add(0x8c).readS32()],selected_chunk:target});
 }
 Interceptor.attach(m.base.add(0x451580),{onEnter(args){observeGround(args[0]);}});
 Interceptor.attach(m.base.add(0x44ff60),{onEnter(args){
  try{observeGround(args[0]);if(!target||located)return;const c=ptr(target),vp=c.add(0x48).readPointer(),n=c.add(0x50).readS32();if(vp.isNull()||n<=0||n>1000000)return;
   let lo=[Infinity,Infinity,Infinity],hi=[-Infinity,-Infinity,-Infinity];for(let i=0;i<n;i++)for(let j=0;j<3;j++){const f=vp.add(i*12+j*4).readFloat();lo[j]=Math.min(lo[j],f);hi[j]=Math.max(hi[j],f);}
   const transform=call(c,'get_transform'),matrix=floats(unbox(call(transform,'get_localToWorldMatrix')),16),center=lo.map((x,i)=>(x+hi[i])/2),world=Memory.alloc(12);[0,1,2].forEach(j=>world.add(j*4).writeFloat(matrix[j]*center[0]+matrix[4+j]*center[1]+matrix[8+j]*center[2]+matrix[12+j]));
   const camera=callM(method(findClass('UnityEngine','Camera'),'get_main',0),nil),screen=floats(unbox(call(camera,'WorldToScreenPoint',[world])),3);send({kind:'live_locator',ground:currentGround,chunk:target,unity_screen:screen,pixel_width:scalar(camera,'get_pixelWidth'),pixel_height:scalar(camera,'get_pixelHeight'),scope:'candidate cursor only, current Ground.Run main thread'});located=true;
  }catch(e){send({kind:'locator_error',message:String(e)});located=true;}
 }});
 Interceptor.attach(m.base.add(0x45f120),{
  onEnter(args){this.chunk=args[0];},
  onLeave(){
   if(busy)return;
   if(globalThis.PROBE_DYNAMIC&&!groundReady)return;
   if(target===null){target=String(this.chunk);chunkClass=cls(this.chunk);}
   if(String(this.chunk)!==target)return;
   seq++;
   const monitoring=globalThis.PROBE_CONTROLLED&&phaseLabel==='edit_monitor';
   if(captures>=(monitoring?48:2))return;
   if(globalThis.PROBE_DYNAMIC){
    if(seq<1||!monitoring&&captures===1&&!armed)return;
    if(!monitoring&&captures===1){const p=this.chunk.add(0x48).readPointer(),n=this.chunk.add(0x50).readS32();if(n<=0||n>1000000)return;const bytes=new Uint8Array(p.readByteArray(n*12));if(beforeBytes&&bytes.length===beforeBytes.length&&bytes.every((x,i)=>x===beforeBytes[i]))return;}
   }
   busy=true;
   let vertexHandle=null;
   const c=this.chunk,id='snapshot_g'+generation+'_'+seq;
   try{
    const collider=c.add(0x40).readPointer(),mc=c.add(0x68).readPointer(),bound=call(collider,'get_sharedMesh');
    if(bound.isNull()||!bound.equals(mc))throw Error('mesh_unbound');
    const start=Date.now(),beginQpc=stamp(),tid=Process.getCurrentThreadId(),vc=scalar(bound,'get_vertexCount');
    if(seq===1){const it=Memory.alloc(8);it.writePointer(nil);const inventory=[];for(let mi=methods(cls(bound),it);!mi.isNull();mi=methods(cls(bound),it)){const n=methodname(mi).readUtf8String();if(/Indices|Triangles|triangles|Index|Topology|BaseVertex|SubMesh/.test(n))inventory.push({name:n,params:Array.from({length:pc(mi)},(_,i)=>typename(param(mi,i)).readUtf8String())});}send({kind:'mesh_api_inventory',methods:inventory});}
    const vertices=call(bound,'get_vertices');vertexHandle=pin(vertices,1);if(!handleTarget(vertexHandle).equals(vertices))throw Error('gchandle_abi_mismatch');const count=arr(id,'vertices',vertices,12,1000000,'Mesh.get_vertices() API copy float32 local');
    if(count!==vc)throw Error('vertex_count_mismatch');
    const sc=scalar(bound,'get_subMeshCount'),submeshes=[];if(sc<=0||sc>128)throw Error('count_limit submesh');
    const getIndices=method(cls(bound),'GetIndices',3);
    const signature=[0,1,2].map(i=>typename(param(getIndices,i)).readUtf8String());
    if(signature.join(',')!=='System.Int32,System.Int32,System.Boolean')throw Error('abi_unverified GetIndices '+signature);
    for(let s=0;s<sc;s++){
     const sm=int(s),apply=int(0),indices=callM(getIndices,bound,[sm,int(0),apply]);
     const n=arr(id,'indices_'+s,indices,4,6000000,'Mesh.GetIndices('+s+', meshLod=0, applyBaseVertex=false) API copy int32');
     let topology=null;try{topology=unbox(call(bound,'GetTopology',[sm])).readS32();}catch(e){try{topology=icall('UnityEngine.Mesh::GetTopologyImpl_Injected','int',['pointer','int'],[bound.add(0x10).readPointer(),s]);}catch(f){send({kind:'unavailable',field:'topology',message:String(f)});}}
     submeshes.push({index:s,index_count:n,base_vertex:unbox(call(bound,'GetBaseVertex',[sm])).readU32(),topology,index_start:String(unbox(call(bound,'GetIndexStart',[sm])).readU32()),reported_index_count:unbox(call(bound,'GetIndexCount',[sm])).readU32()});
    }
    const transform=call(c,'get_transform'), matrix=floats(unbox(call(transform,'get_localToWorldMatrix')),16);
    const go=call(collider,'get_gameObject');
    const config={enabled:bool(collider,'get_enabled'),active:bool(go,'get_activeInHierarchy'),layer:scalar(go,'get_layer'),convex:bool(collider,'get_convex'),is_trigger:optional(collider,'get_isTrigger',()=>icall('UnityEngine.Collider::get_isTrigger_Injected','bool',['pointer'],[collider.add(0x10).readPointer()])),cooking_options:optional(collider,'get_cookingOptions',()=>icall('UnityEngine.MeshCollider::get_cookingOptions_Injected','int',['pointer'],[collider.add(0x10).readPointer()]))};
    const vertexPtr=c.add(0x48).readPointer(),vertexN=c.add(0x50).readS32();
    if(globalThis.PROBE_DYNAMIC&&captures===0)beforeBytes=new Uint8Array(vertexPtr.readByteArray(vertexN*12));
    if(vertexN>0&&vertexN<=1000000)blob(id,'verticesOS',vertexPtr,vertexN*12,'PlaneChunk+0x48 NativeArray<Vector3> completed after UpdateMeshCollider');
    const ridx=c.add(0x58).readPointer(),rn=c.add(0x60).readS32();
    if(rn>0&&rn<=1000000)blob(id,'readbackIndices',ridx,rn*16,'PlaneChunk+0x58 NativeArray<int4>');
    if(globalThis.PROBE_AUX){try{auxiliary(id,c);}catch(e){send({kind:'auxiliary_unavailable',snapshot_id:id,message:String(e),scope:'optional cache not substituted for bound geometry'});}}
    const observedBinding=lastBinding?Object.assign({},lastBinding):null,bindingAtStart=bindingCounter;
    let indexFormat;try{indexFormat=scalar(bound,'get_indexFormat');}catch(e){indexFormat=icall('UnityEngine.Mesh::get_indexFormat_Injected','int',['pointer'],[bound.add(0x10).readPointer()]);}
    try{rays(id,collider,vertices.add(header),vc,matrix);}catch(e){send({kind:'error',stage:'T04',snapshot_id:id,code:'api_unavailable',message:String(e),stack:e.stack});}
    try{const camera=callM(method(findClass('UnityEngine','Camera'),'get_main',0),nil);const b=floats(unbox(call(bound,'get_bounds')),6);const world=Memory.alloc(12);[0,1,2].forEach(j=>world.add(4*j).writeFloat(matrix[j]*b[0]+matrix[4+j]*b[1]+matrix[8+j]*b[2]+matrix[12+j]));const screen=call(camera,'WorldToScreenPoint',[world]);send({kind:'screen_target',snapshot_id:id,unity_screen:floats(unbox(screen),3)});}catch(e){send({kind:'unavailable',field:'screen_target',message:String(e)});}
    if(globalThis.PROBE_CONTROLLED){try{const camera=callM(method(findClass('UnityEngine','Camera'),'get_main',0),nil);send({kind:'capture_phase',snapshot_id:id,phase:phaseLabel,left_button_pressed:leftButton(),camera_world_to_camera:floats(unbox(call(camera,'get_worldToCameraMatrix')),16),camera_projection:floats(unbox(call(camera,'get_projectionMatrix')),16),pixel_width:scalar(camera,'get_pixelWidth'),pixel_height:scalar(camera,'get_pixelHeight'),qpc:stamp()});}catch(e){send({kind:'control_unavailable',snapshot_id:id,message:String(e)});}}
    const final=call(collider,'get_sharedMesh'),end=stamp();
    send({kind:'binding_observation',snapshot_id:id,observedBinding,global_binding_seq_before:bindingAtStart,global_binding_seq_after:bindingCounter,final_shared_mesh:String(final),capture_begin_monotonic_ns:(BigInt(beginQpc)*1000000000n/BigInt(frequency)).toString(),capture_end_monotonic_ns:(BigInt(end)*1000000000n/BigInt(frequency)).toString()});
    send({kind:'snapshot',snapshot_id:id,chunk_identity:String(c),collider_identity:String(collider),meshC_identity:String(mc),bound_mesh_identity:String(bound),binding_seq:seq,update_seq:seq,capture_begin_unix_ms:start,capture_end_unix_ms:Date.now(),capture_begin_qpc:beginQpc,capture_end_qpc:stamp(),qpc_frequency:frequency,capture_thread:tid,vertex_count:vc,index_format:indexFormat,submeshes,local_to_world:matrix,matrix_layout:'Unity column-major; M*v',bounds_local:floats(unbox(call(bound,'get_bounds')),6),config,consistency_status:final.equals(bound)?'binding_stable_update_return_same_thread':'changed_during_capture',retrieval_method:'il2cpp_runtime_invoke getters on UpdateMeshCollider onLeave',completeness:'geometry_exported_pending_verification',unit_status:'Unity scene units; metres unverified'});
    captures++;
   }catch(e){send({kind:'error',stage:'T03',snapshot_id:id,code:'export_failed',message:String(e),stack:e.stack});captures++;}
   if(vertexHandle!==null){try{freeHandle(vertexHandle);send({kind:'temporary_handle_released',snapshot_id:id,handle:String(vertexHandle)});}catch(e){send({kind:'error',code:'handle_release_failed',message:String(e)});}}
   busy=false;
  }
 });
 send({kind:'hook_installed',rva:'0x45f120',selector:'PlaneChunk.UpdateMeshCollider onLeave'});
}
Process.attachModuleObserver({onAdded:install});
