"""Resolve metadata pointers used by the selected hit/collision disassembly."""
import os,runpy,contextlib,io,json,struct,hashlib
from pathlib import Path
ROOT=Path('D:/godot/project/sandcastle')
OUT=ROOT/'test_output/brush_hit_competitor/hit_usage_resolution_20261011'
OUT.mkdir(parents=True,exist_ok=True)
os.environ['BRUSH_HIT_OUTPUT']=str(OUT/'fields')
with contextlib.redirect_stdout(io.StringIO()): ns=runpy.run_path(str(Path(__file__).parent/'metadata_fields.py'))
bb=ns['bb']; mb=ns['mb']; off=ns['off']; reg=ns['reg']; types=ns['types']; sections=ns['sections']; string=ns['string']; u16=ns['u16']; u32=ns['u32']; u64=ns['u64']; i32=ns['i32']
fns=json.loads((ROOT/'test_output/brush_hit_competitor/hit_disassembly_20261011_v3/functions.json').read_text())
ro=reg['offset']; spec_count=u64(bb,ro+64); spec_list=off(u64(bb,ro+72)); inst_count=u64(bb,ro+16); inst_list=off(u64(bb,ro+24))
def inst(idx):
    if idx==-1: return None
    assert 0<=idx<inst_count
    p=u64(bb,inst_list+8*idx); o=off(p); count=u64(bb,o); args=off(u64(bb,o+8)); assert count<20
    return [ns['describe_ptr'](u64(bb,args+8*j))['name'] for j in range(count)]
def method(idx):
    assert 0<=idx<sections['methods']['count']
    o=sections['methods']['offset']+30*idx; ti=u16(mb,o+4)
    return {'name':types[ti]['name']+'.'+string(i32(mb,o)),'index':idx,'metadata_offset':o}
rows=[]
for f in fns:
    for i in f.get('instructions',[]):
        if '[rip + ' not in i['operands']: continue
        displacement=int(i['operands'].split('[rip + ')[1].split(']')[0],16)
        addr=int(i['va'],16)+len(bytes.fromhex(i['bytes']))+displacement
        try: o=off(addr); encoded=u64(bb,o)
        except (ValueError,struct.error): continue
        kind=(encoded&0xe0000000)>>29; index=(encoded&0x1fffffff)>>1
        if encoded>0xffffffff or not encoded&1: continue
        r={'function':f['name'],'instruction':i['va'],'instruction_text':i['mnemonic']+' '+i['operands'],'cell_va':hex(addr),'cell_offset':o,'encoded':hex(encoded),'kind':kind,'index':index}
        try:
            if kind==6:
                assert index<spec_count
                so=spec_list+12*index; mi,ci,ii=struct.unpack_from('<iii',bb,so)
                r.update(method=method(mi),class_args=inst(ci),method_args=inst(ii),spec_offset=so)
            elif kind==3: r.update(method=method(index))
            elif kind in [1,2]: r.update(type=ns['describe'](index)['name'])
            else: continue
        except (ValueError,AssertionError,struct.error) as e: r.update(error=repr(e))
        rows.append(r)
(OUT/'resolved_usages.json').write_text(json.dumps(rows,indent=2),encoding='utf8')
(OUT/'provenance.json').write_text(json.dumps({'command':'python tests/investigation/brush_hit_competitor/resolve_hit_usages.py','script_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'metadata_sha256':hashlib.sha256(mb).hexdigest(),'binary_sha256':hashlib.sha256(bb).hexdigest(),'scope':'metadata reference resolution only for allowlisted hit/collision instructions; generic arguments kept with exact cell selector'},indent=2),encoding='utf8')
print(json.dumps([r for r in rows if r['function'] in ['Game.Raycast','PlaneChunk.UpdateMeshCollider','Readback.<Draw>b__11_0','Readback.Draw'] and r['kind']==6],indent=2))
