import hashlib,json,subprocess
from pathlib import Path
root=Path.cwd(); out=root/'test_output/water_momentum_lab/g0_sources_20261019'
if (out/'workspace_baseline.json').exists():raise SystemExit('Initial baseline already exists; refusing to overwrite')
def identity(p):
 return dict(path=str(p),bytes=p.stat().st_size,sha256=hashlib.sha256(p.read_bytes()).hexdigest()) if p.is_file() else dict(path=str(p),missing=True)
tracked=subprocess.check_output(['git','ls-files','-z']).decode().split('\0')
rows=[identity(root/p) for p in tracked if p and (root/p).is_file()]
(out/'workspace_baseline.json').write_text(json.dumps(rows,indent=2),encoding='utf-8')
paths=['sandcastlegame/test41.rdc','test_output/competitor_edit_compute_20261012_v2/manifest.json','test_output/test1_water_motion/capture_v1/manifest.json','test_output/test1_water_motion/package_v1/manifest.json','docs/competitor/模拟与编辑方案.md','docs/competitor/GPU编辑计算_项目对照.md','docs/competitor/水体运动与回落.md','scripts/simulation/unified_edit/water_response.glsl']
(out/'source_inventory.json').write_text(json.dumps([identity(root/p) for p in paths],ensure_ascii=False,indent=2),encoding='utf-8')
for name in ['edge_flux','drain_scale','update_state']:
 src=root/f'shaders/simulation/shallow_{name}.glsl'; dst=root/f'tests/water_momentum_lab/reference/shallow_{name}.glsl';dst.write_bytes(src.read_bytes())
manifest=[identity(root/f'shaders/simulation/shallow_{n}.glsl') for n in ['edge_flux','drain_scale','update_state']]
(root/'tests/water_momentum_lab/reference/sources.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
