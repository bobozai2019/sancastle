"""Bake the preserved capture height field plus authored tidal channels offline."""
import hashlib
import json
from pathlib import Path
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/test1_geometry'
def identity(path):
    return dict(path=str(path), bytes=path.stat().st_size, sha256=hashlib.sha256(path.read_bytes()).hexdigest())
source = OUT / 'source_sand_1024x512.f32'
assert identity(source)['sha256'] == '954e9ce7fa17992cc7c6eb632349d8fae94e7c72eb05f622a2466f848efaeb51'
height = np.fromfile(source, '<f4').reshape(512, 1024)
profile = json.loads((OUT / 'water_cycle.json').read_text())
channels = json.loads((OUT / 'channels.json').read_text())
assert profile['initial_water'] == 'calm_zero_momentum' and channels['version'] == 1
xx, zz = np.meshgrid((np.arange(256) + .5) * .125 - 16, (np.arange(256) + .5) * .125 - 16)
px = np.clip((-xx + 15) / 30 * 1024 - .5, 0, 1023)
pz = np.clip((zz + 7.5) / 15 * 512 - .5, 0, 511)
ix, iz = np.floor(px).astype(int), np.floor(pz).astype(int)
fx, fz = px-ix, pz-iz
jx, jz = np.minimum(ix+1,1023), np.minimum(iz+1,511)
original = ((height[iz,ix]*(1-fx)+height[iz,jx]*fx)*(1-fz)+(height[jz,ix]*(1-fx)+height[jz,jx]*fx)*fz).astype('<f4')
bed = original.copy()
visible = (abs(xx) < 15) & (abs(zz) < 7.5)
for channel in channels['channels']:
    points = np.asarray(channel['points'], dtype=float)
    padded = np.concatenate([points[:1], points, points[-1:]])
    curve = []
    for i in range(len(points)-1):
        a,b,c,d = padded[i:i+4]
        for t in np.linspace(0,1,24,endpoint=False):
            curve.append(.5*((2*b)+(-a+c)*t+(2*a-5*b+4*c-d)*t*t+(-a+3*b-3*c+d)*t*t*t))
    curve = np.asarray(curve + [points[-1]])
    distances = np.full(xx.shape, np.inf)
    progress = np.zeros_like(xx)
    lengths = np.linalg.norm(np.diff(curve,axis=0),axis=1)
    cumulative = np.concatenate([[0],np.cumsum(lengths)])
    for i,(a,b) in enumerate(zip(curve[:-1],curve[1:])):
        delta=b-a
        t=np.clip(((xx-a[0])*delta[0]+(zz-a[1])*delta[1])/np.dot(delta,delta),0,1)
        dist=np.hypot(xx-a[0]-t*delta[0],zz-a[1]-t*delta[1])
        nearer=dist<distances
        progress[nearer]=(cumulative[i]+t[nearer]*lengths[i])/cumulative[-1]
        distances=np.minimum(distances,dist)
    width=np.interp(progress,[0,1],channel['half_width'])
    target=np.interp(progress,[0,1],channel['bed_y'])
    bank=np.clip((distances-width)/channel['bank_width'],0,1)
    weight=1-bank*bank*(3-2*bank)
    candidate=original-(np.maximum(original-target,0)*weight).astype('f4')
    bed[visible]=np.minimum(bed[visible],candidate[visible])
h=np.maximum(profile['rest_level_m']-bed,0).astype('<f4')
blocked=abs(zz)>=7.5
h[blocked]=0
state=np.stack([bed,h,np.zeros_like(h),np.zeros_like(h),blocked.astype('f4')],axis=-1).astype('<f4')
assert np.isfinite(state).all() and state[..., :2].min()>=0
assert np.array_equal(bed[~visible],original[~visible])
state.tofile(OUT/'initial_state.f32')
report=dict(version=3, capture=dict(path=str(ROOT/'rdc/test1.rdc'),bytes=225224034,sha256='761aa980c2426f75a1fa7364bf6d2655ff4dd20ea76566e630ee5b53ea0ec5b2'),
    inputs=[identity(source),identity(OUT/'channels.json')],tool=identity(Path(__file__)),numpy=np.__version__,
    fields=['sand_height','water_depth','momentum_x','momentum_z','obstacle'],grid_size=256,cell_size_m=.125,
    visible_extent_xz=[30,15],source_to_godot='(-x,y,z); captured base plus authored channels',rock_base=0,
    adaptation='Three curved inlets and one branch, smooth banks; only lower the initial bed. Initial inventories derive from this terrain, not runtime editing.',
    water='h=max(rest_level_m-bed,0), zero momentum; dry blocked Z padding',water_cycle_profile=identity(OUT/'water_cycle.json'),
    visible_height_range=[float(bed[visible].min()),float(bed[visible].max())],visible_cells=int(visible.sum()),
    changed_cells=int(np.count_nonzero(bed!=original)),removed_initial_sand_m3=float(np.sum(original-bed,dtype=float)*.125**2),
    added_initial_water_m3=float(np.sum(h-np.where(blocked,0,np.maximum(profile['rest_level_m']-original,0)),dtype=float)*.125**2),
    artifacts=[identity(OUT/'initial_state.f32')])
(OUT/'initial_state.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print(json.dumps({k:report[k] for k in ['changed_cells','removed_initial_sand_m3','added_initial_water_m3']}))
