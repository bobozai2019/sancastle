"""Verify native bytes, decoded coverage, selected metadata records and sources."""
from pathlib import Path
import json,hashlib
ROOT=Path('D:/godot/project/sandcastle')
RUN=ROOT/'test_output/brush_hit_competitor/hit_disassembly_20261011_v3'
OUT=ROOT/'test_output/brush_hit_competitor/hit_verification_20261011'
OUT.mkdir(parents=True,exist_ok=True)
sources={'binary':ROOT/'sandcastlegame/GameAssembly.dll','metadata':ROOT/'sandcastlegame/Sandcastle_Data/il2cpp_data/Metadata/global-metadata.dat'}
data={k:p.read_bytes() for k,p in sources.items()}
provenance=json.loads((RUN/'provenance.json').read_text())
def sha(b):return hashlib.sha256(b).hexdigest()
checks=[]; index=[]
def export(kind,start,length,label):
    raw=data[kind][start:start+length]; assert len(raw)==length
    path=OUT/(kind+'_'+str(start)+'_'+str(length)+'.raw')
    if not path.exists():path.write_bytes(raw)
    index.append({'source':str(sources[kind]),'source_sha256':sha(data[kind]),'offset':str(start),'length':length,'raw_path':str(path),'raw_sha256':sha(raw),'selector':label})
for f in json.loads((RUN/'functions.json').read_text()):
    raw=Path(f['raw_path']).read_bytes(); source=data['binary'][f['raw_offset']:f['raw_offset']+f['raw_length']]
    decoded=b''.join(bytes.fromhex(i['bytes']) for i in f['instructions'])
    checks.append({'function':f['name'],'source_range_matches':raw==source,'sha_matches':sha(raw)==f['raw_sha256'],'decoded_complete':decoded==raw,'bytes':len(raw)})
    export('metadata',f['method']['offset'],30,f['name']+' method declaration')
    for p in f['parameters']:export('metadata',p['metadata_offset'],10,f['name']+' parameter '+p['name'])
for t in json.loads((RUN/'fields/selected_types_fields.json').read_text()):
    export('metadata',t['offset'],76,'TypeDefinition '+t['namespace']+'.'+t['name'])
    for f in t['fields']:
        export('metadata',f['offset'],10,t['name']+'.'+f['name'])
        export('binary',f['type']['descriptor_offset'],12,t['name']+'.'+f['name']+' native type descriptor')
for r in json.loads((ROOT/'test_output/brush_hit_competitor/hit_usage_resolution_20261011/resolved_usages.json').read_text()):
    if 'error' in r:continue
    export('binary',r['cell_offset'],8,r['function']+' metadata usage at '+r['instruction'])
    if 'spec_offset' in r:export('binary',r['spec_offset'],12,r['function']+' MethodSpec')
    if 'method' in r:export('metadata',r['method']['metadata_offset'],30,r['method']['name'])
source_checks=[{'path':str(p),'size':len(data[k]),'sha256':sha(data[k]),'matches_initial':sha(data[k])==provenance[k+'_sha256']} for k,p in sources.items()]
result={'functions':checks,'sources':source_checks,'raw_records':len(index),'pass':all(all(c[k] for k in ['source_range_matches','sha_matches','decoded_complete']) for c in checks) and all(c['matches_initial'] for c in source_checks),'scope':'code/selected metadata integrity; not a runtime timing or single-brush validation','command':'python tests/investigation/brush_hit_competitor/verify_hit_raw.py','script_sha256':sha(Path(__file__).read_bytes())}
(OUT/'raw_index.json').write_text(json.dumps(index,indent=2),encoding='utf8')
(OUT/'verification.json').write_text(json.dumps(result,indent=2),encoding='utf8')
inventory=ROOT/'docs/competitor/brush_hit_evidence_inventory.json'
inv=json.loads(inventory.read_text())
paths=[p for p in (ROOT/'test_output/brush_hit_competitor').rglob('*') if p.is_file() and any(s in p.as_posix() for s in ['metadata_fields_','metadata_hit_path_','hit_native_','hit_disassembly_','hit_usage_resolution_','hit_verification_'])]
paths += [p for p in (ROOT/'tests/investigation/brush_hit_competitor').glob('*.py')]
paths += list((ROOT/'tests/investigation/brush_hit_competitor/metadata_sources').glob('*.cs'))
inv['native_hit_supplement']={'date':'2026-10-11','confidence':'C3 static code, runtime correspondence/timing unknown','integrity':result,'artifacts':[{'path':p.relative_to(ROOT).as_posix(),'size':p.stat().st_size,'sha256':sha(p.read_bytes())} for p in paths]}
inventory.write_text(json.dumps(inv,indent=2),encoding='utf8')
print(json.dumps({'pass':result['pass'],'functions':len(checks),'raw_records':len(index),'artifacts':len(paths),'sources_unchanged':all(c['matches_initial'] for c in source_checks)},indent=2))
