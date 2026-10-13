"""Reproduce recorded literal specialization bytes without rewriting candidates."""
import argparse,hashlib,json,os,re
from pathlib import Path
root=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser();parser.add_argument('--output',required=True,type=Path);args=parser.parse_args()
assets=root/'assets/water_material_natural_candidate';rows=[]
for name in ['water_geometry_specialized','water_route_specialized','water_route_full','water_debug_specialized','water_reflection_specialized','contact_geometry_specialized','bed_geometry_specialized','bed_material_specialized']:
 index=assets/(name+'_index.json');data=json.loads(index.read_text(encoding='utf8'))
 source=Path(data['source']);source=source if source.is_absolute() else root/source
 target=Path(data['generated']);target=target if target.is_absolute() else root/target
 code=source.read_text(encoding='utf8')
 for key,value in data['constants'].items():
  literal=('true' if value else 'false') if type(value)==bool else str(value)
  pattern=re.compile(r'\b'+re.escape(key)+r'\b')
  code='\n'.join(line if line.lstrip().startswith('uniform ') else pattern.sub(literal,line) for line in code.split('\n'))
 expected=code.replace('\n',os.linesep).encode('utf8')
 row={'index':str(index),'index_sha256':hashlib.sha256(index.read_bytes()).hexdigest(),'source':str(source),'source_hash_matches':hashlib.sha256(source.read_bytes()).hexdigest()==data['source_sha256'],'target':str(target),'recorded_target_hash_matches':hashlib.sha256(target.read_bytes()).hexdigest()==data['generated_sha256'],'reproduced_sha256':hashlib.sha256(expected).hexdigest(),'byte_reproduction_equal':expected==target.read_bytes(),'constants':data['constants']}
 rows.append(row)
result={'command':'python tests/water_material_natural/verify_fixed_variants.py --output '+str(args.output),'rows':rows,'pass':all(r['source_hash_matches'] and r['recorded_target_hash_matches'] and r['byte_reproduction_equal'] for r in rows),'scope':'Generation/index/bytes only. No shader compilation, image, physics or performance gate inferred.'}
args.output.write_text(json.dumps(result,indent=2),encoding='utf8');print(json.dumps({'pass':result['pass'],'rows':[{k:r[k] for k in ['index','source_hash_matches','recorded_target_hash_matches','byte_reproduction_equal']} for r in rows]}))
raise SystemExit(0 if result['pass'] else 1)
