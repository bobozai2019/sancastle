"""Predeclared fixed original-DXBC supplementary matrix, independent of candidate outputs."""
import argparse
import datetime
import json
import shutil
import subprocess
from pathlib import Path
from evidence_contract import identity
from reference_budget import load_budget


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--output', required=True, type=Path)
    args = ap.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    base = out.parent
    budget_path = base / 't03_error_budget_20261025_v1/error_budget.json'
    budget = load_budget(budget_path)
    source = base / 't03_six_kernel_20261025_v4'
    frozen = json.loads((source / 'manifest.json').read_text())
    exe_source = source / 'sources/water_reference.exe'
    expected = next(a for a in frozen['artifacts'] if a['path'] == exe_source.as_posix())
    if identity(exe_source)['sha256'] != expected['sha256']:
        raise ValueError('Original executor changed')
    if shutil.disk_usage(out).free < 14 * 1024**3:
        raise ValueError('Need 14 GiB free for fixed matrix plus reserve; no GPU work started')
    for name in ['sources', 'raw', 'logs']:
        (out / name).mkdir()
    exe = out / 'sources/water_reference.exe'
    shutil.copyfile(exe_source, exe)
    shutil.copyfile(exe_source.with_suffix('.cpp'), out / 'sources/water_reference.cpp')
    for name in ['collect_native_matrix.py','evidence_contract.py','reference_budget.py']:
        shutil.copyfile(Path(__file__).parent / name, out / 'sources' / name)
    request = dict(schema_version='1.0', frozen_before_execution=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                   program_and_input_selection=identity(budget_path), reference_ids=[g['reference_id'] for g in budget['references']],
                   repeat_count=16, before_copy_modes=[True, False], total_experiments=144, total_outputs=2304,
                   purpose='Old budget rejected 24/24 independent unmodified original outputs. Supplement all 72 frozen identities with 16+16 original outputs, not Godot-driven per-point allowances.',
                   unchanged=['Original DXBC', 'original executor binary/source', 'full input/constants/SRV hashes', '16x8 groups and 32x32 threads', 'zero added numeric allowance'],
                   failure_policy='Stop on operation/input/fence error; preserve partial data. Fixed count, no extra repetitions chosen by candidate or acceptance result.',
                   executor=expected, prior_counterexample=identity(base / 't06_native_holdout_20261025_v1/holdout.json'))
    (out / 'request.json').write_text(json.dumps(request, indent=2), encoding='utf-8')
    report = dict(schema_version='1.0', operation_status='running', verification_status='not_evaluated', errors=[], references=[], request=identity(out / 'request.json'),
                  scope='Unmodified original-program supplementary sampled outputs, not universal bounds or Godot acceptance')

    def save():
        (out / 'manifest.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    save()
    try:
        for group_index, g in enumerate(budget['references']):
            for artifact in [g['original_program'], g['input'], g['constants'], *g['srvs']]:
                actual = identity(artifact['path'])
                if actual['sha256'] != artifact['sha256'] or actual['size_bytes'] != artifact['size_bytes']:
                    raise ValueError('FROZEN_DEPENDENCY_CHANGED')
            event = g['event_id']
            kind = 'floor' if event == 1484 else 'sources' if event == 1537 else 'simple'
            for before_copy in [True, False]:
                name = g['reference_id'] + '_copy' + str(int(before_copy))
                target = out / 'raw' / name
                command = [str(exe), '--program', g['original_program']['path'], '--input', g['input']['path'],
                           '--constants', g['constants']['path'], '--output', str(target), '--kind', kind,
                           '--before-copy', str(int(before_copy)), '--repeat', '16']
                if kind == 'floor':
                    command += ['--srv0', g['srvs'][0]['path']]
                if kind == 'sources':
                    command += ['--texture0', g['srvs'][0]['path'], '--srv1', g['srvs'][1]['path']]
                started = datetime.datetime.now(datetime.timezone.utc).isoformat()
                result = subprocess.run(command, capture_output=True, timeout=90, creationflags=subprocess.CREATE_NO_WINDOW)
                (out / 'logs' / (name + '.stdout.bin')).write_bytes(result.stdout)
                (out / 'logs' / (name + '.stderr.bin')).write_bytes(result.stderr)
                if result.returncode:
                    raise ValueError('ORIGINAL_EXECUTION_FAILED:' + name)
                executions = [json.loads(line) for line in (target / 'execution.jsonl').read_text().splitlines()]
                if len(executions) != 16:
                    raise ValueError('EXECUTION_LOG_NOT_CLOSED')
                checks = []
                for index, execution in enumerate(executions):
                    complete = execution['fence_completed'] >= execution['fence_ticket']
                    if not complete or execution['repeat'] != index or execution['dispatch'] != [16,8,1] or execution['threads'] != [32,32,1]:
                        raise ValueError('GPU_COMPLETION_OR_LAYOUT_NOT_PROVEN')
                    before = None
                    srv_proofs = []
                    if before_copy:
                        before = identity(target / ('before_' + str(index) + '.bin'))
                        if before['sha256'] != g['input']['sha256']:
                            raise ValueError('GPU_WATER_BEFORE_MISMATCH')
                        for slot, artifact in enumerate(g['srvs']):
                            observed = identity(target / ('srv' + str(slot) + '_before_' + str(index) + '.bin'))
                            if observed['sha256'] != artifact['sha256']:
                                raise ValueError('GPU_SRV_BEFORE_MISMATCH')
                            srv_proofs.append(observed)
                    checks.append(dict(repeat=index, output=identity(target / ('after_' + str(index) + '.bin')), fence_complete=complete,
                                       before=before, srvs_before=srv_proofs,
                                       pairing='GPU full before hash' if before_copy else 'Same validated restore path without before-copy; no direct same-dispatch GPU-before snapshot'))
                report['references'].append(dict(reference_id=name, request=dict(event_id=event, program=g['original_program'], input=g['input'],
                    constants=g['constants'], srvs=g['srvs'], before_copy=before_copy), checks=checks,
                    command=command, started_at=started, finished_at=datetime.datetime.now(datetime.timezone.utc).isoformat(), exit_code=result.returncode,
                    device=identity(target / 'device.json'), execution=identity(target / 'execution.jsonl')))
                save()
                (out / 'logs/progress.json').write_text(json.dumps(dict(completed=len(report['references']), total=144, group_index=group_index, reference_id=g['reference_id'])), encoding='utf-8')
                print(json.dumps(dict(completed=len(report['references']), total=144, reference_id=g['reference_id'], before_copy=before_copy)), flush=True)
        report['operation_status'] = 'complete'
        report['verification_status'] = 'passed'
    except Exception as error:
        report['operation_status'] = 'failed'
        report['errors'].append(str(error))
    report['artifacts'] = [identity(p) for p in out.rglob('*') if p.is_file() and p.name != 'manifest.json']
    save()
    print(json.dumps(dict(operation=report['operation_status'], experiments=len(report['references']), errors=report['errors'])), flush=True)
    raise SystemExit(bool(report['errors']))


if __name__ == '__main__':
    main()
