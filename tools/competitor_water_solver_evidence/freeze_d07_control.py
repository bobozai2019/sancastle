"""Freeze the separately calibrated public Time control experiment (not original UI)."""
import argparse
import datetime
import json
import shutil
from pathlib import Path
from evidence_contract import identity


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--output', required=True, type=Path)
    args = ap.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    root = Path(__file__).resolve().parents[1]
    base = root.parents[1] / 'docs/competitor/evidence/water_solver_reconstruction'
    evidence_specs = [
        ('scale1_calibration', 't05_control_calibration_eval_scale1_20261025_v1', 'evaluation.json'),
        ('scalehalf_calibration', 't05_control_calibration_eval_scalehalf_20261025_v1', 'evaluation.json'),
        ('scale1_sidecar', 't05_control_sidecar_audit_scale1_20261025_v1', 'control_audit.json'),
        ('scalehalf_sidecar', 't05_control_sidecar_audit_scalehalf_20261025_v1', 'control_audit.json'),
        ('capture_sidecar', 't05_control_capture_audit_20261025_v1', 'control_audit.json'),
        ('capture_gpu', 't05_consumption_20261025_v5', 'consumption.json'),
        ('snapshot_encoding', 't05_snapshot_validation_20261025_v3', 'validation.json'),
        ('native_scalar_abi', 't05_scalar_bridge_helper_20261025_v6', 'manifest.json'),
        ('overflow_negative', 't05_scalar_bridge_overflow_20261025_v1', 'manifest.json'),
    ]
    errors, evidence = [], []
    for role, run, name in evidence_specs:
        folder = base / run
        data = json.loads((folder / name).read_text())
        if data.get('verification_status') != 'passed':
            errors.append(role + ':NOT_PASSED')
        manifest = json.loads((folder / 'manifest.json').read_text())
        for item in manifest['artifacts']:
            actual = identity(item['path'])
            if actual['sha256'] != item['sha256'] or actual['size_bytes'] != item['size_bytes']:
                errors.append(role + ':IDENTITY_CHANGED')
        evidence.append(dict(role=role, **identity(folder / name)))
    criteria = []
    for scale, run in [('scale1', evidence_specs[0][1]), ('scalehalf', evidence_specs[1][1])]:
        path = root / ('requests/d07_control_candidate_' + scale + '_v1.json')
        data = json.loads(path.read_text())
        evaluation = json.loads((base / run / 'evaluation.json').read_text())
        if evaluation['criteria']['sha256'] != identity(path)['sha256']:
            errors.append('CRITERIA_CHANGED:' + scale)
        criteria.append(identity(path))
        shutil.copyfile(path, out / ('criteria_' + scale + '.json'))
    recording = json.loads((out / 'criteria_scale1.json').read_text())['recording']
    full_half = json.loads((out / 'criteria_scalehalf.json').read_text())
    if full_half['recording'] != recording:
        errors.append('RECORDING_CRITERIA_DIFFER')
    names = ['water_observer.js', 'presentation_observer.js', 'isolation_guard.js',
             'scalar_bridge.js', 'scalar_bridge.c', 'clock_control.js']
    sources = []
    dest = out / 'sources'
    dest.mkdir()
    for name in ['runtime_control_startup.py', *names]:
        source = root / 'tools' / (name if name.endswith('.py') else 'runtime/' + name)
        saved_name = 'runtime_startup.py' if name == 'runtime_control_startup.py' else name
        expected = identity(source)
        for run in ['t05_control_calibration_scale1_20261025_v1', 't05_control_calibration_scalehalf_20261025_v1', 't05_control_capture_20261025_v1']:
            saved = base / run / 'sources' / saved_name
            if not saved.exists() or identity(saved)['sha256'] != expected['sha256']:
                errors.append('SOURCE_CHANGED:' + run + ':' + name)
        shutil.copyfile(source, dest / name)
        sources.append(dict(**expected, saved_name=saved_name))
    gpu = json.loads((base / 't05_consumption_20261025_v5/consumption.json').read_text())
    capture_raw = json.loads((base / 't05_control_capture_20261025_v1/logs/events.json').read_text())
    samples = [e for r in capture_raw if r.get('payload', {}).get('kind') == 'water_trace' for e in r['payload']['events'] if e['kind'] == 'engine_clock_sample' and e['call_id'] == gpu['cpu_source_call_id']]
    if len(samples) != 1 or samples[0]['values']['get_timeScale'] != .5:
        errors.append('CAPTURE_NOT_AT_HALF_SCALE')
    formal_request = root / 'requests/t05_control_formal_v1.json'
    request = json.loads(formal_request.read_text())
    if request['actions'] != recording['required_control_actions'] or not request['hold_scale']:
        errors.append('FORMAL_CONTROL_CONFIG_MISMATCH')
    shutil.copyfile(formal_request, out / 'formal_control_request.json')
    shutil.copyfile(Path(__file__), dest / Path(__file__).name)
    result = dict(operation_status='complete', verification_status='passed' if not errors else 'failed',
                  decision_id='D07-control-v1', decision_status='accepted' if not errors else 'not_accepted',
                  created_at=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                  scope='Explicit held public Unity Time 1/.5/1 intervention only, under separately calibrated observer. Not original game UI, wave generator, pause or unmodified clock behavior. G4 requires formal trajectory and mapping.',
                  criteria=criteria, configuration=recording, sources=sources,
                  evidence=evidence, formal_control_request=identity(formal_request),
                  captured_source_native_clock=samples, errors=errors)
    (out / 'decision.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
    (out / 'manifest.json').write_text(json.dumps(dict(operation_status='complete', verification_status=result['verification_status'], errors=errors, artifacts=[identity(p) for p in out.rglob('*') if p.is_file()]), indent=2), encoding='utf-8')
    print(json.dumps(dict(status=result['decision_status'], errors=errors)))
    raise SystemExit(bool(errors))


if __name__ == '__main__':
    main()
