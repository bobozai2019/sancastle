"""Visible 0/3-body AA noise gate followed by three ordered AB/BA/AB pairs."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import statistics
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
ORDER = [('aa_01', 'zero'), ('aa_02', 'zero'),
         ('pair1_a', 'zero'), ('pair1_b', 'three'),
         ('pair2_b', 'three'), ('pair2_a', 'zero'),
         ('pair3_a', 'zero'), ('pair3_b', 'three')]


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def quantile(values, fraction):
    values = sorted(values)
    return values[max(0, math.ceil(len(values)*fraction)-1)]


def summarize(folder):
    result = read(folder/'probe.json')
    manifest = read(folder/'run-manifest.json')
    obs = result['observations']
    measure = obs['measure']
    frames = measure['frames']
    times = [f['wall_frame_ms'] for f in frames]
    return dict(passed=result['pass'] and manifest['pass'], frames=len(frames),
                p50_ms=statistics.median(times), p95_ms=quantile(times, .95),
                p99_ms=quantile(times, .99) if len(times) >= 1000 else None,
                physics_cpu_p50_ms=statistics.median(f['physics_cpu_ms'] for f in frames),
                physics_cpu_p95_ms=quantile([f['physics_cpu_ms'] for f in frames], .95),
                sample_age_p95_s=quantile([f['sample_age_s'] for f in frames], .95),
                max_sample_age_s=max(f['sample_age_s'] for f in frames),
                throughput=measure['throughput_sim_s_per_wall_s'],
                environment=obs['environment'], sources=manifest['sources'],
                engine_sha256=manifest['engine_sha256'],
                recipe=measure['recipe'], manifest_sha256=hashlib.sha256((folder/'run-manifest.json').read_bytes()).hexdigest())


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    rows = {}
    for label, case in ORDER:
        print('COST_MATRIX_BEGIN', label, case, flush=True)
        command = [sys.executable, str(ROOT/'tools/floating_props/run_probe.py'),
                   '--output', str(output/label), '--script', 'tests/floating_props/main_cost_probe.gd',
                   '--case', case, '--timeout', '150', '--quit-after', '20000']
        completed = subprocess.run(command, cwd=ROOT)
        if completed.returncode:
            (output/'incomplete.json').write_text(json.dumps(dict(failed_run=label, command=command, returncode=completed.returncode), indent=2)+'\n', encoding='utf-8')
            raise SystemExit(completed.returncode)
        rows[label] = summarize(output/label)
        if label == 'aa_02':
            noise = abs(rows['aa_01']['p95_ms']-rows['aa_02']['p95_ms'])
            (output/'noise_gate.json').write_text(json.dumps(dict(p95_range_ms=noise,
                aa_p95_ms=[rows['aa_01']['p95_ms'], rows['aa_02']['p95_ms']],
                policy='Observed AA P95 range frozen before any AB run; acceptance=max(2ms,10% of paired A,AA range). Two repeats do not establish universal hardware variance.'), indent=2)+'\n', encoding='utf-8')
        print('COST_MATRIX_RESULT', label, rows[label]['p95_ms'], rows[label]['throughput'], flush=True)
    noise = read(output/'noise_gate.json')['p95_range_ms']
    pairs = []
    for index in range(1, 4):
        a, b = rows[f'pair{index}_a'], rows[f'pair{index}_b']
        limit = max(2.0, a['p95_ms']*.1, noise)
        delta = b['p95_ms']-a['p95_ms']
        throughput_ratio = b['throughput']/a['throughput']
        pairs.append(dict(pair=index, a_p95_ms=a['p95_ms'], b_p95_ms=b['p95_ms'],
                          delta_p95_ms=delta, allowed_delta_ms=limit,
                          throughput_ratio=throughput_ratio,
                          passed=delta <= limit and throughput_ratio >= .90))
    first = rows['aa_01']
    sources_equal = all(row['sources'] == first['sources'] and row['engine_sha256'] == first['engine_sha256'] for row in rows.values())
    env_keys = ['gpu', 'driver', 'cpu', 'vsync', 'window_size', 'output_size', 'display', 'warm_wall_s', 'measure_wall_s']
    environment_equal = all(all(row['environment'][key] == first['environment'][key] for key in env_keys) for row in rows.values())
    passed = sources_equal and environment_equal and all(row['passed'] for row in rows.values()) and all(pair['passed'] for pair in pairs)
    result = dict(passed=passed, sources_equal=sources_equal, environment_equal=environment_equal,
                  noise_gate_ms=noise, pairs=pairs,
                  runs={key: {field: value for field, value in row.items() if field != 'sources'} for key, row in rows.items()},
                  sources=first['sources'], scope='Visible full-main product frame cost, current hardware and open background workload; no stage-specific GPU attribution or general 60FPS claim.')
    (output/'comparison.json').write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
    print('COST_MATRIX_PASS', passed, json.dumps(pairs), flush=True)
    raise SystemExit(0 if passed else 1)


if __name__ == '__main__':
    main()
