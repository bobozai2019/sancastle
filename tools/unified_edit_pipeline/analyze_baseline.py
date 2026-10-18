"""Summarize raw G0 samples without upgrading exploratory runs to gates."""
import argparse
from collections import defaultdict
import hashlib
import json
import math
from pathlib import Path
import re
import statistics

def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))

def stats(values):
    values = sorted(values)
    if not values:
        return {'n': 0}
    return {'n': len(values), 'p50': statistics.median(values),
            'p95': values[math.ceil(len(values)*0.95)-1],
            'p99': values[math.ceil(len(values)*0.99)-1] if len(values) >= 1000 else None,
            'max': max(values), 'p99_reason': None if len(values) >= 1000 else 'insufficient_samples'}

def summarize(directory):
    manifest_path = directory / 'run-manifest.json'
    manifest = read(manifest_path)
    result = {'manifest': str(manifest_path.resolve()), 'manifest_sha256': digest(manifest_path),
              'pass': manifest['pass'], 'classification': manifest['classification'],
              'sampling': manifest['sampling'], 'cases': {}}
    for run in manifest['runs']:
        path = Path(run['result'])
        if not path.exists():
            result['cases'][run['case']] = {'pass': False, 'reason': 'missing_result'}
            continue
        if digest(path).lower() != run['result_sha256'].lower():
            raise ValueError(f'result identity mismatch: {path}')
        data = read(path)
        groups = defaultdict(list)
        for frame in data['gpu_samples']:
            for span in frame['spans']:
                # Ticket numbers identify instances, not algorithm stages.
                name = re.sub(r'^edit_shape_\d+_(\d+)$', r'edit_shape_stage_\1', span['label'])
                if not name.startswith('edit_shape_'):
                    name = span['group'] or name
                groups[name].append(span['gpu_ns'] / 1e6)
        initial = data['runtime'].get('initial_state', {})
        for field in initial.values():
            if digest(Path(field['path'])) != field['sha256']:
                raise ValueError(f'initial identity mismatch: {field["path"]}')
        result['cases'][run['case']] = {
            'pass': run['pass'] and data['pass'], 'result_sha256': digest(path),
            'check_count': len(data['checks']), 'command_count': len(data['samples']),
            'frame_ms_exploratory_all_frames': stats([v / 1000 for v in data['frame_us']]),
            'wall_ms_including_observer_drain': stats([v['wall_us'] / 1000 for v in data['samples']]),
            'queue_peak_at_frame_observation': max((v['pending'] for v in data['occupancy']), default=None),
            'gpu_stage_ms_per_dispatch': {key: stats(values) for key, values in groups.items()},
            'initial_sha256': {key: v['sha256'] for key, v in initial.items()},
            'final_sha256': data['witnesses']['field_sha256'],
            'limitations': ['No stable-window or cold-window separation.',
                            'No first-visible or collision-application latency.',
                            'Queue is observed per process frame, not every admission.',
                            'Final hashes cover only witness fields, not all double slots/material.']}
    return result

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('directories', nargs='+', type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    runs = [summarize(path) for path in args.directories]
    comparisons = []
    if len(runs) == 2:
        for case in runs[0]['cases'].keys() & runs[1]['cases'].keys():
            a, b = [run['cases'][case] for run in runs]
            comparisons.append({'case': case,
                                'initial_recorded_fields_equal': a.get('initial_sha256') == b.get('initial_sha256'),
                                'final_recorded_fields_equal': a.get('final_sha256') == b.get('final_sha256')})
    with args.output.open('x', encoding='utf-8') as stream:
        json.dump({'role': 'exploratory baseline summary; not G0 PASS',
                   'analyzer_sha256': digest(Path(__file__)), 'runs': runs,
                   'comparisons': comparisons}, stream, ensure_ascii=False, indent=2)
    print(json.dumps({'output': str(args.output), 'runs': len(runs), 'comparisons': comparisons}))

if __name__ == '__main__':
    main()
