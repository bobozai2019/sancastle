'use strict';
// Common minimal presentation observer for baseline, water trace and capture modes.
const installed=new Set(),stats={presents:0,returns:0,inflight:0,dropped:0,errors:0};let queue=[],seq=0,open=true,call=0;
let targetWindow=null;
const k=Process.getModuleByName('kernel32.dll'),qpc=new NativeFunction(k.getExportByName('QueryPerformanceCounter'),'bool',['pointer'],{scheduling:'exclusive'}),qpf=new NativeFunction(k.getExportByName('QueryPerformanceFrequency'),'bool',['pointer'],{scheduling:'exclusive'}),qp=Memory.alloc(8),fp=Memory.alloc(8);qpf(fp);
function stamp(){qpc(qp);return qp.readS64().toString();}
function emit(kind,data={}){const time=stamp();if(queue.length>=8192){stats.dropped++;return;}queue.push({seq:++seq,kind,qpc:time,...data});}
function flush(){if(queue.length){const events=queue;queue=[];send({kind:'presentation_trace',events});}}
const user=Process.getModuleByName('user32.dll'),winapi=(n,r,a)=>new NativeFunction(user.getExportByName(n),r,a,{exceptions:'propagate'});
const visible=winapi('IsWindowVisible','bool',['pointer']),iconic=winapi('IsIconic','bool',['pointer']),foreground=winapi('GetForegroundWindow','pointer',[]),owner=winapi('GetWindowThreadProcessId','uint',['pointer','pointer']),client=winapi('GetClientRect','bool',['pointer','pointer']),cursor=winapi('GetCursorPos','bool',['pointer']),screenToClient=winapi('ScreenToClient','bool',['pointer','pointer']),key=winapi('GetAsyncKeyState','int16',['int']);
function sampleWindow(){if(!open||!targetWindow)return;try{const pid=Memory.alloc(4),rect=Memory.alloc(16),point=Memory.alloc(8);owner(foreground(),pid);const focused=pid.readU32()===Process.id,haveRect=client(targetWindow,rect),input={};if(focused&&cursor(point)&&screenToClient(targetWindow,point)){input.client_x=point.readS32();input.client_y=point.add(4).readS32();input.left=(key(1)&0x8000)!==0;input.right=(key(2)&0x8000)!==0;input.middle=(key(4)&0x8000)!==0;}const state={visible:visible(targetWindow),minimized:iconic(targetWindow),foreground_owned:focused,client_width:haveRect?rect.add(8).readS32()-rect.readS32():null,client_height:haveRect?rect.add(12).readS32()-rect.add(4).readS32():null,input:focused?input:null};emit('window_state',state);}catch(e){stats.errors++;emit('error',{where:'window_state',message:String(e)});}}
function method(o,index){return o.readPointer().add(index*8).readPointer();}
function query(o,bytes){const guid=Memory.alloc(16);guid.writeByteArray(bytes);const result=Memory.alloc(8);result.writePointer(ptr(0));const get=new NativeFunction(method(o,0),'int',['pointer','pointer','pointer'],{exceptions:'propagate'});return get(o,guid,result)===0?result.readPointer():null;}
function release(o){new NativeFunction(method(o,2),'uint',['pointer'],{exceptions:'propagate'})(o);}
function attach(address,label,callbacks){if(installed.has(String(address)))return;Interceptor.attach(address,callbacks);installed.add(String(address));const m=Process.findModuleByAddress(address);emit('hook',{label,address:String(address),module:m?m.path:null,offset:m?String(address.sub(m.base)):null});}
function swapchain(o,source){
 try{
  const desc=Memory.alloc(80),get=new NativeFunction(method(o,12),'int',['pointer','pointer'],{exceptions:'propagate'}),result=get(o,desc);
  emit('swapchain',{object:String(o),source,description_result:result,width:result===0?desc.readU32():null,height:result===0?desc.add(4).readU32():null,hwnd:result===0?String(desc.add(48).readPointer()):null,windowed:result===0?desc.add(56).readU32():null});
  if(result===0){targetWindow=desc.add(48).readPointer();sampleWindow();}
  attach(method(o,13),'ResizeBuffers',{
   onEnter(a){this.chain=a[0];this.request={buffer_count:a[1].toUInt32(),width:a[2].toUInt32(),height:a[3].toUInt32(),format:a[4].toUInt32(),flags:a[5].toUInt32()};},
   onLeave(ret){if(!open)return;try{const actual=Memory.alloc(80),get=new NativeFunction(method(this.chain,12),'int',['pointer','pointer'],{exceptions:'propagate'}),status=get(this.chain,actual);emit('swapchain_resize',{object:String(this.chain),requested:this.request,hresult:ret.toUInt32(),description_result:status,width:status===0?actual.readU32():null,height:status===0?actual.add(4).readU32():null});}catch(e){stats.errors++;emit('error',{where:'ResizeBuffers.GetDesc',message:String(e)});}}
  });
  const extended=query(o,[0xf7,0x45,0x0a,0x79,0x42,0x0d,0x76,0x48,0x98,0x3a,0x0a,0x55,0xcf,0xe6,0xf4,0xaa]);
  for(const [index,label] of extended?[[8,'Present'],[22,'Present1']]:[[8,'Present']])attach(method(extended||o,index),label,{
   onEnter(a){if(!open)return;this.id=++call;stats.presents++;stats.inflight++;emit('present_enter',{call_id:this.id,swapchain:String(a[0]),api:label,sync_interval:a[1].toUInt32(),flags:a[2].toUInt32()});},
   onLeave(ret){if(this.id){stats.returns++;stats.inflight--;emit('present_return',{call_id:this.id,hresult:ret.toUInt32()});}}
  });
  if(extended)release(extended);
 }catch(e){stats.errors++;emit('error',{where:'swapchain',message:String(e)});}
}
function factory(o){
 const extended=query(o,[0x1c,0x3a,0xc8,0x50,0x72,0xe0,0x48,0x4c,0x87,0xb0,0x36,0x30,0xfa,0x36,0xa6,0xd0]);
 const candidates=extended?[[10,'CreateSwapChain',3],[15,'CreateSwapChainForHwnd',6],[16,'CreateSwapChainForCoreWindow',5],[24,'CreateSwapChainForComposition',4]]:[[10,'CreateSwapChain',3]];
 for(const [index,label,outIndex] of candidates){
  try{const a=method(extended||o,index),range=Process.findRangeByAddress(a);if(!range||!range.protection.includes('x')){emit('unsupported_factory_method',{label,index});continue;}
   attach(a,label,{onEnter(args){this.output=args[outIndex];},onLeave(ret){if(ret.toInt32()===0&&!this.output.isNull())swapchain(this.output.readPointer(),label);}});
  }catch(e){stats.errors++;emit('error',{where:label,message:String(e)});}
 }
 if(extended)release(extended);
}
const observer=Process.attachModuleObserver({onAdded(m){if(m.name.toLowerCase()!=='dxgi.dll')return;for(const name of ['CreateDXGIFactory','CreateDXGIFactory1','CreateDXGIFactory2']){
 try{attach(m.getExportByName(name),name,{onEnter(a){this.output=a[name==='CreateDXGIFactory2'?2:1];},onLeave(ret){if(ret.toInt32()===0)factory(this.output.readPointer());}});}catch(e){stats.errors++;emit('error',{where:name,message:String(e)});}
}}});
emit('loaded',{qpc_frequency:fp.readS64().toString(),scope:'Common DXGI API observer; Present return is not GPU completion',window_sampling_ms:500,input_scope:'Mouse buttons/cursor only while this owned process is foreground; no external-app input'});setInterval(flush,100);setInterval(sampleWindow,500);
rpc.exports={mark(label){const qpc=stamp();emit('host_marker',{label,marker_qpc:qpc});flush();return {qpc,qpc_frequency:fp.readS64().toString()};},finish(){sampleWindow();open=false;emit('window_close',{...stats});flush();return {...stats,last_seq:seq};},status(){return {...stats,last_seq:seq};}};
