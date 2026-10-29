"""Verify the actual output files and complete raw bytes independently of GPU assertions."""
import argparse
import hashlib
import json
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--evidence', type=Path)
    args = parser.parse_args()
    source = args.evidence or args.output.parent / 'runtime_profile/runtime_profile.json'
    evidence = json.loads(source.read_text(encoding='utf-8'))
    checks = []

    def check(name, value):
        checks.append({'name': name, 'pass': bool(value)})

    expected = {(p, entrance) for p in ['capacity_scale_s_per_m', 'erosion_rate_per_s', 'deposition_rate_per_s'] for entrance in ['awaited', 'requested']}
    check('all_parameter_entrance_pairs', {(r['parameter'], r['entrance']) for r in evidence['observations']} == expected and len(evidence['observations']) == 6)
    for row in evidence['observations']:
        name = row['parameter'] + '_' + row['entrance']
        check(name + '_explicit_error', row['error'] == 'unsupported_checkpoint_erosion_profile')
        check(name + '_no_file', not (source.parent / (name + '.scp')).exists() and not row['file_written'])
    check('late_change_no_file', not (source.parent / 'changed_during_capture.scp').exists())
    check('default_actual_file', (source.parent / 'default_profile.scp').is_file())
    anchor = None
    check('all_snapshots_present', len(evidence['raw_index']) == 9)
    for snapshot in evidence['raw_index']:
        fields = snapshot['fields']
        check('snapshot_all27', len(fields) == 27)
        actual = {}
        for key, item in fields.items():
            data = Path(item['path']).read_bytes()
            check(key + '_indexed_bytes', len(data) == item['bytes'] and hashlib.sha256(data).hexdigest() == item['sha256'])
            actual[key] = data
        if anchor is None:
            anchor = actual
        check('all27_exact_to_anchor', actual == anchor)
    result = {'pass': all(row['pass'] for row in checks), 'checks': checks, 'scope': 'Actual file existence and indexed raw bytes; GPU probe separately checks metadata and capture-time callback.'}
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / 'result.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
    print('RUNTIME_PROFILE_REFERENCE', result['pass'], len(checks))
    raise SystemExit(0 if result['pass'] else 1)


if __name__ == '__main__':
    main()
