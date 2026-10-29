"""Fixed-size independent original-DXBC holdout against the unchanged frozen noise budget."""
import argparse
import datetime
import json
import shutil
import subprocess
from pathlib import Path
from evidence_contract import identity
from reference_budget import load_budget, compare


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--output', required=True, type=Path)
    args = ap.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    base = out.parent
    budget_path = base / 't03_error_budget_20261025_v1/error_budget.json'
    budget = load_budget(budget_path)
    selected = [g for g in budget['references'][:6] if g['event_id'] in [1490, 1495, 1500]]
    exe_source = base / 't03_six_kernel_20261025_v4/sources/water_reference.exe'
    for name in ['sources', 'raw', 'comparisons']:
        (out / name).mkdir()
    exe = out / 'sources/water_reference.exe'
    shutil.copyfile(exe_source, exe)
    shutil.copyfile(exe_source.with_suffix('.cpp'), out / 'sources/water_reference.cpp')
    for name in ['run_native_holdout.py', 'reference_budget.py', 'evidence_contract.py']:
        shutil.copyfile(Path(__file__).parent / name, out / 'sources' / name)
    request = dict(operation='independent_native_holdout', repeat_count=8,
                   selected_reference_ids=[g['reference_id'] for g in selected], budget=identity(budget_path),
                   purpose='Distinguish original in-place sampled-range incompleteness from Godot lowering errors. Exactly eight repeats per selected dynamic kernel, no rerun-until-pass and no budget edits.',
                   executor=identity(exe), frozen_at=datetime.datetime.now(datetime.timezone.utc).isoformat())
    (out / 'request.json').write_text(json.dumps(request, indent=2), encoding='utf-8')
    runs, comparisons, errors = [], [], []
    for g in selected:
        for name in ['original_program', 'input', 'constants']:
            artifact = g[name]
            actual = identity(artifact['path'])
            if actual['sha256'] != artifact['sha256'] or actual['size_bytes'] != artifact['size_bytes']:
                raise ValueError('Frozen dependency changed')
        target = out / 'raw' / g['reference_id']
        command = [str(exe), '--program', g['original_program']['path'], '--input', g['input']['path'],
                   '--constants', g['constants']['path'], '--output', str(target), '--kind', 'simple', '--before-copy', '1', '--repeat', '8']
        started = datetime.datetime.now(datetime.timezone.utc).isoformat()
        result = subprocess.run(command, capture_output=True, timeout=90, creationflags=subprocess.CREATE_NO_WINDOW)
        runs.append(dict(command=command, started_at=started, finished_at=datetime.datetime.now(datetime.timezone.utc).isoformat(), exit_code=result.returncode, stdout=result.stdout.decode(errors='replace'), stderr=result.stderr.decode(errors='replace')))
        if result.returncode:
            errors.append('NATIVE_EXECUTION_FAILED:' + g['reference_id'])
            continue
        for index in range(8):
            before = identity(target / ('before_' + str(index) + '.bin'))
            if before['sha256'] != g['input']['sha256']:
                errors.append('BEFORE_INPUT_MISMATCH')
            candidate = target / ('after_' + str(index) + '.bin')
            check = compare(budget_path, g['reference_id'], candidate)
            file = out / 'comparisons' / (g['reference_id'] + '_' + str(index) + '.json')
            file.write_text(json.dumps(check, indent=2), encoding='utf-8')
            comparisons.append(dict(reference_id=g['reference_id'], repeat=index, input_verified=before['sha256']==g['input']['sha256'], result=check['verification_status'], report=identity(file)))
    outside = sum(c['result'] != 'passed' for c in comparisons)
    report = dict(operation_status='complete' if not errors else 'failed', verification_status='passed' if not errors and not outside else 'failed',
                  scope='Independent original DXBC holdout evaluated against frozen sampled ranges only. A failure is not a Godot pass or automatic budget relaxation.',
                  request=identity(out / 'request.json'), runs=runs, comparisons=comparisons, outputs_outside_frozen_budget=outside, errors=errors)
    (out / 'holdout.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    (out / 'manifest.json').write_text(json.dumps(dict(operation_status=report['operation_status'], verification_status=report['verification_status'], errors=errors, artifacts=[identity(p) for p in out.rglob('*') if p.is_file()]), indent=2), encoding='utf-8')
    print(json.dumps(dict(operation=report['operation_status'], outputs=len(comparisons), outside=outside, errors=errors)))
    raise SystemExit(bool(errors or outside))


if __name__ == '__main__':
    main()
