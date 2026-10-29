"""Join the completed component evidence and the exact G4 compatibility path."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile
def main():
    p=argparse.ArgumentParser();p.add_argument('--project',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();project=a.project.resolve();base=project/'test_output/wave_propagation';out=a.output.resolve();out.mkdir(parents=True,exist_ok=False);fail=[];inputs={}
    def check(ok,reason):
        if not ok:fail.append(reason)
    def load(path):
        raw=path.read_bytes();inputs[str(path)]=hashlib.sha256(raw).hexdigest();return json.loads(raw)
    previous=load(base/'g4_intermediate_audit_02/result.json');check(previous['outcome']=='pass','published state, cold restart, clocks and lifetime component audit')
    for name,h in previous['input_hashes'].items():check(hashlib.sha256(Path(name).read_bytes()).hexdigest()==h,'component input changed '+name)
    for directory,name in [('g4_configuration_01','result.json'),('g4_migration_04','result.json'),('g4_rebuilt_legacy_01/data','result.json'),('g4_catalog_negative_01','result.json')]:check(load(base/directory/name)['outcome']=='pass',directory)
    for directory in ['g4_source_restore_02','g4_source_foreign_01','g4_algorithm_switch_02']:
        folder=base/directory;r=load(folder/'probe.json');m=load(folder/'manifest.json');check(r['pass'] and r['checks'] and all(c['pass'] for c in r['checks']),directory+' checks');check(m['outcome']=='pass' and m['exit_code']==0 and not m['source_drift'],directory+' process')
        with zipfile.ZipFile(folder/'consumed_sources.zip') as z:
            for name,h in r['observations']['sources'].items():check(hashlib.sha256(z.read(name.removeprefix('res://'))).hexdigest()==h,directory+' source '+name)
        if directory=='g4_source_restore_02':
            check(len(r['observations']['migrations'])==7,'all seven source migrations')
            check(all(not row['error'] for row in r['observations']['capture_attempts']),'all public resaves admitted at ready boundary')
            for row in r['observations']['migrations']:
                for key in ['source','saved']:check(hashlib.sha256(Path(row[key]['path']).read_bytes()).hexdigest()==row[key]['sha256'],'source/native container identity')
        elif directory=='g4_source_foreign_01':check(len(r['observations']['foreign_rejections'])==7,'all seven foreign sources rejected without replacing current')
        else:
            for row in r['files'].values():check(hashlib.sha256(Path(row['path']).read_bytes()).hexdigest()==row['sha256'],'same-release switch container identity')
    for directory in ['g4_source_restore_02','g4_algorithm_switch_02']:check(load(base/directory/'independent_audit.json')['outcome']=='pass',directory+' independent actual-file audit')
    old=load(base/'g4_service_matrix_03/four_scene_service/probe.json')['observations']['sources'];new=load(base/'g4_source_restore_02/probe.json')['observations']['sources']
    changed={name:{'before':old[name],'after':new[name]} for name in old.keys()&new.keys() if old[name]!=new[name]}
    expected={'res://scripts/simulation/unified_edit/configuration.gd','res://scripts/simulation/unified_edit/checkpoint_codec.gd','res://scripts/simulation/unified_edit/numerics_checkpoint_sources.gd','res://assets/unified_edit/numerics_source_catalog.variant'}
    check(set(changed)==expected,'targeted compatibility-only changes since lifetime matrix')
    scope_only=[]
    for name in old.keys()-new.keys():
        file=base/'g4_workspace_01'/name.removeprefix('res://');check(hashlib.sha256(file.read_bytes()).hexdigest()==old[name],'unchanged other-scene source '+name);scope_only.append(name)
    current_drift=[name for name,h in new.items() if not (project/name.removeprefix('res://')).is_file() or hashlib.sha256((project/name.removeprefix('res://')).read_bytes()).hexdigest()!=h]
    check(not current_drift,'current workspace consumed-source drift')
    result={'schema':1,'gate':'G4','outcome':'fail' if fail else 'pass','failures':fail,'input_hashes':inputs,'changed_shared_sources':changed,'prior_other_scene_scope_only_unchanged':sorted(scope_only),'current_workspace_drift':current_drift,'scope':'T04 final completed state, real Jolt sample clock, native cold recovery, exact historical and same-release source compatibility, and failure/retirement behavior. No G5 experience, G6 long-stability or cost acceptance.','audit_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
    (out/Path(__file__).name).write_bytes(Path(__file__).read_bytes());(out/'result.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print(json.dumps({k:v for k,v in result.items() if k not in ['input_hashes','changed_shared_sources','prior_other_scene_scope_only_unchanged']},indent=2));raise SystemExit(bool(fail))
if __name__=='__main__':main()
