"""Identify the first recorded completed-tick difference in original repeats."""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from material_repeat_reference import run as repeat_run


def run(output):
    passed = repeat_run(output)
    p = output.parent
    a, b = [json.loads((p / n / 'tick_trace.json').read_text())['ticks']
            for n in ['original_a', 'original_b']]
    first = None
    for x, y in zip(a, b):
        for record in [x, y]:
            for name in ['sediment', 'spare_sediment']:
                f = record['fields'][name]
                data = Path(f['path']).read_bytes()
                assert len(data) == f['bytes'] and hashlib.sha256(data).hexdigest() == f['sha256']
        bad = [n for n in x['fields'] if x['fields'][n]['sha256'] != y['fields'][n]['sha256']]
        if bad and first is None:
            first = {'tick': x['tick'], 'fields': bad, 'revision_a': x['revision'], 'revision_b': y['revision'], 'sediment_differences': {}}
            for name in ['sediment', 'spare_sediment']:
                u, v = [np.fromfile(r['fields'][name]['path'], dtype='<f4') for r in [x, y]]
                ids = np.flatnonzero(u.view('u4') != v.view('u4'))
                first['sediment_differences'][name] = {'different_cells': len(ids), 'max_abs': float(np.max(np.abs(u-v))),
                    'first_cells': [{'cell': int(i), 'a_bits': hex(int(u.view('u4')[i])), 'b_bits': hex(int(v.view('u4')[i]))} for i in ids[:8]]}
    result = json.loads((output/'result.json').read_text())
    result['completed_tick_trace'] = {'length_a': len(a), 'length_b': len(b), 'first_difference': first}
    result['scope'] = 'Original completed-tick diagnosis with extra readbacks. No uninstrumented gate or GPU-pass cause proven.'
    result['pass'] = passed and len(a) == len(b) == 900 and first is None
    (output/'result.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
    return result['pass']


if __name__ == '__main__':
    parser = argparse.ArgumentParser(); parser.add_argument('--output', type=Path, required=True); args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    passed = run(args.output); print('MATERIAL_TICK_TRACE', passed)
    raise SystemExit(0 if passed else 1)
