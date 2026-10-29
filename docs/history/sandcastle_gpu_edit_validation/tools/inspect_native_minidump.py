import struct,json,hashlib,sys
from pathlib import Path
p=Path(sys.argv[1]);data=p.read_bytes()
def u32(b,o):return struct.unpack_from('<I',b,o)[0]
def u64(b,o):return struct.unpack_from('<Q',b,o)[0]
assert data[:4]==b'MDMP'
streams={}
for i in range(u32(data,8)):
 t,size,rva=struct.unpack_from('<III',data,u32(data,12)+i*12);streams[t]=(size,rva)
assert struct.unpack_from("<H",data,streams[7][1])[0]==9, "AMD64 minidump required"
modules=[]
_,at=streams[4]
for i in range(u32(data,at)):
 o=at+4+i*108;base=u64(data,o);size=u32(data,o+8);name_at=u32(data,o+20);name=data[name_at+4:name_at+4+u32(data,name_at)].decode('utf-16-le')
 modules.append({'base':base,'size':size,'path':name})
exports={}
def pe_exports(path):
 if path in exports:return exports[path]
 try:
  b=Path(path).read_bytes();pe=u32(b,0x3c);n=struct.unpack_from('<H',b,pe+6)[0];opt=pe+24;opt_size=struct.unpack_from('<H',b,pe+20)[0];dd=opt+(112 if struct.unpack_from('<H',b,opt)[0]==0x20b else 96);er=u32(b,dd);sections=[]
  for j in range(n):
   o=opt+opt_size+j*40;sections.append((u32(b,o+12),max(u32(b,o+8),u32(b,o+16)),u32(b,o+20)))
  def pos(rva):
   for va,size,raw in sections:
    if va<=rva<va+size:return raw+rva-va
   return rva
  out=[]
  if er:
   e=pos(er);func=pos(u32(b,e+28));names=pos(u32(b,e+32));ordinals=pos(u32(b,e+36))
   for j in range(u32(b,e+24)):
    no=pos(u32(b,names+j*4));end=b.index(b'\0',no);name=b[no:end].decode('ascii','replace');ordinal=struct.unpack_from('<H',b,ordinals+j*2)[0];out.append((u32(b,func+ordinal*4),name))
  exports[path]=sorted(out);return exports[path]
 except (OSError,ValueError,struct.error):exports[path]=[];return []
def locate(address):
 for m in modules:
  if m['base']<=address<m['base']+m['size']:
   rva=address-m['base'];values=[x for x in pe_exports(m['path']) if x[0]<=rva]
   last=values[-1] if values else None
   return {'module':Path(m['path']).name,'module_path':m['path'],'rva':hex(rva),'nearest_export':last[1] if last else None,'export_offset':rva-last[0] if last else None}
 return None
threads=[]
_,at=streams[3]
for i in range(u32(data,at)):
 o=at+4+i*48;tid=u32(data,o);stack_base=u64(data,o+24);stack_size=u32(data,o+32);stack_rva=u32(data,o+36);ctx_size=u32(data,o+40);ctx=u32(data,o+44)
 if ctx_size<256:continue
 rsp=u64(data,ctx+152);rip=u64(data,ctx+248);candidates=[]
 for displacement in range(0,min(512,stack_base+stack_size-rsp),8):
  at_stack=stack_rva+(rsp-stack_base)+displacement
  if at_stack<0 or at_stack+8>len(data):break
  address=u64(data,at_stack);where=locate(address)
  if where:candidates.append({'rsp_offset':displacement,'address':hex(address),'location':where})
 threads.append({'tid':tid,'rip':hex(rip),'rsp':hex(rsp),'instruction_location':locate(rip),'raw_stack_address_candidates':candidates,'stack_size':stack_size})
result={'source':str(p),'sha256':hashlib.sha256(data).hexdigest(),'streams':streams,'scope':'AMD64 context instruction pointers are direct evidence; raw stack mapped values are candidates, not unwound call stacks; nearest exports are labels, not private symbols','modules':modules,'threads':threads}
out=p.with_name('native_thread_contexts.json');out.write_text(json.dumps(result,indent=2),encoding='utf-8');print(json.dumps({'threads':len(threads),'output':str(out),'instructions':[(x['tid'],x['instruction_location']) for x in threads]}))
