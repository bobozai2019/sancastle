"""Map only collision/sampling technical method declarations to original code.

No tool/economy/UI behavior decompilation; metadata inventory supplies selectors.
"""
import os, runpy, contextlib, io, json, struct, re, hashlib, sys
from pathlib import Path
ROOT=Path('D:/godot/project/sandcastle')
OUT=Path(os.environ.get('BRUSH_HIT_NATIVE_OUTPUT', str(ROOT/'test_output/brush_hit_competitor/hit_native_20261011_v4')))
OUT.mkdir(parents=True,exist_ok=True)
os.environ['BRUSH_HIT_OUTPUT']=str(OUT/'fields')
with contextlib.redirect_stdout(io.StringIO()):
    ns=runpy.run_path(str(Path(__file__).parent/'metadata_fields.py'))
mb=ns['mb']; bb=ns['bb']; types=ns['types']; sections=ns['sections']; off=ns['off']; string=ns['string']; describe=ns['describe']; base=ns['imagebase']
u16=ns['u16']; u32=ns['u32']; u64=ns['u64']; i32=ns['i32']; reg=ns['reg']
def save(n,d): (OUT/n).write_text(json.dumps(d,indent=2),encoding='utf8')
def va(raw): return base+next(s['rva']+raw-s['raw'] for s in ns['pe_sections'] if s['raw']<=raw<s['raw']+s['size'])
# Image definitions are 36 bytes on v39, including 16-bit type indices.
images=[]
for j in range(sections['images']['count']):
    o=sections['images']['offset']+36*j
    images.append({'name':string(i32(mb,o)),'start':u16(mb,o+8),'count':u32(mb,o+10),'offset':o})
assert sections['images']['size']==36*len(images)
image=next(x for x in images if x['name']=='Assembly-CSharp.dll')
name_at=bb.index(b'Assembly-CSharp.dll\0'); name_va=va(name_at)
candidates=[]
for m in re.finditer(re.escape(struct.pack('<Q',name_va)),bb):
    o=m.start()
    try:
        n=u64(bb,o+8); array=off(u64(bb,o+16)); first=next(u64(bb,array+8*j) for j in range(min(n,20)) if u64(bb,array+8*j))
        if 0<n<sections['methods']['count'] and any(s['name'] in {'.text','il2cpp'} and s['rva']<=first-base<s['rva']+s['vsize'] for s in ns['pe_sections']):
            candidates.append({'offset':o,'va':hex(va(o)),'method_count':n,'method_pointer_array':array})
    except (ValueError,struct.error): pass
save('codegen_module_candidates.json',candidates)
assert len(candidates)==1, candidates
module=candidates[0]
assert sections['methods']['size']==sections['methods']['count']*30
def method(idx):
    o=sections['methods']['offset']+idx*30
    decl=u16(mb,o+4); token=u32(mb,o+18)
    assert token>>24==6
    rid=token&0xffffff
    ptr=u64(bb,module['method_pointer_array']+(rid-1)*8) if image['start']<=decl<image['start']+image['count'] and 0<rid<=module['method_count'] else None
    return {'index':idx,'metadata_offset':o,'name':string(i32(mb,o)),'declaring_type':types[decl]['name'],'declaring_type_index':decl,'return_type':describe(u16(mb,o+6)),'parameter_count':u16(mb,o+28),'parameter_start':i32(mb,o+12),'token':hex(token),'va':hex(ptr) if ptr else None,'rva':hex(ptr-base) if ptr else None}
targets={'Ground','Readback','PlaneChunk','Layer','CameraRig','UpdateVertexPositionJob'}
rows=[]
for t in types:
    if t['name'] not in targets: continue
    start=i32(mb,t['offset']+24); count=u16(mb,t['offset']+52)
    for j in range(count):
        m=method(start+j); assert m['declaring_type_index']==t['index']
        rows.append(m)
save('technical_method_declarations.json',rows)
hit_declarations=[]
for idx in range(sections['methods']['count']):
    o=sections['methods']['offset']+idx*30
    decl=u16(mb,o+4)
    if not image['start']<=decl<image['start']+image['count']: continue
    name=string(i32(mb,o))
    if re.search('Raycast|HitTest|GetPointer|GetMouse|GetGroundPoint|PickGround',name):
        hit_declarations.append(method(idx))
save('hit_named_declarations.json',hit_declarations)
# Locate exact hit-related fields without interpreting other owners' behavior.
field_names={'colliderResolution','planeChunks','readbackCells','readbackCellsPtr','groundRaycast','raycastResults','rayTest','mouseRay','groundHit','hitPoint','hitPosition','raycastHit','pointerRay','mousePosition'}
clues=[]
for t in types:
    for j in range(t['field_count']):
        idx=t['first_field']+j; o=sections['fields']['offset']+idx*10
        name=string(i32(mb,o))
        if name in field_names:
            clues.append({'owner':t['name'],'namespace':t['namespace'],'owner_index':t['index'],'field':name,'field_index':idx,'metadata_offset':o,'type':describe(u16(mb,o+4))})
save('hit_field_owner_clues.json',clues)
save('provenance.json',{'script_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'module':module,'image':image,'sources':ns['sha'](mb)+' / '+ns['sha'](bb),'scope':'bounded declarations and technical collision/sampling methods; no unrelated method bodies','command':'python tests/investigation/brush_hit_competitor/hit_native_probe.py'})
print(json.dumps({'module':module,'new_job_declarations':[{k:v for k,v in m.items() if k in ['declaring_type','name','rva','parameter_count']} for m in rows if m['declaring_type']=='UpdateVertexPositionJob'],'hit_declarations':[{k:v for k,v in m.items() if k in ['declaring_type','name','rva','parameter_count']} for m in hit_declarations]},indent=2))
