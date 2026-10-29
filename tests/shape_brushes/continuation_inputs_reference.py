"""Compare complete per-substep parameter records while keeping state strict failure separate."""
import argparse
import json
import struct
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    data = json.loads((args.output.parent / 'continuation_inputs/continuation_inputs.json').read_text(encoding='utf-8'))
    rows = data['rows']
    checks = []

    def check(name, value):
        checks.append({'name': name, 'pass': bool(value)})

    direct = {r['tick']: r for r in rows if r['branch'] == 0 and r['tick'] > 10}
    restored = {r['tick']: r for r in rows if r['branch'] == 1}
    check('complete_branches_no_duplicate_ticks', len(rows) == 610 and len(direct) == 300 and len(restored) == 300 and set(direct) == set(range(11, 311)) == set(restored))
    for row in rows:
        count = row['substeps']
        check('all_substeps_observed_without_16_row_truncation', count > 0 and all(len(row[k]) == count for k in ['coupled', 'erosion_pushes', 'slope_pushes']))
        for coupled, erosion, slope in zip(row['coupled'], row['erosion_pushes'], row['slope_pushes']):
            cpu = struct.unpack('<3d', bytes.fromhex(coupled['float64_hex']))
            erosion_bytes = bytes.fromhex(erosion['bytes_hex'])
            slope_bytes = bytes.fromhex(slope['bytes_hex'])
            check('actual_push_sizes_and_shared_delta', len(erosion_bytes) == 32 and len(slope_bytes) == 48 and erosion_bytes[:4] == slope_bytes[:4] == struct.pack('<f', cpu[0]))
            check('actual_erosion_release_coefficients', erosion_bytes[8:24] == struct.pack('<4f', .08, .35, .45, .001))
            check('same_dispatch_revision', coupled['revision'] == erosion['revision'] == slope['revision'] and coupled['index'] == erosion['index'])
    differences = []
    for tick in sorted(set(direct) & set(restored)):
        a = {k: v for k, v in direct[tick].items() if k != 'branch'}
        b = {k: v for k, v in restored[tick].items() if k != 'branch'}
        if a != b:
            differences.append({'tick': tick, 'keys': [k for k in a if a[k] != b[k]]})
    check('all_observed_parameters_exact_across_restore', not differences)
    result = {'pass': all(r['pass'] for r in checks), 'checks': checks, 'parameter_differences': differences, 'scope': data['scope'], 'state_gate': 'Use original continuation main_smoke.json and raw fields separately; this result only verifies parameter coverage and identity.'}
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / 'result.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
    print('CONTINUATION_INPUTS_REFERENCE', result['pass'], len(checks), differences[:3])
    raise SystemExit(0 if result['pass'] else 1)


if __name__ == '__main__':
    main()
