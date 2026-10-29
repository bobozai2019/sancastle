"""Disassemble an explicit allowlist of hit/collision technical functions."""
import os,sys,json,struct,re,hashlib,runpy,io,contextlib,bisect
from pathlib import Path
ROOT=Path('D:/godot/project/sandcastle')
OUT=ROOT/'test_output/brush_hit_competitor/hit_disassembly_20261011_v3'
OUT.mkdir(parents=True,exist_ok=True)
sys.path.insert(0,str(Path(__file__).parent/'deps'))
import capstone
from capstone.x86 import X86_OP_IMM,X86_OP_MEM,X86_REG_RIP
os.environ['BRUSH_HIT_OUTPUT']=str(OUT/'fields')
with contextlib.redirect_stdout(io.StringIO()): ns=runpy.run_path(str(Path(__file__).parent/'metadata_fields.py'))
bb=ns['bb']; mb=ns['mb']; off=ns['off']; types=ns['types']; sections=ns['sections']; string=ns['string']; base=ns['imagebase']
u16=ns['u16']; u32=ns['u32']; u64=ns['u64']; i32=ns['i32']
def save(n,d): (OUT/n).write_text(json.dumps(d,indent=2),encoding='utf8')
def va(raw): return base+next(s['rva']+raw-s['raw'] for s in ns['pe_sections'] if s['raw']<=raw<s['raw']+s['size'])
def code(ptr): return any(s['name'] in {'.text','il2cpp'} and s['rva']<=ptr-base<s['rva']+s['vsize'] for s in ns['pe_sections'])
images=[]; modules={}
for j in range(sections['images']['count']):
    o=sections['images']['offset']+36*j
    image={'name':string(i32(mb,o)),'start':u16(mb,o+8),'count':u32(mb,o+10)}
    images.append(image)
    hits=[]
    for m in re.finditer(re.escape(image['name'].encode()+b'\0'),bb):
        p=va(m.start())
        for ref in re.finditer(re.escape(struct.pack('<Q',p)),bb):
            try:
                r=ref.start(); n=u64(bb,r+8); array=off(u64(bb,r+16))
                if 0<n<100000 and any(code(u64(bb,array+8*k)) for k in range(min(n,30))): hits.append({'offset':r,'count':n,'array':array})
            except (ValueError,struct.error): continue
    if len(hits)==1: modules[image['name']]=hits[0]
save('module_mapping.json',{'images':images,'modules':modules,'unresolved_modules':[i['name'] for i in images if i['name'] not in modules]})
# Address symbol map is mechanical only. Persist only actual call targets.
symbols={}
method_records={}
for idx in range(sections['methods']['count']):
    o=sections['methods']['offset']+30*idx; decl=u16(mb,o+4)
    image=next((im for im in images if im['start']<=decl<im['start']+im['count']),None)
    if not image or image['name'] not in modules: continue
    mod=modules[image['name']]; token=u32(mb,o+18); rid=token&0xffffff
    if not 0<rid<=mod['count']: continue
    ptr=u64(bb,mod['array']+8*(rid-1))
    if not ptr: continue
    name=types[decl]['name']+'.'+string(i32(mb,o))
    symbols.setdefault(ptr,[]).append(name)
    method_records[name]={'index':idx,'offset':o,'ptr':ptr,'token':hex(token)}
allowlist=['PlayerControls.GetHitInfo','Game.Raycast','Ground.Setup','Ground.UpdateColliders','PlaneChunk.SetMeshCollider','PlaneChunk.UpdateMeshCollider','UpdateVertexPositionJob.Execute','Readback.UpdateCellsImmediate','Readback.Draw','Readback.<Draw>b__11_0','Readback.SamplerPoint','Readback.Sampler','ReadbackCell.get_GroundNormal']
opt=ns['opt']; er=u32(bb,opt+112+3*8); es=u32(bb,opt+112+3*8+4)
entries=list(struct.iter_unpack('<III',bb[off(base+er):off(base+er)+es])); starts=[e[0] for e in entries]
def rootentry(e,depth=0):
    assert depth<20
    u=off(base+e[2]); flags=bb[u]>>3; n=bb[u+2]
    if flags&4:
        chain=struct.unpack_from('<III',bb,u+4+((n+1)//2)*4)
        return rootentry(chain,depth+1)
    return e
roots={e:rootentry(e) for e in entries}
md=capstone.Cs(capstone.CS_ARCH_X86,capstone.CS_MODE_64); md.detail=True
functions=[]
for name in allowlist:
    if name not in method_records: functions.append({'name':name,'status':'no_pointer'}); continue
    rec=method_records[name]; ptr=rec['ptr']; rva=ptr-base; ix=bisect.bisect_right(starts,rva)-1
    if ix<0 or not entries[ix][0]<=rva<entries[ix][1]: functions.append({'name':name,'status':'no_pdata','va':hex(ptr)}); continue
    root=roots[entries[ix]]; fragments=[e for e in entries if roots[e]==root]
    begin=min(e[0] for e in fragments); end=max(e[1] for e in fragments); unwind=root[2]
    assert end-begin<65536
    assert all(fragments[j][1]==fragments[j+1][0] for j in range(len(fragments)-1)), (name,fragments)
    rawoff=off(base+begin); raw=bb[rawoff:rawoff+end-begin]; stem=name.replace('<','_').replace('>','_').replace('.','_')
    (OUT/(stem+'.raw')).write_bytes(raw)
    o=rec['offset']; params=[]
    for j in range(u16(mb,o+28)):
        idx=i32(mb,o+12)+j; po=sections['parameters']['offset']+10*idx
        ty=ns['describe'](u16(mb,po+8))
        ty['byref']=bool(u32(bb,ty['descriptor_offset']+8)&(1<<29))
        params.append({'name':string(i32(mb,po)),'type':ty,'metadata_offset':po})
    insrows=[]; calls=[]
    for ins in md.disasm(raw,base+begin):
        notes=[]
        for operand in ins.operands:
            target=None
            if operand.type==X86_OP_IMM and ins.mnemonic in {'call','jmp'}: target=operand.imm
            if operand.type==X86_OP_MEM and operand.mem.base==X86_REG_RIP:
                addr=ins.address+ins.size+operand.mem.disp
                try:
                    data=bb[off(addr):off(addr)+180].split(b'\0',1)[0]
                    if len(data)>5 and all(32<=c<127 for c in data): notes.append({'rip_string':data.decode(),'va':hex(addr)})
                    candidate=u64(bb,off(addr))
                    if candidate in symbols: notes.append({'pointer_symbols':symbols[candidate],'va':hex(candidate)})
                except (ValueError,struct.error): pass
            if target is not None:
                syms=symbols.get(target,[])
                if syms: notes.append({'direct_symbols':syms})
                if ins.mnemonic=='call': calls.append({'at':hex(ins.address),'target':hex(target),'symbols':syms})
        insrows.append({'va':hex(ins.address),'bytes':bytes(ins.bytes).hex(),'mnemonic':ins.mnemonic,'operands':ins.op_str,'notes':notes})
    funcs={'name':name,'method':rec|{'ptr':hex(ptr)},'return_type':ns['describe'](u16(mb,o+6)),'parameters':params,'status':'disassembled','pdata':{'begin':hex(base+begin),'end':hex(base+end),'unwind_rva':hex(unwind),'fragments':[[hex(x) for x in e] for e in fragments]},'raw_offset':rawoff,'raw_length':len(raw),'raw_sha256':hashlib.sha256(raw).hexdigest(),'raw_path':str(OUT/(stem+'.raw')),'calls':calls,'instructions':insrows}
    functions.append(funcs)
    lines=[name+' '+hex(ptr), 'parameters: '+str([(p['name'],p['type']['name'],p['type']['byref']) for p in params])]
    lines += [i['va']+' '+i['mnemonic']+' '+i['operands']+(' ; '+str(i['notes']) if i['notes'] else '') for i in insrows]
    (OUT/(stem+'.txt')).write_text('\n'.join(lines),encoding='utf8')
save('functions.json',functions)
save('provenance.json',{'binary':ns['BIN'].as_posix(),'binary_sha256':hashlib.sha256(bb).hexdigest(),'metadata_sha256':hashlib.sha256(mb).hexdigest(),'script_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'capstone_version':capstone.__version__,'command':'python tests/investigation/brush_hit_competitor/disassemble_hit.py','allowlist':allowlist,'scope':'actual disassembly of hit/collision functions only; not original C# source'})
print(json.dumps([{'name':f['name'],'status':f['status'],'length':f.get('raw_length'),'parameters':[(p['name'],p['type']['name'],p['type']['byref']) for p in f.get('parameters',[])],'calls':[c for c in f.get('calls',[]) if c['symbols'] and len(c['symbols'])<10]} for f in functions],indent=2))
