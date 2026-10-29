"""Freeze an evaluated D07 candidate and exact observer sources, without accepting G4."""
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
    requirements = [
        ('calibration', 't05_d07_evaluation_20261025_v3', 'evaluation.json'),
        ('scalar_abi', 't05_scalar_bridge_helper_20261025_v6', 'manifest.json'),
        ('overflow_negative', 't05_scalar_bridge_overflow_20261025_v1', 'manifest.json'),
        ('snapshot_schema', 't05_snapshot_validation_20261025_v3', 'validation.json'),
        ('native_gpu_consumption', 't05_consumption_20261025_v4', 'consumption.json'),
    ]
    errors, evidence = [], []
    for label, run, name in requirements:
        path = base / run / name
        data = json.loads(path.read_text(encoding='utf-8'))
        if data.get('verification_status') != 'passed':
            errors.append(label + ':not_passed')
        manifest = json.loads((base / run / 'manifest.json').read_text(encoding='utf-8'))
        for item in manifest.get('artifacts', []):
            actual = identity(item['path'])
            if actual['sha256'] != item['sha256'] or actual['size_bytes'] != item['size_bytes']:
                errors.append(label + ':artifact_identity')
        evidence.append(dict(role=label, **identity(path)))
    criteria_path = root / 'requests/d07_candidate_v2.json'
    criteria = json.loads(criteria_path.read_text())
    evaluation = json.loads((base / requirements[0][1] / requirements[0][2]).read_text())
    if evaluation['criteria']['sha256'] != identity(criteria_path)['sha256']:
        errors.append('CRITERIA_CHANGED')
    capture = base / 't05_native_scalar_capture_20261025_v1'
    mode = json.loads((capture / 'mode.json').read_text())
    if not mode.get('native_scalars') or mode.get('clock_sample_every') != 1:
        errors.append('CAPTURE_CONFIG_MISMATCH')
    names = ['water_observer.js', 'presentation_observer.js', 'isolation_guard.js',
             'scalar_bridge.js', 'scalar_bridge.c']
    sources = []
    dest = out / 'sources'
    dest.mkdir()
    for source in [root / 'tools/runtime_startup.py', Path(__file__),
                   *[root / 'tools/runtime' / n for n in names]]:
        original = identity(source)
        # The actual game run must have consumed the same instrumented source.
        saved = capture / 'sources' / source.name
        if source.name in names + ['runtime_startup.py'] and (not saved.exists() or identity(saved)['sha256'] != original['sha256']):
            errors.append('SOURCE_DIFFERS_FROM_CAPTURE:' + source.name)
        calibrated = base / 't05_d07_acceptance_20261025_v3/sources' / source.name
        if source.name in names + ['runtime_startup.py'] and (not calibrated.exists() or identity(calibrated)['sha256'] != original['sha256']):
            errors.append('SOURCE_DIFFERS_FROM_CALIBRATION:' + source.name)
        shutil.copy2(source, dest / source.name)
        sources.append(original)
    shutil.copy2(criteria_path, out / 'criteria.json')
    result = dict(operation_status='complete', verification_status='passed' if not errors else 'failed',
                  decision_id='D07', decision_status='accepted' if not errors else 'not_accepted',
                  created_at=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                  scope='Observer configuration/window only. Calibration hook gaps and GPU capture stalls are excluded from continuous formal trajectories. Not G4 acceptance.',
                  criteria=identity(criteria_path), configuration=criteria['recording'],
                  evidence=evidence, sources=sources, errors=errors,
                  residual_unknowns=['CPU origin of GPU light_factor', 'unobserved states and reset scheduling',
                                     'uninstrumented wall-clock cadence', 'controllable-input formal trajectory'])
    (out / 'decision.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
    manifest = dict(operation_status='complete', verification_status=result['verification_status'],
                    errors=errors, artifacts=[identity(p) for p in out.rglob('*') if p.is_file()])
    (out / 'manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    print(json.dumps(dict(status=result['decision_status'], errors=errors)))
    raise SystemExit(bool(errors))


if __name__ == '__main__':
    main()
