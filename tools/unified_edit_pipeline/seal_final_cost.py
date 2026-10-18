"""Preserve terminal cost runs, source subsets, original reference and verifiers."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile
ROOT=Path(__file__).resolve().parents[2]
def sha(raw):return hashlib.sha256(raw).hexdigest()
def main():
    p=argparse.ArgumentParser();p.add_argument('joint',type=Path);args=p.parse_args();folder=args.joint.resolve();report=json.loads((folder/'report.json').read_text('utf-8'));audit=json.loads((folder/'audit.json').read_text('utf-8'));assert report['pass'] and audit['pass']
    assert not (folder/'sources.zip').exists()
    files={};cache_variations=[]
    for name,digest in report['current_sources'].items():
        raw=(ROOT/name).read_bytes();assert sha(raw)==digest;files['current/'+name]=raw
    for name in ['tools/unified_edit_pipeline/analyze_final_cost.py','tools/unified_edit_pipeline/combine_final_cost.py','tools/unified_edit_pipeline/seal_final_cost.py','tools/unified_edit_pipeline/prepare_cost_reference.py','tools/unified_edit_pipeline/apply_cost_reference_overlay.py','tools/unified_edit_pipeline/run_remaining_cost.py','task/sandcastle_unified_edit_pipeline/验收/G0_比较方法.md','task/sandcastle_unified_edit_pipeline/验收/G0_基线噪声与比较门.json']:
        files['verification/'+name]=(ROOT/name).read_bytes()
    assert sha((ROOT/'tools/unified_edit_pipeline/analyze_final_cost.py').read_bytes())==audit['auditor_sha256']
    for key in ['uep_g8_reference01','uep_g8_reference02']:
        ref=Path('D:/godot/test_runs')/key;index_raw=(ref/'reference-index.json').read_bytes();index=json.loads(index_raw);files[key+'/reference-index.json']=index_raw
        for name,meta in index['files'].items():
            raw=(ref/name).read_bytes()
            if sha(raw)!=meta['sha256']:
                assert name in {'.godot/uid_cache.bin','.godot/global_script_class_cache.cfg'},name
                cache_variations.append({'reference':key,'path':name,'initial_sha256':meta['sha256'],'terminal_sha256':sha(raw),'role':'Mutable engine lookup cache, not game/observer code; initial identity remains in reference-index'})
            files[key+'/'+name]=raw
        for name in ['reference-index.before-render-overlay.json']:
            if (ref/name).exists():files[key+'/'+name]=(ref/name).read_bytes()
    original=ROOT/'test_output/unified_edit_pipeline/g0_final_reference_20261018/reference_sources.zip';assert sha(original.read_bytes())=='c80d051495eafd39fe7b69d6e4b0ed22f62a474b7658593bb0fc38cf8ff1939a'
    files['original-g0-reference.zip']=original.read_bytes()
    index={name:{'bytes':len(raw),'sha256':sha(raw)} for name,raw in files.items()}
    with zipfile.ZipFile(folder/'sources.zip','x',zipfile.ZIP_DEFLATED) as z:
        for name,raw in sorted(files.items()):z.writestr(name,raw)
        z.writestr('source-index.json',json.dumps(index,indent=2))
    with zipfile.ZipFile(folder/'sources.zip') as z:
        assert z.testzip() is None and len(z.namelist())==len(set(z.namelist()))
        for name,meta in index.items():assert sha(z.read(name))==meta['sha256']
    # The joint keeps original per-run paths and their immutable report hashes.
    # Index all terminal files in those source groups, including the failed start.
    artifacts={}
    for entry in report['source_groups']:
        group=Path(entry['path']).parent
        assert sha(Path(entry['path']).read_bytes())==entry['sha256']
        for path in sorted(group.rglob('*')):
            if path.is_file():artifacts[str(path)]={'bytes':path.stat().st_size,'sha256':sha(path.read_bytes())}
    for name in ['report.json','audit.json','sources.zip']:
        path=folder/name;artifacts[str(path)]={'bytes':path.stat().st_size,'sha256':sha(path.read_bytes())}
    (folder/'artifact-index.json').write_text(json.dumps(artifacts,indent=2),'utf-8')
    result={'pass':True,'source_files':len(files),'source_zip_sha256':sha((folder/'sources.zip').read_bytes()),'source_zip_members':len(files)+1,'artifact_files':len(artifacts),'cache_variations':cache_variations,'scope':'Exact source/verifier/reference corpus and terminal evidence. Mutable engine lookup caches are explicitly distinguished from the unchanged game and observer source bytes.'}
    (folder/'seal.json').write_text(json.dumps(result,indent=2),'utf-8');print('COST_SEALED',len(files),len(artifacts))
if __name__=='__main__':main()
