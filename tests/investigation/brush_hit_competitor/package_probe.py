"""Read-only, bounded hit-configuration probe; no method decompilation."""
import hashlib, json, sys, platform
from pathlib import Path
ROOT = Path('D:/godot/project/sandcastle')
sys.path.insert(0, str(Path(__file__).parent / 'deps'))
import UnityPy
OUT = ROOT / 'test_output/brush_hit_competitor/package_probe'
OUT.mkdir(parents=True, exist_ok=True)
def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for b in iter(lambda: f.read(1024*1024), b''): h.update(b)
    return h.hexdigest()
def save(name, data):
    (OUT/name).write_text(json.dumps(data, ensure_ascii=False, indent=2, default=str), encoding='utf-8')
data = ROOT/'sandcastlegame/Sandcastle_Data'
sources = list(data.glob('*'))
sources = [p for p in sources if p.is_file()]
sources += [p for p in (ROOT/'sandcastlegame').iterdir() if p.is_file()]
manifest = [{'path':str(p), 'size':p.stat().st_size, 'sha256':digest(p)} for p in sources]
save('source_manifest.json', manifest)
rows=[]; index=[]; counts={}; versions={}
selected={'MeshCollider','TerrainCollider','BoxCollider','SphereCollider','CapsuleCollider','TerrainData','Camera','MonoScript'}
for path in sources:
    if path.parent!=data or path.suffix in {'.resS','.resource','.info','.json','.config'}: continue
    try: env=UnityPy.load(str(path))
    except Exception as e:
        rows.append({'source':str(path),'status':'load_failed','error':repr(e)}); continue
    for obj in env.objects:
        typ=obj.type.name
        counts[typ]=counts.get(typ,0)+1
        versions[str(path)]=str(obj.assets_file.unity_version)
        if typ not in selected and typ not in {'GameObject','Transform'}: continue
        row={'source':str(path),'container_sha256':next(x['sha256'] for x in manifest if x['path']==str(path)), 'path_id':obj.path_id,'type':typ,'byte_start':obj.byte_start,'byte_size':obj.byte_size}
        try:
            tree=obj.read_typetree()
            if typ in {'GameObject','Transform'}:
                row['tree']=tree; rows.append(row); continue
            # Never export TerrainData external content as if it were included in object bytes.
            name=path.name+'_'+str(obj.path_id)
            raw=obj.get_raw_data(); rawpath=OUT/(name+'.raw'); rawpath.write_bytes(raw)
            row.update(status='parsed',raw_path=str(rawpath),raw_sha256=digest(rawpath),tree=tree,external_payload_complete=False if typ=='TerrainData' else None)
            index.append({k:v for k,v in row.items() if k!='tree'})
        except Exception as e: row.update(status='parse_failed',error=repr(e)); index.append(row.copy())
        rows.append(row)
save('objects.json',rows)
save('raw_index.json',index)
save('summary.json',{'python':platform.python_version(),'unitypy':UnityPy.__version__,'versions':versions,'object_counts':counts,'rows':len(rows),'script_sha256':digest(Path(__file__)),'scope':'built-in collision/camera configuration and script type names only; no MonoBehaviour or methods parsed'})
print(json.dumps({'output':str(OUT),'rows':len(rows),'counts':counts,'versions':versions},indent=2))
