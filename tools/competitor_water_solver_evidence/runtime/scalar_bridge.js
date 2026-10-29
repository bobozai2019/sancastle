'use strict';
// Native onEnter listeners read Frida 17.23.3 x64 saved XMM registers.
// No replacement/forwarding path; the target and its Win32 error behavior remain native.
globalThis.makeScalarBridge=function(compute,global,capacity=8192){
 if(Process.arch!=='x64'||Process.pointerSize!==8||capacity<2||capacity>8192||(capacity&(capacity-1)))throw Error('Unsupported scalar bridge platform/capacity');
 const allocate=n=>{const p=Memory.alloc(n);p.writeByteArray(new Uint8Array(n));return p;};
 const entries=allocate(capacity*32),indices=allocate(capacity*4),counts=allocate(64),lock=allocate(64),output=allocate(capacity*32),kernel=Process.getModuleByName('kernel32.dll');
 const symbols={cache_entries:entries,dirty_indices:indices,cache_counts:counts,cache_lock:lock};
 for(const n of ['InitializeCriticalSection','EnterCriticalSection','LeaveCriticalSection','QueryPerformanceCounter','GetLastError','SetLastError'])symbols[n]=kernel.getExportByName(n);
 const module=new CModule('#define CACHE_CAPACITY '+capacity+'\n'+globalThis.SCALAR_BRIDGE_SOURCE,symbols);
 const read=new NativeFunction(module.drain,'uint',['pointer','uint'],{scheduling:'exclusive'});
 return {module,computeEnter:module.compute_enter,globalEnter:module.global_enter,drain(){const n=read(output,capacity),rows=[];for(let i=0;i<n;i++){const p=output.add(i*32),value=p.add(16).readFloat();rows.push({object:String(p.readPointer()),property_id:p.add(8).readS32(),kind:p.add(12).readU32(),value_bits:p.add(16).readU32(),value:Number.isFinite(value)?value:String(value),qpc:p.add(24).readS64().toString()});}return rows;},status(){return {capacity,dirty_count:counts.readU32(),overflow:counts.add(4).readU32(),compute_calls:counts.add(8).readU64().toString(),global_calls:counts.add(16).readU64().toString(),drains:counts.add(24).readU64().toString(),updates:counts.add(32).readU64().toString()};}};
};
