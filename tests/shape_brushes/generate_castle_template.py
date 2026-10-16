"""Generate the frozen G1A four-tower height-field asset deterministically."""
import hashlib
import json
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / 'assets/brushes/castle'


def height(x, z):
    h = .08
    # Four 1.5 m square towers with four .5 m corner merlons each.
    for cx in (-1.25, 1.25):
        for cz in (-1.25, 1.25):
            dx, dz = abs(x-cx), abs(z-cz)
            if dx <= .75 and dz <= .75:
                h = max(h, .7 if dx >= .25 and dz >= .25 else .55)
    # .5 m walls join the towers; alternating .5 m merlons and gaps.
    for across, along in ((x, z), (z, x)):
        if 1.0 <= abs(across) <= 1.5 and abs(along) <= .5:
            h = max(h, .7 if abs(along) >= .25 else .4)
    return h


def main():
    DEST.mkdir(parents=True, exist_ok=True)
    data = b''.join(struct.pack('<4f', height(x/16-2, z/16-2)/.7, 1., 1., 0.)
                    for z in range(65) for x in range(65))
    target = DEST / 'four_towers_v1.rgba32f'
    target.write_bytes(data)
    index = {'template_id': 'four_towers_v1', 'size': [65, 65],
             'spacing_m': .0625, 'local_bounds_m': [-2, 2],
             'channels': ['normalized_height', 'foundation_mask', 'shape_mask', 'reserved'],
             'interpolation': 'height_bilinear_masks_nearest',
             'heights_m': {'base': .08, 'wall': .4, 'tower': .55, 'merlon': .7},
             'geometry_m': {'tower_centers': [-1.25, 1.25], 'tower_width': 1.5,
                            'wall_width': .5, 'merlon_width': .5, 'gap_width': .5},
             'default_physical_grid_volume_m3': sum(height((x+.5-16)*.125, (z+.5-16)*.125)
                                                    for z in range(32) for x in range(32))*.125**2,
             'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest(),
             'generator': 'tests/shape_brushes/generate_castle_template.py',
             'generator_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
    (DEST / 'four_towers_v1.json').write_text(json.dumps(index, indent=2)+'\n', encoding='utf-8')
    print(json.dumps({'bytes': len(data), 'sha256': index['sha256']}))


if __name__ == '__main__':
    main()
