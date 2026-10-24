"""Read-only selected sand material and water/ground visual compute resources."""
import sys, json, hashlib, struct, traceback
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT/'tests/investigation/brush_hit_competitor/deps'))
sys.path.insert(0, str(ROOT/'tests/investigation/competitor_transport'))
import UnityPy
from UnityPy.helpers import CompressionHelper
from analyze_transport import disassemble
OUT = ROOT/'docs/competitor/evidence/wet_sand_20261024/package'
SOURCE = ROOT/'sandcastlegame/Sandcastle_Data/sharedassets0.assets'
def ident(p): return dict(path=p.as_posix(),bytes=p.stat().st_size,sha256=hashlib.sha256(p.read_bytes()).hexdigest())
OUT.mkdir(parents=True,exist_ok=False)
report = dict(source=ident(SOURCE),tool=ident(Path(__file__)),unitypy=UnityPy.__version__,command=sys.argv,artifacts=[],objects=[],programs=[],errors=[],scope='Material 20, Lit/Sand 605, Water 636 UpdateAmount, Ground 640 HeightIntegration only. No business methods. Compiled instructions are not original HLSL.')
def save(name,data,selector):
 p=OUT/name;p.write_bytes(data);r=dict(**ident(p),selector=selector);report['artifacts'].append(r);return r
try:
 assert report['source']['sha256']=='6dd7bb6bc7d926fd43c08d22c9c767b7edf531cf11a4a555fcd41830f2f9c721'
 env=UnityPy.load(str(SOURCE))
 for obj in env.objects:
  if obj.assets_file.name!=SOURCE.name or obj.path_id not in [20,605,636,640]: continue
  raw=obj.get_raw_data();tree=obj.read_typetree();pid=obj.path_id
  with SOURCE.open('rb') as stream:stream.seek(obj.byte_start);assert stream.read(len(raw))==raw
  report['objects'].append(dict(path_id=pid,type=obj.type.name,unity_version=str(obj.assets_file.unity_version),raw=save(f'object_{pid}.bin',raw,dict(path_id=pid,source_offset=obj.byte_start,bytes=len(raw))),external_payload='None for selected serialized shader/material data; referenced textures not exported by this tool.'))
  if pid==20:
   save('material_20.json',json.dumps(tree,indent=2).encode(),dict(path_id=pid,kind='derived_typetree'))
  elif pid in [636,640]:
   wanted='UpdateAmount' if pid==636 else 'HeightIntegration'
   for vi,v in enumerate(tree['variants']):
    if v['targetRenderer']!=2:continue
    for ki,k in enumerate(v['kernels']):
     if k['name']!=wanted:continue
     for ui,u in enumerate(k['uniqueVariants']):
      code=bytes(u['code']);positions=[];start=0
      while (at:=raw.find(code,start))>=0:positions.append(at);start=at+1
      assert positions and code[:4]==b'DXBC'
      prefix=f'{tree["m_Name"]}_{wanted}_{ui}'
      bc=save(prefix+'.dxbc',code,dict(path_id=pid,variant=vi,kernel=ki,unique_variant=ui,object_offsets=positions,source_offsets=[obj.byte_start+p for p in positions]))
      asm=save(prefix+'.asm',disassemble(code).encode(),dict(derived_from=bc['path'],tool='D3DDisassemble'))
      report['programs'].append(dict(name=prefix,bytecode=bc,assembly=asm,bindings={x:u[x] for x in ['cbs','inBuffers','outBuffers','textures']},constants=[v['constantBuffers'][i] for i in u['cbVariantIndices']]))
  else:
   assert tree['m_ParsedForm']['m_Name']=='Lit/Sand' and tree['platforms']==[4] and tree['offsets']==[[0]]
   blob=bytes(tree['compressedBlob']);offset=raw.find(blob);assert offset>=0
   save('sand_shader_compressed.lz4',blob,dict(path_id=pid,object_offset=offset,source_offset=obj.byte_start+offset))
   decoded=CompressionHelper.decompress_lz4(blob,tree['decompressedLengths'][0][0])
   save('sand_shader_decompressed.bin',decoded,dict(derived_from='sand_shader_compressed.lz4',codec='lz4'))
   count=struct.unpack_from('<I',decoded)[0];entries=[struct.unpack_from('<III',decoded,4+12*i) for i in range(count)]
   for si,sub in enumerate(tree['m_ParsedForm']['m_SubShaders']):
    for pi,pa in enumerate(sub['m_Passes']):
     for stage in ['progVertex','progFragment']:
      for gi,group in enumerate(pa[stage]['m_PlayerSubPrograms']):
       for vi,v in enumerate(group):
        offset,size,segment=entries[v['m_BlobIndex']];assert segment==0
        record=decoded[offset:offset+size];begin=record.find(b'DXBC');assert begin>=0
        length=struct.unpack_from('<I',record,begin+24)[0];assert begin+length<=len(record)
        code=record[begin:begin+length];prefix=f'Sand_{si}_{pi}_{stage}_{gi}_{vi}'
        bc=save(prefix+'.dxbc',code,dict(path_id=pid,subshader=si,pass_index=pi,stage=stage,group=gi,variant=vi,blob_index=v['m_BlobIndex'],decompressed_offset=offset+begin,bytes=length))
        asm=save(prefix+'.asm',disassemble(code).encode(),dict(derived_from=bc['path'],tool='D3DDisassemble'))
        report['programs'].append(dict(name=prefix,bytecode=bc,assembly=asm,parameters=pa[stage]['m_CommonParameters'],name_indices=pa['m_NameIndices'],variant=v))
 report['source_after']=ident(SOURCE);assert report['source_after']==report['source']
 report['pass']=True
except Exception:report['errors'].append(traceback.format_exc());report['pass']=False
(OUT/'manifest.json').write_text(json.dumps(report,indent=2),encoding='utf8')
print(json.dumps(dict(passed=report['pass'],programs=len(report['programs']),errors=report['errors'])))
