"""Validate two unchanged, normal-path scene captures and report observed noise."""
import json
from pathlib import Path
import statistics
import math

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = ROOT / 'task/muscl_performance_round2/验收'


def read(path):
    return json.loads(path.read_text(encoding='utf-8'))


def metrics(rows):
    values = sorted(r['frame_ms'] for r in rows)
    return {'frames': len(values), 'mean_ms': statistics.mean(values),
            **{f'p{p}_ms': values[math.ceil(len(values)*p/100)-1] for p in (50, 95, 99)},
            'fps': 1000/statistics.mean(values),
            'focused_fraction': statistics.mean(bool(r['focused']) for r in rows),
            'frames_over_50_ms': sum(v > 50 for v in values),
            'max_pending': max(r['pending'] for r in rows), 'max_active': max(r['active'] for r in rows)}


def analyze(name):
    directory = EVIDENCE / name
    manifest = read(directory / 'manifest.json')
    data = read(directory / 'capture.json')
    isolation = read(directory / 'isolation.json')
    metadata = data['metadata']
    failures = []
    for passed, label in (
        (manifest['exit_code'] == 0, 'engine_exit'),
        (manifest['user_unchanged'], 'user_parameters_unchanged'),
        (not manifest['source_drift'], 'no_drift_during_run'),
        (not metadata['source_drift'], 'frozen_configuration_sources'),
        (not metadata['last_error'], 'scene_no_error'),
        (metadata['timing_off'] and not metadata['detailed_gpu'], 'normal_path_no_detailed_diagnostics'),
        (metadata['driver'] == 'd3d12', 'd3d12'),
        (metadata['configuration']['environment']['water_numerics']['solver_id'] == 'muscl_mc_ssprk2_v1', 'muscl'),
        (isolation['startup_sha256'] == manifest['parameter_initial_sha256'], 'parameter_copy_consumed'),
        (str(directory.name) in isolation['parameter_path'], 'isolated_parameter_path'),
    ):
        if not passed:
            failures.append(label)
    # Development harness corrections after freeze are explicit, never treated as simulation changes.
    runtime_differences = [p for p in manifest['baseline_differences'] if not p.startswith('tools/muscl_performance/')]
    if runtime_differences:
        failures.append('baseline_runtime_difference')
    phases = {}
    for interval in metadata['intervals']:
        name = interval['phase']
        rows = [r for r in data['frames'] if r['phase'] == name]
        wall_s = (interval['end_us']-interval['start_us'])/1e6
        sim_s = interval['end_sim_s']-interval['start_sim_s']
        phases[name] = metrics(rows) | {'wall_s': wall_s, 'completed_sim_s': sim_s,
            'simulation_ratio': sim_s/wall_s, 'completed_ticks': interval['end_tick']-interval['start_tick'],
            'gpu_ms_per_sim_s': None, 'cpu_recording_us': None}
    return {'failures': failures, 'phases': phases, 'runtime_differences': runtime_differences,
            'harness_differences': manifest['baseline_differences'],
            'engine': metadata['engine'], 'adapter': metadata['adapter'],
            'window': metadata['window'], 'vsync': metadata['vsync'],
            'camera': metadata['camera'], 'configuration': metadata['configuration']}


if __name__ == '__main__':
    runs = {name: analyze(name) for name in ('baseline_a1_v2', 'baseline_a2')}
    a, b = runs.values()
    pair_failures = []
    for key in ('engine', 'adapter', 'window', 'vsync', 'camera', 'configuration'):
        if a[key] != b[key]:
            pair_failures.append(key + '_mismatch')
    noise = {}
    for phase in a['phases']:
        noise[phase] = {}
        for metric in ('mean_ms', 'p95_ms', 'p99_ms', 'simulation_ratio'):
            x, y = a['phases'][phase][metric], b['phases'][phase][metric]
            noise[phase][metric] = abs(x-y)/statistics.mean((x,y)) if x+y else None
    result = {'runs': runs, 'pair_failures': pair_failures, 'relative_noise': noise,
              'limits': ['Two baseline segments estimate variability, not confidence intervals.',
                         'Detailed CPU/GPU diagnostics are off: missing costs are null.',
                         'No input baseline only; tools, waves, recovery and long run remain unverified.',
                         'Simulation progress uses completed interval endpoints, subject to endpoint quantization.']}
    (EVIDENCE / 'baseline_comparison.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({'pair_failures': pair_failures, 'relative_noise': noise,
                      'runs': {k: {'failures': v['failures'], 'phases': v['phases']} for k,v in runs.items()}}))
    raise SystemExit(bool(pair_failures or any(v['failures'] for v in runs.values())))
