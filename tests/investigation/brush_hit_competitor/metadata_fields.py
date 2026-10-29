"""Version-39 bounded type/field decoder. No methods or business behavior."""
import hashlib, json, struct, re, os
from pathlib import Path
ROOT=Path('D:/godot/project/sandcastle')
OUT=Path(os.environ.get('BRUSH_HIT_OUTPUT', str(ROOT/'test_output/brush_hit_competitor/metadata_fields_20261011')))
OUT.mkdir(parents=True,exist_ok=True)
META=ROOT/'sandcastlegame/Sandcastle_Data/il2cpp_data/Metadata/global-metadata.dat'
BIN=ROOT/'sandcastlegame/GameAssembly.dll'
mb=META.read_bytes(); bb=BIN.read_bytes()
def sha(b): return hashlib.sha256(b).hexdigest()
def save(name,obj): (OUT/name).write_text(json.dumps(obj,indent=2),encoding='utf8')
def u16(b,o): return struct.unpack_from('<H',b,o)[0]
def i32(b,o): return struct.unpack_from('<i',b,o)[0]
def u32(b,o): return struct.unpack_from('<I',b,o)[0]
def u64(b,o): return struct.unpack_from('<Q',b,o)[0]
assert u32(mb,0)==0xFAB11BAF and i32(mb,4)==39
names='stringLiteral stringLiteralData string events properties methods parameterDefaultValues fieldDefaultValues fieldAndParameterDefaultValueData fieldMarshaledSizes parameters fields genericParameters genericParameterConstraints genericContainers nestedTypes interfaces vtableMethods interfaceOffsets typeDefinitions images assemblies fieldRefs referencedAssemblies attributeData attributeDataRange unresolvedVirtualCallParameterTypes unresolvedVirtualCallParameterRanges windowsRuntimeTypeNames windowsRuntimeStrings exportedTypeDefinitions'.split()
sections={n:dict(zip(['offset','size','count'],struct.unpack_from('<iii',mb,8+i*12))) for i,n in enumerate(names)}
assert all(0<=s['offset']<=len(mb) and 0<=s['size']<=len(mb)-s['offset'] for s in sections.values())
def string(idx):
    s=sections['string']; assert 0<=idx<s['size']
    o=s['offset']+idx; end=mb.index(0,o,o+512)
    return mb[o:end].decode('utf8')
assert sections['fields']['size']//sections['fields']['count']==10
assert sections['typeDefinitions']['size']//sections['typeDefinitions']['count']==76
assert sections['interfaceOffsets']['size']//sections['interfaceOffsets']['count']-4==2
types=[]
for idx in range(sections['typeDefinitions']['count']):
    o=sections['typeDefinitions']['offset']+76*idx
    t={'index':idx,'name':string(i32(mb,o)),'namespace':string(i32(mb,o+4)),'offset':o,'byval':u16(mb,o+8),'parent':u16(mb,o+12),'flags':u32(mb,o+16),'first_field':i32(mb,o+20),'field_count':u16(mb,o+56),'token':u32(mb,o+72)}
    assert t['token']>>24==2
    assert not t['field_count'] or 0<=t['first_field']<sections['fields']['count'] and t['first_field']+t['field_count']<=sections['fields']['count']
    types.append(t)
# PE virtual-address mapping; no execution of binary.
pe=u32(bb,0x3c); assert bb[pe:pe+4]==b'PE\0\0'
nsec=u16(bb,pe+6); opts=u16(bb,pe+20); opt=pe+24
assert u16(bb,opt)==0x20b
imagebase=u64(bb,opt+24)
pe_sections=[]
for j in range(nsec):
    o=opt+opts+40*j
    pe_sections.append({'name':bb[o:o+8].rstrip(b'\0').decode(),'vsize':u32(bb,o+8),'rva':u32(bb,o+12),'size':u32(bb,o+16),'raw':u32(bb,o+20)})
def off(va):
    rva=va-imagebase
    for s in pe_sections:
        d=rva-s['rva']
        if 0<=d<s['size']: return s['raw']+d
    raise ValueError('unmapped VA '+hex(va))
# MetadataRegistration has fieldOffsetsCount/typeDefinitionsSizesCount == type count.
count=len(types); candidates=[]
for m in re.finditer(re.escape(struct.pack('<Q',count)),bb):
    o=m.start()-80
    if o<0 or o%8: continue
    if u64(bb,o+96)!=count: continue
    try:
        field_list=off(u64(bb,o+88)); type_list=off(u64(bb,o+56))
        nt=u64(bb,o+48)
        if not 0<nt<65535: continue
        probes=[off(u64(bb,type_list+8*types[k]['byval'])) for k in [0,1,100,1000]]
        candidates.append({'offset':o,'va':hex(imagebase+next(s['rva']+o-s['raw'] for s in pe_sections if s['raw']<=o<s['raw']+s['size'])),'num_types':nt,'field_list_offset':field_list,'type_list_offset':type_list})
    except (ValueError,struct.error): continue
save('registration_candidates.json',candidates)
assert len(candidates)==1, candidates
reg=candidates[0]
primitive={1:'void',2:'bool',3:'char',4:'sbyte',5:'byte',6:'short',7:'ushort',8:'int',9:'uint',10:'long',11:'ulong',12:'float',13:'double',14:'string',24:'IntPtr',25:'UIntPtr',28:'object'}
def describe_ptr(ptr,depth=0):
    if depth>8: return {'unresolved':'depth'}
    o=off(ptr); data=u64(bb,o); bits=u32(bb,o+8); tag=(bits>>16)&255
    d={'descriptor_va':hex(ptr),'descriptor_offset':o,'type_tag':tag,'attrs':bits&65535,'data':hex(data)}
    if tag in primitive: d['name']=primitive[tag]
    elif tag in [17,18]:
        assert data<len(types)
        t=types[data]; d.update(name=(t['namespace']+'.' if t['namespace'] else '')+t['name'],type_definition_index=data)
    elif tag in [15,16,29]:
        e=describe_ptr(data,depth+1); d.update(name=e.get('name','?')+{15:'*',16:'&',29:'[]'}[tag],element=e)
    elif tag==21:
        go=off(data); base=describe_ptr(u64(bb,go),depth+1)
        inst=off(u64(bb,go+8)); n=u64(bb,inst); args=off(u64(bb,inst+8))
        assert 0<n<20
        argtypes=[describe_ptr(u64(bb,args+8*j),depth+1) for j in range(n)]
        d.update(name=base.get('name','?')+'<'+','.join(a.get('name','?') for a in argtypes)+'>',generic_base=base,generic_arguments=argtypes)
    else: d['name']='unresolved_tag_'+str(tag)
    return d
def describe(idx): return describe_ptr(u64(bb,reg['type_list_offset']+idx*8))
selected=[]
targets={'Ground','Readback','Brush','CameraRig','GroundCell','ReadbackCell','PlaneChunk','Layer','UpdateVertexPositionJob','HitInfo'}
for t in types:
    if t['name'] not in targets: continue
    row=t.copy(); row['fields']=[]
    type_raw=mb[t['offset']:t['offset']+76]
    (OUT/('type_'+str(t['index'])+'.raw')).write_bytes(type_raw)
    ptr=u64(bb,reg['field_list_offset']+8*t['index'])
    field_offsets=off(ptr) if ptr else None
    for j in range(t['field_count']):
        idx=t['first_field']+j; o=sections['fields']['offset']+10*idx
        f={'index':idx,'offset':o,'name':string(i32(mb,o)),'type_index':u16(mb,o+4),'token':u32(mb,o+6),'native_instance_offset':i32(bb,field_offsets+4*j) if field_offsets is not None else None}
        assert f['token']>>24==4
        f['type']=describe(f['type_index']); row['fields'].append(f)
        (OUT/('field_'+str(idx)+'.raw')).write_bytes(mb[o:o+10])
    row['parent_type']=describe(t['parent']) if t['parent']!=65535 else None
    selected.append(row)
save('selected_types_fields.json',selected)
save('provenance.json',{'metadata':{'path':str(META),'size':len(mb),'sha256':sha(mb),'version':39},'binary':{'path':str(BIN),'size':len(bb),'sha256':sha(bb),'imagebase':hex(imagebase),'sections':pe_sections},'header_sections':sections,'registration':reg,'script_sha256':sha(Path(__file__).read_bytes()),'command':'python tests/investigation/brush_hit_competitor/metadata_fields.py','scope':'selected technical types and fields only; no methods parsed','compatibility':'strict v39 dimensions/tokens/bounds checks','selected_type_count':len(selected)})
print(json.dumps([{'type':t['name'],'index':t['index'],'fields':[(f['name'],f['type']['name'],f['native_instance_offset']) for f in t['fields']]} for t in selected],indent=2))
