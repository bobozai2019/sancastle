"""Audit raw G0 fields and measure spectra using completed GPU time."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile
import numpy as np


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('directory', type=Path)
    ap.add_argument('--source-root', type=Path, default=Path(__file__).resolve().parents[2])
    ap.add_argument('--measurement', type=Path)
    ap.add_argument('--report-name', default='analysis.json')
    args = ap.parse_args()
    root = args.directory.resolve()
    if Path(args.report_name).name != args.report_name or not args.report_name.endswith('.json'):
        ap.error('report-name must be a JSON filename')
    report_path = root / args.report_name
    if report_path.exists():
        raise FileExistsError(report_path)
    result = json.loads((root / 'diagnosis.json').read_text(encoding='utf-8'))
    measurement = json.loads(args.measurement.read_text(encoding='utf-8')) if args.measurement else result['fixture']
    x = (np.arange(256) + .5 - 128) * .125
    interval = np.abs(x) < 4
    failures, cases = [], {}
    project = args.source_root.resolve()
    archive = root / 'consumed_sources.zip'
    if not archive.exists():
        with zipfile.ZipFile(archive, 'x', zipfile.ZIP_DEFLATED) as bundle:
            for source, expected in result['source_hashes'].items():
                relative = source.removeprefix('res://')
                path = project / relative
                if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
                    failures.append(f'{source}: consumed source unavailable or changed before archival')
                    continue
                bundle.write(path, relative)
    else:
        with zipfile.ZipFile(archive) as bundle:
            for source, expected in result['source_hashes'].items():
                relative = source.removeprefix('res://')
                if relative not in bundle.namelist() or hashlib.sha256(bundle.read(relative)).hexdigest() != expected:
                    failures.append(f'{source}: consumed archive mismatch')
    for case in result['cases']:
        for source, expected in case.get('configuration', {}).get('sources', {}).items():
            if result['source_hashes'].get(source) != expected:
                failures.append(f'{case["id"]}/{source}: source identities differ between cases')
        rows = []
        initial_mass = None
        spec = case.get('fixture', case.get('initial_condition', {}))
        wavelength = spec.get('wavelength', spec.get('wavelength_m', 1.))
        for snap in case['snapshots']:
            fields = {}
            for name, item in snap['fields'].items():
                path = Path(item['path'])
                raw = path.read_bytes()
                if len(raw) != item['bytes'] or hashlib.sha256(raw).hexdigest() != item['sha256']:
                    failures.append(f'{case["id"]}/{snap["label"]}/{name}: identity mismatch')
                if name not in ('decision', 'control'):
                    fields[name] = np.frombuffer(raw, dtype='<f4').astype(float).reshape(256, 256)
            water = fields['water']
            mass = water.sum() * .125**2
            if initial_mass is None:
                initial_mass = mass
            eta = fields['rock'] + fields['sand'] + water
            signal = water[128, interval]
            coefficient = 2 * np.mean((signal - signal.mean()) * np.exp(-2j*np.pi*x[interval]/wavelength))
            points = []
            for px, pz in measurement['far_points_xz_m']:
                ix, iz = int(px/.125 + 128), int(pz/.125 + 128)
                points.append({'h': float(water[iz, ix]), 'eta': float(eta[iz, ix]),
                               'qx': float(fields['momentum_x'][iz, ix]), 'qz': float(fields['momentum_z'][iz, ix])})
            rows.append({'time_s': snap['time_s'], 'tick': snap['tick'],
                         'amplitude_m': float(abs(coefficient)), 'wrapped_phase_rad': float(np.angle(coefficient)),
                         'water_m3': float(mass), 'mass_relative_error': float((mass-initial_mass)/initial_mass),
                         'min_h_m': float(water.min()), 'points': points})
            if not all(np.isfinite(f).all() for f in fields.values()) or water.min() < 0:
                failures.append(f'{case["id"]}/{snap["label"]}: invalid physical fields')
        initial_amplitude = rows[0]['amplitude_m']
        for row in rows:
            row['amplitude_ratio'] = row['amplitude_m'] / initial_amplitude if initial_amplitude > 1e-10 else None
        measured = {'input': spec, 'rows': rows}
        if spec.get('kind') == 'sine':
            # Early dense samples prevent temporal phase aliasing; exclude noise floor.
            phase_rows = [r for r in rows if r['time_s'] <= 1.001 and r['amplitude_ratio'] > .02]
            if len(phase_rows) >= 4:
                phase = np.unwrap([r['wrapped_phase_rad'] for r in phase_rows])
                slope = np.polyfit([r['time_s'] for r in phase_rows], phase, 1)[0]
                measured['phase_speed_early_m_s'] = float(-slope*wavelength/(2*np.pi))
                measured['phase_window_s'] = [phase_rows[0]['time_s'], phase_rows[-1]['time_s']]
            else:
                measured['phase_speed_missing_reason'] = 'Insufficient above-noise early phase samples'
            measured['expected_speed_m_s'] = float(np.sqrt(9.81*spec['depth']))
            measured['amplitude_ratio_2s'] = min(rows, key=lambda r: abs(r['time_s']-2))['amplitude_ratio']
        cases[case['id']] = measured
    if not result['pass'] or result['source_drift']:
        failures.append('Probe failed or consumed sources changed')
    summary = {'schema': 1, 'scope': 'G0 baseline audit, not candidate acceptance',
               'analysis_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
               'source_root': str(project),
               'measurement': measurement,
               'measurement_sha256': hashlib.sha256(args.measurement.read_bytes()).hexdigest() if args.measurement else None,
               'raw_identity_and_finite_pass': not failures, 'failures': failures,
               'cases': cases, 'source_hashes': result['source_hashes'], 'fixture': result['fixture']}
    report_path.write_text(json.dumps(summary, indent=2), encoding='utf-8')
    print(json.dumps({'cases': len(cases), 'failures': failures,
                      'central_depth_waves': {k: v.get('amplitude_ratio_2s') for k, v in cases.items() if 'h0.1_a0.0001_' in k}}, indent=2))
    raise SystemExit(bool(failures))


if __name__ == '__main__':
    main()
