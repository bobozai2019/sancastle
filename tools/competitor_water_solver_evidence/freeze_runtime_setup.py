"""Freeze T05-G01 setup evidence; explicitly does not accept D07 or G4."""
import argparse
import datetime
import json
import shutil
from pathlib import Path
from evidence_contract import identity
from audit_runtime_pilot import closure

BASE=Path('D:/godot/project/sandcastle/docs/competitor/evidence/water_solver_reconstruction')

def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--output',required=True,type=Path);args=ap.parse_args();out=args.output.resolve()
    if not str(out).isascii():raise ValueError('ASCII output required')
    out.mkdir(parents=True,exist_ok=False);errors=[];inputs={}
    names=['t05_runtime_copy_20261025_v1','t05_renderdoc_helper_20261025_v5','t05_modes_baseline_20261025_v1','t05_modes_light_20261025_v1','t05_modes_capture_20261025_v2','t05_consumption_20261025_v1','t05_consumption_20261025_v2','t05_modes_audit_20261025_v1']
    for name in names:
        path=BASE/name/'manifest.json';inputs[name]=identity(path)
        data=json.loads(path.read_text())
        if data['operation_status']!='complete':errors.append(name+':operation_not_complete')
        for expected in data.get('artifacts',[]):
            actual=identity(expected['path'])
            if actual['sha256']!=expected['sha256'] or actual['size_bytes']!=expected['size_bytes']:errors.append('ARTIFACT_IDENTITY_MISMATCH:'+expected['path'])
    helper=json.loads((BASE/names[1]/'manifest.json').read_text())
    if helper['verification_status']!='passed' or not helper['result']['guard_ready_before_main'] or helper['result']['renderdoc_api_result']!=1 or helper['real_registry_marker_after']:errors.append('HELPER_ISOLATION_OR_INJECTION_FAILED')
    coverage=[];stats=[]
    for name in ['t05_modes_light_20261025_v1','t05_modes_capture_20261025_v2']:
        run=BASE/name;data=json.loads((run/'manifest.json').read_text());raw=json.loads((run/'logs/events.json').read_text());events=[e for m in raw if m.get('payload',{}).get('kind')=='water_trace' for e in m['payload']['events']];stat=json.loads((run/'observer_final.json').read_text());trace_errors=closure(events,stat)
        if trace_errors:errors.extend(name+':'+e for e in trace_errors)
        if any(e['kind'].startswith('unsupported_water') for e in events):errors.append(name+':UNMODELED_WATER_PATH')
        if not data['watched_source_and_user_data_unchanged']:errors.append(name+':SOURCE_CHANGED')
        coverage.append(dict(run=name,observer_source=identity(run/'sources/water_observer.js'),events=[e for e in events if e['kind'] in ['hook_installed','hook_alias_skipped','coverage_limit']],unmodeled_water_paths_observed=0))
        stats.append(dict(run=name,stats=stat,trace_errors=trace_errors))
    if coverage[0]['observer_source']['sha256']!=coverage[1]['observer_source']['sha256']:errors.append('OBSERVER_VERSION_MISMATCH')
    for name in ['t05_consumption_20261025_v1','t05_consumption_20261025_v2']:
        data=json.loads((BASE/name/'consumption.json').read_text())
        if data['verification_status']!='passed' or data['errors'] or len({e['stage'] for e in data['gpu_chain']})!=6:errors.append(name+':GPU_CORRESPONDENCE_FAILED')
    comparison=json.loads((BASE/'t05_modes_audit_20261025_v1/comparison.json').read_text())
    if comparison['comparability_errors']:errors.extend(comparison['comparability_errors'])
    limitations=['Accepted setup is limited to this executable/hash, seeded startup and observed direct water path, not every interaction','No all-process/OS sandbox claim; non-disk devices and pipes allowed','Source and selected user files/registry are monitored, not all Windows state','Unmodeled water setter/array/keyword or command paths fail closed','Pointer reuse beyond observed lifetime and compound command bindings not universally closed','GPU light_factor=1 sampled but CPU setter origin unmapped','Common baseline includes guard and Present observer; no observer-free original cadence claim','D07/window perturbation, formal trajectories, original clock and Godot validation are not accepted']
    setup=dict(schema_version='1.0',milestone='T05-G01',verification_status='passed' if not errors else 'failed',accepted_observer_sha256=coverage[0]['observer_source']['sha256'],program_copy=inputs[names[0]],helper=inputs[names[1]],runtime_runs=[inputs[n] for n in names[2:5]],consumption_spotchecks=[inputs[n] for n in names[5:7]],statistics=stats,inputs=inputs,limitations=limitations,errors=errors)
    (out/'runtime_setup.json').write_text(json.dumps(setup,indent=2),encoding='utf-8');(out/'hook_coverage.json').write_text(json.dumps(dict(accepted=not errors,coverage=coverage,limitations=limitations),indent=2),encoding='utf-8')
    for name in ['freeze_runtime_setup.py','evidence_contract.py','audit_runtime_pilot.py']:
        shutil.copyfile(Path(__file__).parent/name,out/name)
    (out/'manifest.json').write_text(json.dumps(dict(operation_status='complete',verification_status=setup['verification_status'],created_at=datetime.datetime.now(datetime.timezone.utc).isoformat(),errors=errors,scope='T05-G01 setup only, no G02/D07/G4 acceptance',inputs=inputs,artifacts=[identity(p) for p in out.iterdir() if p.is_file()]),indent=2),encoding='utf-8')
    print(json.dumps(dict(milestone='T05-G01',verification_status=setup['verification_status'],observer_sha256=setup['accepted_observer_sha256'],errors=errors)))
    raise SystemExit(1 if errors else 0)

if __name__=='__main__':main()
