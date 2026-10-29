"""Export only Water compute object and its named compiled variable bindings."""
import sys,json,hashlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'tests/investigation/brush_hit_competitor/deps'))
import UnityPy
OUT=ROOT/'test_output/test1_water_motion/package_v1';OUT.mkdir(parents=True,exist_ok=False)
SOURCE=ROOT/'sandcastlegame/Sandcastle_Data/sharedassets0.assets'
before=hashlib.sha256(SOURCE.read_bytes()).hexdigest();assert before=='6dd7bb6bc7d926fd43c08d22c9c767b7edf531cf11a4a555fcd41830f2f9c721'
report={'source':str(SOURCE),'source_bytes':SOURCE.stat().st_size,'source_sha256':before,'path_id':636,'exports':[],'kernels':[], 'tool':'UnityPy '+UnityPy.__version__}
def export(name,data,selector):
 p=OUT/name;p.write_bytes(data);r={'path':str(p),'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest(),'selector':selector};report['exports'].append(r);return r
env=UnityPy.load(str(SOURCE));obj=next(o for o in env.objects if o.path_id==636 and o.assets_file.name==SOURCE.name)
raw=obj.get_raw_data();tree=obj.read_typetree();assert tree['m_Name']=='Water'
report['object_byte_start']=obj.byte_start;report['object_bytes']=len(raw)
export('object.raw',raw,'sharedassets0.assets PathID636 entire object byte range')
export('typetree.json',json.dumps(tree,indent=2).encode(),'PathID636 full typetree, including compiled blobs')
for vi,v in enumerate(tree['variants']):
 if v['targetRenderer']!=2:continue
 for ki,k in enumerate(v['kernels']):
  for ui,u in enumerate(k['uniqueVariants']):
   code=bytes(u['code']);assert code[:4]==b'DXBC';start=raw.find(code);assert start>=0
   r={'name':k['name'],'variant':vi,'kernel':ki,'unique_variant':ui,'code_offset_in_object':start,'bytecode_sha256':hashlib.sha256(code).hexdigest(),
      'bindings':{n:u[n] for n in ['inBuffers','outBuffers','textures','builtinSamplers'] if n in u},
      'constant_buffers':[v['constantBuffers'][i] for i in u['cbVariantIndices']]}
   r['bytecode']=export('%s_%d.dxbc'%(k['name'],ui),code,'PathID636 renderer2 kernels[%d].uniqueVariants[%d].code'%(ki,ui));report['kernels'].append(r)
report['source_after_sha256']=hashlib.sha256(SOURCE.read_bytes()).hexdigest();assert report['source_after_sha256']==before
report['script_sha256']=hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
(OUT/'manifest.json').write_text(json.dumps(report,indent=2));print(json.dumps({'kernels':len(report['kernels']),'source_unchanged':True}))
