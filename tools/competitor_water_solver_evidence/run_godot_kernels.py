"""Execute candidate packed single kernels and compare exact identities to frozen original bands."""
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
    ap.add_argument('--lowering', required=True, type=Path)
    ap.add_argument('--all', action='store_true', help='All 72 frozen identities after initial six-case pilot')
    ap.add_argument('--fixture-prefix', nargs='+', help='Select frozen fixture names by provenance local-reference prefix')
    ap.add_argument('--repeat', type=int, default=3)
    ap.add_argument('--driver', choices=['vulkan', 'd3d12'], default='vulkan')
    ap.add_argument('--budget', type=Path, help='Explicit versioned budget; defaults to original v1')
    ap.add_argument('--godot', type=Path, default=Path('D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'))
    args = ap.parse_args()
    if not 1 <= args.repeat <= 3:
        raise ValueError('Bounded repeat count 1..3')
    root = Path(__file__).resolve().parents[3]
    project = root / 'tests/investigation/water_solver_evidence_probe'
    base = root / 'docs/competitor/evidence/water_solver_reconstruction'
    budget_path = args.budget.resolve() if args.budget else base / 't03_error_budget_20261025_v1/error_budget.json'
    budget = load_budget(budget_path)
    lowering = json.loads((args.lowering / 'lowering.json').read_text())
    selected = budget['references'] if args.all else budget['references'][:6]
    if args.fixture_prefix:
        if args.all:
            raise ValueError('Use either all or fixture prefixes')
        selected = [g for g in budget['references'] if any(p['local_reference_id'].startswith(prefix) for p in g['provenance'] for prefix in args.fixture_prefix)]
        if not selected:
            raise ValueError('No frozen fixture matched')
    out = args.output.resolve()
    if not str(out).isascii():
        raise ValueError('ASCII output required')
    out.mkdir(parents=True, exist_ok=False)
    for folder in ['sources', 'inputs', 'raw', 'comparisons']:
        (out / folder).mkdir()
    for source in [*project.rglob('*.gd'), *project.rglob('*.glsl'), *project.glob('*.tscn'), project / 'project.godot', Path(__file__), Path(__file__).with_name('reference_budget.py'), Path(__file__).with_name('evidence_contract.py')]:
        shutil.copyfile(source, out / 'sources' / source.name)

    def checked_copy(artifact):
        actual = identity(artifact['path'])
        if actual['sha256'] != artifact['sha256'] or actual['size_bytes'] != artifact['size_bytes']:
            raise ValueError('SOURCE_ARTIFACT_CHANGED:' + artifact['path'])
        target = out / 'inputs' / (actual['sha256'] + '.bin')
        if not target.exists():
            shutil.copyfile(artifact['path'], target)
        return dict(**identity(target), source=artifact)

    cases = []
    for group in selected:
        program = next(p for p in lowering['programs'] if p['event'] == group['event_id'])
        if identity(program['shader']['path'])['sha256'] != program['shader']['sha256']:
            raise ValueError('CANDIDATE_SHADER_CHANGED')
        source_hash = identity(args.lowering / ('e' + str(group['event_id']) + '_inplace.glsl'))['sha256']
        if source_hash != program['shader']['sha256']:
            raise ValueError('LOWERING_RECEIPT_CHANGED')
        original = checked_copy(group['original_program'])
        cases.append(dict(case_id=group['reference_id'], event_id=group['event_id'],
                          original_program=original, input=checked_copy(group['input']),
                          constants=checked_copy(group['constants']), srvs=[checked_copy(a) for a in group['srvs']],
                          shader_sha256=program['shader']['sha256']))
    request = dict(schema_version='1.0', mode='candidate_original_alias_packed_lowering',
                   output_root=(out / 'raw').as_posix(), budget=identity(budget_path),
                   lowering=identity(args.lowering / 'lowering.json'), repeat_count=args.repeat, cases=cases)
    request_path = out / 'request.json'
    request_path.write_text(json.dumps(request, indent=2), encoding='utf-8')
    command = [str(args.godot), '--path', str(project), '--rendering-method', 'mobile', '--rendering-driver', args.driver,
               '--log-file', str(out / 'engine.log'), 'res://kernel_probe.tscn', '--', '--request', str(request_path)]
    started = datetime.datetime.now(datetime.timezone.utc).isoformat()
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, creationflags=subprocess.CREATE_NO_WINDOW)
    timed_out = False
    try:
        stdout, stderr = process.communicate(timeout=180)
    except subprocess.TimeoutExpired:
        timed_out = True
        process.kill()  # Exact owned process instance only.
        stdout, stderr = process.communicate()
    (out / 'stdout.bin').write_bytes(stdout)
    (out / 'stderr.bin').write_bytes(stderr)
    result_file = out / 'raw/probe_result.json'
    result = json.loads(result_file.read_text()) if result_file.exists() else None
    comparisons, errors = [], []
    if process.returncode or timed_out or not result or result['operation_status'] != 'complete':
        errors.append('GODOT_KERNEL_RUN_FAILED')
    else:
        for case in result['cases']:
            for repeat in case['repeats']:
                comparison = compare(budget_path, case['case_id'], repeat['after'])
                file = out / 'comparisons' / (case['case_id'] + '_' + str(repeat['index']) + '.json')
                file.write_text(json.dumps(comparison, indent=2), encoding='utf-8')
                if comparison['verification_status'] != 'passed':
                    errors.append(dict(code='NUMERIC_COMPARISON_FAILED', case_id=case['case_id'], repeat=repeat['index'], comparison=identity(file)))
                comparisons.append(dict(case_id=case['case_id'], repeat=repeat['index'], result=comparison['verification_status'], report=identity(file)))
    report = dict(operation_status='complete' if result and result['operation_status']=='complete' else 'failed',
                  verification_status='passed' if not errors else 'failed',
                  scope='Selected frozen sampled identities only. Not short sequence, ping-pong, lifecycle or G5 acceptance.',
                  command=command, pid=process.pid, exit_code=process.returncode, timed_out=timed_out,
                  started_at=started, finished_at=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                  godot=identity(args.godot), request=identity(request_path), budget=identity(budget_path),
                  lowering=identity(args.lowering / 'lowering.json'), result=result, comparisons=comparisons, errors=errors)
    (out / 'kernel_audit.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    (out / 'manifest.json').write_text(json.dumps(dict(operation_status=report['operation_status'], verification_status=report['verification_status'], errors=errors, artifacts=[identity(p) for p in out.rglob('*') if p.is_file()]), indent=2), encoding='utf-8')
    print(json.dumps(dict(operation=report['operation_status'], verification=report['verification_status'], comparisons=len(comparisons), failed=sum(c['result']!='passed' for c in comparisons), errors=[e for e in errors if isinstance(e,str)])))
    raise SystemExit(bool(errors))


if __name__ == '__main__':
    main()
