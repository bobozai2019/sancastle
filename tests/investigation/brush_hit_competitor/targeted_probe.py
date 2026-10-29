"""Raw and typetree probe of only Ground/Readback scene configuration."""
import sys, json, hashlib
from pathlib import Path
ROOT=Path('D:/godot/project/sandcastle')
sys.path.insert(0,str(Path(__file__).parent/'deps'))
import UnityPy
OUT=ROOT/'test_output/brush_hit_competitor/targeted_probe'
OUT.mkdir(parents=True,exist_ok=True)
path=ROOT/'sandcastlegame/Sandcastle_Data/level0'
env=UnityPy.load(str(path)); rows=[]
for obj in env.objects:
    if obj.path_id not in {72,78,188,192,541,546,235}: continue
    raw=obj.get_raw_data(); dst=OUT/('level0_'+str(obj.path_id)+'.raw'); dst.write_bytes(raw)
    row={'source':str(path),'source_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'path_id':str(obj.path_id),'type':obj.type.name,'byte_start':str(obj.byte_start),'byte_size':obj.byte_size,'raw_path':str(dst),'raw_sha256':hashlib.sha256(raw).hexdigest(),'raw_complete':True,'external_payload':'not examined; no mesh payload claim'}
    try: row.update(tree=obj.read_typetree(),parse_status='ok')
    except Exception as e: row.update(parse_status='raw_only',error=repr(e))
    rows.append(row)
(OUT/'index.json').write_text(json.dumps({'unitypy':UnityPy.__version__,'script_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'command':'python tests/investigation/brush_hit_competitor/targeted_probe.py','objects':rows},indent=2),encoding='utf8')
print(json.dumps(rows,indent=2))
