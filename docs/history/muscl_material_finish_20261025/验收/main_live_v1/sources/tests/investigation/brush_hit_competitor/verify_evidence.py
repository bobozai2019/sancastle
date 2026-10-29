"""Complete raw provenance for the mechanical inventory and verify file ranges."""
import sys,json,hashlib,struct,functools
from pathlib import Path
ROOT=Path('D:/godot/project/sandcastle')
sys.path.insert(0,str(Path(__file__).parent/'deps'))
import UnityPy
OUT=ROOT/'test_output/brush_hit_competitor/package_probe'
@functools.lru_cache(maxsize=None)
def sha(p):
    h=hashlib.sha256()
    with Path(p).open('rb') as f:
        for b in iter(lambda:f.read(1048576),b''): h.update(b)
    return h.hexdigest()
rows=json.loads((OUT/'objects.json').read_text(encoding='utf8')); manifest=json.loads((OUT/'source_manifest.json').read_text())
index=[]
for source in sorted({r['source'] for r in rows if 'path_id' in r}):
    env=UnityPy.load(source); wanted={r['path_id']:r for r in rows if r['source']==source and 'path_id' in r}
    with open(source,'rb') as src:
        for obj in env.objects:
            if obj.path_id not in wanted: continue
            raw=obj.get_raw_data(); dst=OUT/(Path(source).name+'_'+str(obj.path_id)+'.raw')
            if not dst.exists(): dst.write_bytes(raw)
            src.seek(obj.byte_start); direct=src.read(obj.byte_size)
            index.append({'source':source,'container_sha256':sha(source),'path_id':str(obj.path_id),'type':obj.type.name,'offset':str(obj.byte_start),'length':obj.byte_size,'raw_path':str(dst),'raw_sha256':sha(dst),'source_range_matches':direct==raw,'parse_status':'ok' if 'tree' in wanted[obj.path_id] else 'failed'})
(OUT/'complete_raw_index.json').write_text(json.dumps(index,indent=2),encoding='utf8')
checks=[{'path':r['path'],'size':Path(r['path']).stat().st_size,'sha256':sha(r['path']),'unchanged':sha(r['path'])==r['sha256']} for r in manifest]
(OUT/'post_source_check.json').write_text(json.dumps(checks,indent=2),encoding='utf8')
names={(r['source'],r['path_id']):r['tree'].get('m_Name') for r in rows if r.get('type')=='GameObject'}
colliders=[{'source':r['source'],'path_id':str(r['path_id']),'type':r['type'],'game_object_name':names.get((r['source'],r['tree']['m_GameObject']['m_PathID'])),'game_object':r['tree']['m_GameObject']} for r in rows if 'Collider' in r.get('type','')]
scripts=[{'source':r['source'],'path_id':str(r['path_id']),'class':r['tree']['m_ClassName'],'namespace':r['tree']['m_Namespace'],'assembly':r['tree']['m_AssemblyName']} for r in rows if r.get('type')=='MonoScript' and r['tree']['m_AssemblyName']=='Assembly-CSharp' and r['tree']['m_ClassName'] in {'Ground','Readback','Brush','CameraRig'}]
finding={'colliders':colliders,'technical_script_types':scripts,'range_checks':len(index),'range_mismatches':sum(not r['source_range_matches'] for r in index),'source_checks':len(checks),'source_changes':sum(not r['unchanged'] for r in checks),'command':'python tests/investigation/brush_hit_competitor/verify_evidence.py','script_sha256':sha(Path(__file__))}
(OUT/'verification.json').write_text(json.dumps(finding,indent=2),encoding='utf8')
print(json.dumps({k:v for k,v in finding.items() if k not in {'colliders'}},indent=2))
