"""Bake captured geometry into main's existing scalar-field contract without stretching."""
import hashlib
import json
from pathlib import Path
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'test_output/test1_geometry_20261018/replay_v3'
OUT = ROOT / 'assets/test1_geometry'
OUT.mkdir(parents=True, exist_ok=True)
PROFILE = OUT / 'water_cycle.json'
profile = json.loads(PROFILE.read_text(encoding='utf-8'))
assert profile['schema_version'] == 1 and profile['initial_water'] == 'calm_zero_momentum'
assert .5 <= profile['rest_level_m'] <= 1.1
assert 0 < profile['runup_height_m'] <= .6 and 12 <= profile['period_s'] <= 60

def identity(path):
    return {'path': str(path), 'bytes': path.stat().st_size,
            'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}

manifest = json.loads((SOURCE / 'manifest.json').read_text())
assert manifest['pass']
inputs = []
for name in ('e5006_vs_buffer0.bin', 'e5006_vs_buffer1.bin'):
    path = SOURCE / name
    row = next(x for x in manifest['exports'] if Path(x['path']).name == name)
    assert identity(path)['sha256'] == row['sha256']
    inputs.append(dict(identity(path), selector=row['selector']))
scale = np.array([0x3521999b], dtype='<u4').view('<f4')[0]
g = np.fromfile(SOURCE / 'e5006_vs_buffer0.bin', '<u4').reshape(512, 1024, 4)
height = (((g[..., 2] >> 12) | (g[..., 3] << 20)) & 0xffffff).astype('f4') * scale
w = np.fromfile(SOURCE / 'e5006_vs_buffer1.bin', '<u4').reshape(256, 512, 4)
floor = (((w[..., 2] >> 24) | (w[..., 3] << 8)) & 0xffffff).astype('f4') * scale
depth = np.maximum((w[..., 2] & 0xffffff).astype('f4') * scale - np.float32(.05), 0)
vx = (((w[..., 0] >> 16) | (w[..., 1] << 16)) & 0xffffff).astype('f4') * np.float32(8 / 16777215) - 4
vz = (w[..., 1] >> 8).astype('f4') * np.float32(8 / 16777215) - 4
xx, zz = np.meshgrid((np.arange(256) + .5) * .125 - 16, (np.arange(256) + .5) * .125 - 16)

def sample(field):
    rows, cols = field.shape
    px = np.clip(((-xx + 15) / 30 * cols - .5), 0, cols-1)
    pz = np.clip(((zz + 7.5) / 15 * rows - .5), 0, rows-1)
    ix, iz = np.floor(px).astype(int), np.floor(pz).astype(int)
    fx, fz = px-ix, pz-iz
    jx, jz = np.minimum(ix+1, cols-1), np.minimum(iz+1, rows-1)
    return ((field[iz, ix]*(1-fx)+field[iz, jx]*fx)*(1-fz) +
            (field[jz, ix]*(1-fx)+field[jz, jx]*fx)*fz).astype('<f4')

bed = sample(height)
# A captured strong-wave snapshot is not a calm starting water level.
# Initialize a lake-at-rest at the configured low sea level, then let the
# existing solver transport each boundary pulse inland and back out.
h = np.maximum(profile['rest_level_m'] - bed, 0).astype('<f4')
blocked = abs(zz) >= 7.5
h[blocked] = 0
qx, qz = np.zeros_like(h), np.zeros_like(h)
state = np.stack([bed, h, qx, qz, blocked.astype('f4')], axis=-1).astype('<f4')
assert np.isfinite(state).all() and state[..., :2].min() >= 0
state.tofile(OUT / 'initial_state.f32')
height.astype('<f4').tofile(OUT / 'source_sand_1024x512.f32')
visible = (abs(xx) < 15) & ~blocked
report = {
    'version': 2, 'capture': manifest['source'], 'inputs': inputs,
    'tool': identity(Path(__file__)), 'numpy': np.__version__,
    'fields': ['sand_height', 'water_depth', 'momentum_x', 'momentum_z', 'obstacle'],
    'grid_size': 256, 'cell_size_m': .125, 'visible_extent_xz': [30, 15],
    'source_to_godot': '(-x, y, z); keep absolute captured surface Y',
    'rock_base': 0, 'sand_thickness': 'resampled captured height above project rock Y=0; Godot adaptation',
    'padding': 'Z outside +/-7.5 is a solid dry mask; X continues nearest edge to the existing +/-16 simulation boundary. Visible mesh and picking stop at +/-15.',
    'water': 'h=max(configured rest_level_m-bilinear(captured sand),0); zero initial momentum; dry Z padding',
    'water_cycle_profile': identity(PROFILE),
    'source_height_range': [float(height.min()), float(height.max())],
    'visible_height_range': [float(bed[visible].min()), float(bed[visible].max())],
    'visible_cells': int(visible.sum()), 'artifacts': []}
for name in ('initial_state.f32', 'source_sand_1024x512.f32'):
    report['artifacts'].append(identity(OUT / name))
(OUT / 'initial_state.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
print(json.dumps({'visible_cells': report['visible_cells'], 'height_range': report['visible_height_range'], 'state_sha256': report['artifacts'][0]['sha256']}))
