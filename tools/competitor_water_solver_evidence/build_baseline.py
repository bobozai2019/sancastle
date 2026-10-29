"""Read-only baseline inventory and request negative checks for T00."""
import argparse
import copy
import datetime
import json
import platform
import shutil
import subprocess
import sys
from pathlib import Path
from evidence_contract import identity, validate

ROOT = Path('D:/godot/project/sandcastle')
TASK = ROOT / 'task/competitor_water_solver_evidence'


def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    out = args.output
    if not out.is_absolute() or not str(out).isascii():
        raise ValueError('Absolute ASCII output required')
    out.mkdir(parents=True, exist_ok=False)
    for name in ['raw', 'derived', 'sources', 'logs']:
        (out / name).mkdir()
    old = json.loads((ROOT / 'docs/competitor/evidence/water_gap_recovery_20261025_v1/inventory.json').read_text(encoding='utf-8'))
    paths = {row['path']: row for row in old['files'] + old['captures']}
    for p in (ROOT / 'sandcastlegame/Sandcastle_Data').rglob('*'):
        if p.is_file():
            paths.setdefault(p.as_posix(), {})
    for name in ['UnityPlayer.dll', 'baselib.dll']:
        paths.setdefault((ROOT / 'sandcastlegame' / name).as_posix(), {})
    baseline = []
    for path, expected in paths.items():
        actual = identity(path)
        baseline.append(dict(actual=actual, historical=expected or None,
                             matches_historical=None if not expected else actual['sha256'] == expected.get('sha256') and actual['size_bytes'] == expected.get('bytes')))
    write(out / 'source_baseline.json', baseline)
    git = subprocess.run(['git', '-c', 'core.quotepath=false', 'status', '--porcelain=v1', '--untracked-files=all'], cwd=ROOT, capture_output=True, encoding='utf-8', check=True)
    (out / 'logs/worktree_before.txt').write_text(git.stdout, encoding='utf-8')
    powershell = subprocess.run(['powershell', '-NoProfile', '-Command',
        "[pscustomobject]@{GPU=@(Get-CimInstance Win32_VideoController | Select-Object Name,DriverVersion,PNPDeviceID);Processes=@(Get-Process | Where-Object { $_.ProcessName -match 'godot|qrenderdoc|sandcastle' } | Select-Object Id,ProcessName,Path);RenderDocVersion=(Get-Item -LiteralPath 'D:/other_software/RenderDoc/qrenderdoc.exe').VersionInfo.FileVersion} | ConvertTo-Json -Depth 5"], capture_output=True, text=True, check=True)
    env = dict(time=datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),
               os=platform.platform(), python=sys.version, executable=sys.executable,
               system=json.loads(powershell.stdout), command=sys.argv,
               graphics_backend=None, godot_version=None,
               limitation='No replay or Godot launched. Process list cannot prove absence of all GPU activity.',
               allowed_writes=[TASK.as_posix(), (ROOT / 'docs/competitor/evidence/water_solver_reconstruction').as_posix()],
               originals='read-only; no game launch in T00', evidence_self_contained=False)
    write(out / 'environment.json', env)
    contracts = []
    for path in sorted((TASK / '契约').glob('*.md')):
        target = out / 'sources' / ('contract_' + str(len(contracts)) + '.md')
        shutil.copyfile(path, target)
        contracts.append(dict(original=identity(path), snapshot=identity(target)))
    write(out / 'contract_freeze.json', dict(version='1.0', frozen_at=env['time'], contracts=contracts,
        scope='C01 identity; C02 fields only; C03 method only; C04 fields only; C05 isolation boundary',
        deferred=['stage selectors T01', 'numeric budgets T03', 'observation window T05', 'Godot probe path T06']))
    src = identity(ROOT / 'sandcastlegame/test1.rdc')
    request = dict(schema_version='1.0', run_id='t01_pilot_20261025_v1', mode='rdc_replay', operation='sync_graph',
        source=dict(source_id='rdc:' + src['sha256'], source_path=src['path'], source_size=src['size_bytes'], source_sha256=src['sha256']),
        selector=dict(capture_sha256=src['sha256'], event_id=1495, stage='compute', boundary='post-dispatch',
                      shader_sha256=None, preliminary=True), fixed_inputs=[], repeat_index=0,
        replay_instance_id='t01_pilot_20261025_v1_open0', variation=None,
        output_root=(out.parent / 't01_pilot_20261025_v1').as_posix(),
        environment=env, tool=dict(name='pilot_replay.py', version=None, sha256=None, command=None),
        questions=['Are all water read dependencies exportable?', 'Do complete API records show kernel barriers and queue dependencies?',
                   'Can snapshots be proved to enclose the same dispatch?'],
        hypotheses=['Post-event snapshots are available but separate replays do not prove pairing', 'Missing API/descriptor data requires targeted recovery'],
        numeric_budget=None)
    write(out / 'pilot_request.json', request)
    (TASK / 'requests').mkdir(exist_ok=True)
    write(TASK / 'requests/pilot_request.json', request)
    cases = [('valid', request, None)]
    bad = copy.deepcopy(request); bad['source']['source_sha256'] = '0' * 64
    cases.append(('wrong_hash', bad, 'SOURCE_IDENTITY_MISMATCH'))
    bad = copy.deepcopy(request); del bad['selector']
    cases.append(('missing_field', bad, 'FIELD_MISSING'))
    bad = copy.deepcopy(request); bad['output_root'] = out.as_posix()
    cases.append(('existing_output', bad, 'OUTPUT_INVALID'))
    bad = copy.deepcopy(request); bad['selector']['capture_sha256'] = '0' * 64
    cases.append(('wrong_selector', bad, 'SELECTOR_MISMATCH'))
    truncated = out / 'raw/truncated_fixture.bin'; truncated.write_bytes(b'1234')
    bad = copy.deepcopy(request); bad['fixed_inputs'] = [dict(path=truncated.as_posix(), size_bytes=8, sha256=identity(truncated)['sha256'])]
    cases.append(('truncated_buffer', bad, 'DEPENDENCY_MISSING'))
    bad = copy.deepcopy(request); bad['output_root'] = (truncated / 'cannot_create').as_posix()
    cases.append(('non_directory_output_parent', bad, 'OUTPUT_INVALID'))
    bad = copy.deepcopy(request); bad['fixed_inputs'] = [dict(path=(out / 'missing.bin').as_posix(), size_bytes=8, sha256='0' * 64)]
    cases.append(('missing_dependency', bad, 'DEPENDENCY_MISSING'))
    bad = copy.deepcopy(request); bad['pairing'] = dict(pairing_kind='same_execution', proof_artifact_ids=[])
    cases.append(('false_pairing', bad, 'PAIRING_UNPROVEN'))
    results = []
    for name, req, expected in cases:
        errors = validate(req)
        results.append(dict(name=name, expected_code=expected, errors=errors,
                            passed=not errors if expected is None else expected in [e['code'] for e in errors]))
    write(out / 'derived/contract_negatives.json', results)
    for path in Path(__file__).parent.glob('*.py'):
        shutil.copyfile(path, out / 'sources' / path.name)
    artifacts = [identity(p) for p in out.rglob('*') if p.is_file()]
    write(out / 'manifest.json', dict(schema_version='1.0', run_id=out.name, operation_status='complete',
        verification_status='not_evaluated', artifacts=artifacts, errors=[], dependencies_complete=False,
        clocks=[], pairing=None, observations=['Static identity only'],
        unknowns=['T01 replay compatibility and exact selectors not yet tested', 'Numeric tolerances remain null'],
        all_historical_matches=all(r['matches_historical'] is not False for r in baseline),
        negative_checks_passed=all(r['passed'] for r in results)))
    print(json.dumps(dict(output=out.as_posix(), source_count=len(baseline), historical_matches=all(r['matches_historical'] is not False for r in baseline), negative_checks=results), ensure_ascii=True))


if __name__ == '__main__':
    main()
