"""Independent native height snapshots versus per-chunk temporal upper bounds."""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('run', type=Path)
    args = parser.parse_args()
    result = json.loads((args.run/'probe.json').read_text(encoding='utf-8-sig'))
    manifest = json.loads((args.run/'run-manifest.json').read_text(encoding='utf-8-sig'))
    obs = result['observations']
    checks = []

    def check(name, passed):
        checks.append(dict(name=name, passed=bool(passed)))

    def raw(item):
        data = Path(item['path']).read_bytes()
        check('raw_identity_'+Path(item['path']).name, len(data) == item['bytes'] and hashlib.sha256(data).hexdigest() == item['sha256'])
        return data

    snapshots = []
    for label in ['initial', 'held', 'corner', 'no_bed']:
        physical = obs[label]['physical']
        sand = np.frombuffer(raw(physical['sand0']), '<f4').astype(np.float64).reshape(256, 256)
        dirty = np.frombuffer(raw(physical['height_dirty']), '<u4')[:256].reshape(64, 4)
        bounds = dirty[:, 3].copy().view('<f4').astype(np.float64)
        check('finite_nonnegative_bounds_'+label, np.all(np.isfinite(bounds)) and np.all(bounds >= 0))
        snapshots.append((label, sand, bounds))
    check('initial_bound_exact_zero', np.all(snapshots[0][2] == 0))
    margins = []
    for before, after in zip(snapshots, snapshots[1:]):
        label = before[0]+'_to_'+after[0]
        check('monotonic_cumulative_bound_'+label, np.all(after[2] >= before[2]))
        for chunk in range(64):
            xs = np.minimum(255, chunk % 8*32+np.arange(33))
            zs = np.minimum(255, chunk // 8*32+np.arange(33))
            actual = float(np.max(np.abs(after[1][np.ix_(zs, xs)]-before[1][np.ix_(zs, xs)])))
            bound = float(after[2][chunk]-before[2][chunk])
            check(f'full_33x33_temporal_bound_{label}_{chunk}', bound >= actual)
            margins.append(bound-actual)
    changed = set(np.flatnonzero(snapshots[2][2] > 0).tolist())
    check('one_corner_updates_its_four_shared_halos', changed == {27, 28, 35, 36})
    check('acknowledgement_preserves_bound', np.array_equal(snapshots[1][2], snapshots[2][2]))
    check('material_nochange_rejection_leave_bound_unchanged', np.array_equal(snapshots[2][2], snapshots[3][2]))
    for label, _, exact in snapshots:
        if label == 'held':
            continue
        applied = obs[label]['surface']['change_bounds']
        for chunk in range(64):
            value = float(applied[str(chunk)])
            ulp = float(np.nextafter(np.float32(exact[chunk]), np.float32(np.inf)))-exact[chunk]
            check(f'packed_applied_upper_bound_{label}_{chunk}', 0 <= value-exact[chunk] <= 63*ulp)
    check('functional_and_frozen_sources', result['pass'] and manifest['pass'] and not manifest['drift'])
    output = args.run/'independent_height_bounds.json'
    if output.exists():
        raise SystemExit('Do not overwrite evidence')
    source = Path(__file__).read_bytes()
    (args.run/'independent_height_bounds_verifier.py').write_bytes(source)
    report = dict(passed=all(c['passed'] for c in checks), checks=checks,
                  minimum_bound_minus_actual_m=min(margins),
                  verifier_sha256=hashlib.sha256(source).hexdigest(),
                  scope='Independent raw sand and dirty-buffer bytes, complete shared 33x33 collision vertices; no Godot decoder or pointwise slope approximation.')
    output.write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8')
    print('HEIGHT_CHANGE_BOUNDS', report['passed'], len(checks), report['minimum_bound_minus_actual_m'])
    raise SystemExit(0 if report['passed'] else 1)


if __name__ == '__main__':
    main()
