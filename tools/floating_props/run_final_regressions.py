"""Serial affected-scope regression matrix. Fresh evidence; stop on a real failure."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
CASES = [
    ('native_migration', 'native_migration_probe', 'normal', None),
    ('lifecycle_cycles', 'lifecycle_cycles_probe', 'normal', None),
    *[(f'entry_{key}', 'four_entries_probe', key, None) for key in ['main', 'test1_capture', 'test1_backwash', 'test1_geometry']],
    ('isolation', 'isolation_probe', 'normal', None),
    ('runtime', 'runtime_probe', 'normal', None),
    ('service_api', 'service_api_probe', 'normal', 'bottle'),
    ('fault_recovery', 'fault_recovery_probe', 'normal', None),
    ('wave', 'wave_probe', 'wave', 'bottle'),
    ('rolling', 'rolling_probe', 'rolling', 'bottle'),
    *[(f'contact_{key}', 'contact_probe', key, 'bottle') for key in ['bed_fill', 'bed_dig', 'cross_chunk', 'collision_pair', 'erosion_continuous']],
    *[(f'stack_{key}', 'stack_contact_probe', key, None) for key in ['hover_edit', 'stack_fill']],
    *[(f'three_{key}', 'three_props_probe', key, 'bottle') for key in ['flow_positive', 'flow_negative', 'tilt_width', 'tilt_length']],
    *[(f'sample_{key}', 'sample_probe', key, 'sample') for key in ['linear', 'constant', 'thin']],
    ('height_priority', 'height_priority_probe', 'normal', 'height_bounds'),
    ('height_faults', '../integration/unified_edit_height_probe', 'height_faults', None),
    ('active_lifecycle', 'active_lifecycle_probe', 'normal', None),
    ('scene_reentry', 'scene_reentry_probe', 'normal', None),
]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--previous', type=Path)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    (output/'matrix_runner.py').write_bytes(Path(__file__).read_bytes())
    previous = {}
    if args.previous:
        prior = json.loads((args.previous/'progress.json').read_text('utf-8-sig'))
        previous = {row['name']: row for row in prior['rows'] if row['passed']}
    spec = __import__('importlib.util', fromlist=['util']).spec_from_file_location('audit', ROOT/'tools/unified_edit_pipeline/audit_architecture.py')
    audit = __import__('importlib.util', fromlist=['util']).module_from_spec(spec)
    spec.loader.exec_module(audit)
    production, _, _ = audit.graph()
    production = {p: hashlib.sha256(raw).hexdigest() for p, raw in production.items()}
    rows = []
    for name, script, case, verifier in CASES:
        print('FINAL_REGRESSION_BEGIN', name, flush=True)
        folder = output/name
        path = (ROOT/'tests/floating_props'/(script+'.gd')).resolve().relative_to(ROOT).as_posix()
        command = [sys.executable, str(ROOT/'tools/floating_props/run_probe.py'), '--output', str(folder), '--script', path, '--case', case, '--timeout', '900' if name == 'lifecycle_cycles' else '240', '--quit-after', '90000']
        reused = False
        if name in previous:
            prior = previous[name]
            prior_command = prior['command']
            if prior_command[prior_command.index('--script')+1] == path and prior_command[prior_command.index('--case')+1] == case:
                folder = Path(prior.get('evidence_dir', args.previous/name)).resolve()
                manifest = json.loads((folder/'run-manifest.json').read_text('utf-8-sig'))
                assert manifest['pass'] and not manifest['drift'] and all(manifest['sources'].get(p) == h for p, h in production.items()), name
                assert hashlib.sha256((folder/'run-manifest.json').read_bytes()).hexdigest() == prior['manifest_sha256']
                command = prior_command
                reused = True
        code = 0 if reused else subprocess.run(command, cwd=ROOT).returncode
        if not reused and not code and verifier:
            code = subprocess.run([sys.executable, str(ROOT/'tools/floating_props'/f'verify_{verifier}.py'), str(folder)], cwd=ROOT).returncode
        row = dict(name=name, command=command, passed=code == 0, evidence_dir=str(folder), reused_verified_evidence=reused)
        if (folder/'run-manifest.json').exists():
            manifest = json.loads((folder/'run-manifest.json').read_text('utf-8-sig'))
            row.update(checks=manifest['checks'], manifest_sha256=hashlib.sha256((folder/'run-manifest.json').read_bytes()).hexdigest())
        rows.append(row)
        (output/'progress.json').write_text(json.dumps(dict(rows=rows, total=len(CASES), passed=all(r['passed'] for r in rows), complete=len(rows) == len(CASES)), indent=2)+'\n', encoding='utf-8')
        print('FINAL_REGRESSION_RESULT', name, row['passed'], flush=True)
        if code:
            raise SystemExit(code)


if __name__ == '__main__':
    main()
