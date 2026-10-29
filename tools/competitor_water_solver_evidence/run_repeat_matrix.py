"""Freeze and execute a small serial RenderDoc repeat matrix (no live game)."""
import argparse
import datetime
import json
import subprocess
import sys
from pathlib import Path
from evidence_contract import identity


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline-request', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    out = args.output
    if not out.is_absolute() or not str(out).isascii():
        raise ValueError('Absolute ASCII output required')
    out.mkdir(parents=True, exist_ok=False)
    for name in ['sources', 'raw', 'derived', 'logs', 'requests']:
        (out / name).mkdir()
    tools = Path(__file__).resolve().parent
    baseline = json.loads(args.baseline_request.read_text())
    experiments = [('cached', 3), ('force', 3), ('fresh', 3), ('process', 1), ('process', 1), ('process', 1)]
    requests = []
    for index, (mode, count) in enumerate(experiments):
        req = dict(baseline)
        req.update(run_id=out.name + '_%d_%s' % (index, mode), operation='repeat', repeat_mode=mode, sample_count=count,
                   repeat_index=index, replay_instance_id=out.name + '_process%d' % index,
                   variation=dict(factor='replay_selection_and_lifetime', old_value='cached', new_value=mode))
        req.pop('events', None)
        req['output_root'] = (out.parent / req['run_id']).as_posix()
        req['tool'] = dict(name='repeat_replay.py', script=identity(tools / 'repeat_replay.py'), version='1.0')
        path = out / ('requests/group%d.json' % index)
        path.write_text(json.dumps(req, indent=2), encoding='utf-8')
        requests.append(path)
    matrix = dict(frozen_at=datetime.datetime.now(datetime.timezone.utc).isoformat(),
        experiments=[dict(mode=m, sample_count=n, request=identity(p)) for (m,n),p in zip(experiments,requests)],
        fixed=['Capture SHA256', 'E1490/E1495 shader hashes', 'UAV resource/extent/stride', 'machine and RenderDoc binary'],
        hypotheses=['Cached readback may be stable while forced replay differs',
                    'Upstream candidate state may vary with replay, so output differences cannot establish in-kernel races',
                    'Fresh controller or independent process may change the variation distribution'],
        input_proof='unproven: post E1490 selection is not an enclosed E1495 pre-state',
        budgets=None, limitations=['Three samples diagnose gross instability; not a statistical bound', 'No Godot candidate is tested'])
    (out / 'repeat_matrix.json').write_text(json.dumps(matrix, indent=2), encoding='utf-8')
    for name in ['run_repeat_matrix.py', 'run_replay.py', 'repeat_replay.py', 'evidence_contract.py']:
        (out / 'sources' / name).write_bytes((tools / name).read_bytes())
    results = []
    for path in requests:
        command = [sys.executable, '-X', 'utf8', str(tools / 'run_replay.py'), '--request', str(path), '--script', str(tools / 'repeat_replay.py')]
        print(json.dumps(dict(phase='launch_group', request=path.as_posix())), flush=True)
        result = subprocess.run(command, capture_output=True, text=True)
        log = out / 'logs' / (path.stem + '.txt')
        log.write_text(result.stdout + result.stderr, encoding='utf-8')
        results.append(dict(request=identity(path), exit_code=result.returncode, log=identity(log)))
        (out / 'logs/progress.json').write_text(json.dumps(results, indent=2), encoding='utf-8')
        if result.returncode:
            break
    (out / 'manifest.json').write_text(json.dumps(dict(operation_status='complete' if len(results)==len(requests) and all(r['exit_code']==0 for r in results) else 'partial',
        verification_status='not_evaluated', results=results, artifacts=[identity(p) for p in out.rglob('*') if p.is_file()]), indent=2), encoding='utf-8')
    print(json.dumps(dict(finished_groups=len(results), results=results)), flush=True)


if __name__ == '__main__':
    main()
