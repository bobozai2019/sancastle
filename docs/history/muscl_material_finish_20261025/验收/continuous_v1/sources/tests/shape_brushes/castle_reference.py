"""Float64 inverse-transform and bilinear oracle for exported castle candidates.

Geometry bounds are forward-error allowances, separate from the frozen actual
binary32 volume budget. No total-field percentage tolerance is used.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import numpy as np

U = 2**-24
ROOT = Path(__file__).resolve().parents[2]


def raw(record, field, channels=1, dtype='<f4'):
    entry = record['fields'][field]
    data = Path(entry['path']).read_bytes()
    assert len(data) == entry['bytes'] and hashlib.sha256(data).hexdigest() == entry['sha256']
    return np.frombuffer(data, dtype=dtype).astype(np.float64).reshape(256, 256, channels).squeeze()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--evidence', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    args.evidence = args.evidence or args.output.parent/'castle_gpu/castle_cases.json'
    template = np.fromfile(ROOT/'assets/brushes/castle/four_towers_v1.rgba32f', dtype='<f4').astype(np.float64).reshape(65, 65, 4)
    checks = []
    def check(name, passed, detail=None):
        checks.append({'name': name, 'pass': bool(passed), 'detail': detail})
    axis = (np.arange(256)+.5-128)*.125
    x, z = np.meshgrid(axis, axis)
    for case in json.loads(args.evidence.read_text(encoding='utf-8')):
        name, cmd, receipt = case['name'], case['command'], case['result']
        before, after = case['before'], case['after']
        old, rock, new = raw(before, 'sand'), raw(before, 'rock'), raw(after, 'sand')
        check(name+'_rock', np.array_equal(rock, raw(after, 'rock')))
        if receipt['status'] == 3:
            check(name+'_all_raw_atomic', all(before['fields'][key]['sha256'] == after['fields'][key]['sha256'] for key in before['fields']))
            check(name+'_source_zero', case['source'] == 0)
            continue
        # Evaluate the actual wire angle/scale in double arithmetic.
        angle, scale, height = map(lambda v: float(np.float32(v)), (cmd['yaw_rad'], cmd['scale_xz'], cmd['height_m']))
        co, si = math.cos(angle), math.sin(angle)
        lx, lz = (co*x+si*z)/scale, (-si*x+co*z)/scale
        mask = (np.abs(lx) <= 2) & (np.abs(lz) <= 2)
        # Protected entities remain untouched; immutable rock is part of bed.
        obstacle = raw(before, 'obstacle', dtype='u1')
        mask &= obstacle <= 0
        ux, uz = np.clip((lx+2)*16, 0, 64), np.clip((lz+2)*16, 0, 64)
        ix, iz = np.floor(ux).astype(int), np.floor(uz).astype(int)
        jx, jz = np.minimum(ix+1, 64), np.minimum(iz+1, 64)
        tx, tz = ux-ix, uz-iz
        h = ((template[iz, ix, 0]*(1-tx)+template[iz, jx, 0]*tx)*(1-tz)
             +(template[jz, ix, 0]*(1-tx)+template[jz, jx, 0]*tx)*tz)*height
        bed = old+rock
        base = 0.0
        expected = np.where(mask, np.maximum(old, base+h-rock), old)
        # Max adjacent normalized height difference determines interpolation
        # sensitivity to the fixed binary32 inverse-coordinate error.
        gradient = max(np.abs(np.diff(template[:, :, 0], axis=0)).max(), np.abs(np.diff(template[:, :, 0], axis=1)).max())/.0625
        bound = 8*U*(np.maximum(1, np.abs(old))+np.abs(rock)+height)+32*U*16*gradient*height/scale
        check(name+'_double_geometry', np.all(np.abs(new-expected) <= bound), {'max_error_m': float(np.max(np.abs(new-expected))), 'max_bound_m': float(bound.max())})
        check(name+'_outside_exact', np.array_equal(new[~mask], old[~mask]))
        check(name+'_only_adds', np.all(new >= old))
        check(name+'_higher_sand_rock_preserved', np.array_equal(new[bed >= h], old[bed >= h]))
        check(name+'_protected_obstacle_preserved', np.array_equal(new[obstacle > 0], old[obstacle > 0]))
        if name == 'deep':
            check('deep_bottom_deficit_filled', np.all(new[mask]+rock[mask] >= h[mask]-bound[mask]))
        if name == 'mixed':
            check('mixed_low_and_high_both_present', np.any(mask & (bed > h)) and np.any(mask & (bed < h)))
        check(name+'_published', np.array_equal(new, raw(after, 'published_sand')))
        volume = math.fsum((new-old).ravel())*.015625
        check(name+'_actual_volume', abs(volume-receipt['added_m3']) <= receipt['eps_sand_m3'], {'volume_m3': volume, 'receipt_m3': receipt['added_m3'], 'eps_m3': receipt['eps_sand_m3']})
        check(name+'_source', case['source'] == receipt['added_m3'] and receipt['external_sink_delta_m3'] == 0)
        support = raw(after, 'mold_support_0', 2)
        # The material depth is stored as binary32, including subtraction of
        # the preexisting layer; keep accounting above in float64 instead.
        tagged_layer = (new.astype('<f4')-old.astype('<f4')).astype(np.float64)
        check(name+'_new_layer_tag', np.array_equal(support[:, :, 0], tagged_layer) and np.array_equal(support[:, :, 1], np.where(new>old, new, 0)))
        check(name+'_material_dual', after['fields']['mold_support_0']['sha256'] == after['fields']['mold_support_1']['sha256'])
        for cx in (-1.25, 1.25):
            for cz in (-1.25, 1.25):
                roi = (np.abs(lx-cx) <= .75) & (np.abs(lz-cz) <= .75)
                check(name+f'_tower_{cx}_{cz}', roi.any() and np.max(new[roi]+rock[roi]-base) >= height*.99)
        np.asarray(expected, dtype='<f4').tofile(args.output/(name+'_reference_sand.bin'))
    result = {'pass': all(row['pass'] for row in checks), 'checks': checks}
    (args.output/'result.json').write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
    print(json.dumps({'pass': result['pass'], 'checks': len(checks)}))
    raise SystemExit(0 if result['pass'] else 1)


if __name__ == '__main__':
    main()
