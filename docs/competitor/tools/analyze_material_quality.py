"""Summarize recorded single-variable probes; pixel differences are not quality scores."""
from pathlib import Path
import hashlib
import json
import zipfile
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'docs/competitor/evidence/material_quality_20261023'

def identity(p):
    return dict(path=str(p.relative_to(ROOT)).replace('\\', '/'), bytes=p.stat().st_size,
                sha256=hashlib.sha256(p.read_bytes()).hexdigest())

result = dict(scope='Paused tick 0, default startup settings; per-image differences only within each run. No cross-game similarity or performance claim.', runs={})
for name in ('main', 'main_v2', 'geometry', 'layers', 'layers_v2', 'layers_v3'):
    folder = OUT / name
    probe = json.loads((folder / 'probe.json').read_text(encoding='utf-8-sig'))
    base = np.asarray(Image.open(folder / 'baseline.png')).astype(np.int16)
    rows = {}
    for p in sorted(folder.glob('*.png')):
        d = np.abs(np.asarray(Image.open(p)).astype(np.int16) - base)
        changed = np.any(d != 0, axis=2)
        ys, xs = np.where(changed)
        rows[p.stem] = dict(**identity(p), changed_pixels=int(changed.sum()), mean_abs_channel_8bit=float(d.mean()),
                            changed_bbox=[int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1] if len(xs) else None,
                            foreground_sand_crop_changed_pixels=int(changed[490:710, 430:930].sum()))
    drift = []
    for path, digest in probe['observations']['sources'].items():
        p = ROOT / path.removeprefix('res://')
        if not p.is_file() or hashlib.sha256(p.read_bytes()).hexdigest() != digest:
            drift.append(path)
    result['runs'][name] = dict(probe=identity(folder / 'probe.json'), pass_as_recorded=probe['pass'],
                               failed_checks=[x for x in probe['checks'] if not x['pass']],
                               source_drift=drift, images=rows,
                               probe_script=identity(folder / 'probe_material_quality.gd'),
                               command=['D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe',
                                        '--path', str(ROOT), '--rendering-driver', 'd3d12', '--script',
                                        'res://docs/competitor/tools/probe_material_quality.gd', '--log-file',
                                        str(folder / 'godot.log'), '--', '--output=' + str(folder),
                                        '--scene=' + ('test1_geometry' if name == 'geometry' else 'main'),
                                        '--ignore-parameter-config'] + (['--layers'] if name.startswith('layers') else []))

# Preserve the implementation actually inspected; production files are not edited.
sources = ['project.godot', 'assets/parameters/catalog.json', 'scripts/parameters/parameter_schema.gd',
           'assets/water_material_natural_candidate/async_rdc_bed.gdshader',
           'assets/water_material_natural_candidate/async_rdc_water.gdshader',
           'scenes/unified_edit/presentation/main.tscn', 'scenes/unified_edit/presentation/test1_geometry.tscn',
           'docs/competitor/tools/probe_material_quality.gd', 'docs/competitor/tools/export_material_quality.py',
           'docs/competitor/tools/analyze_material_quality.py']
result['sources'] = [identity(ROOT / p) for p in sources if (ROOT / p).is_file()]
with zipfile.ZipFile(OUT / 'inspected_sources.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
    for row in result['sources']:
        archive.write(ROOT / row['path'], row['path'])

# Native-resolution crops; all columns come from the same camera and paused state.
font = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 20)
columns = [('当前默认', 'main_v2/baseline.png'), ('仅沙粒密度 30 → 70', 'main_v2/sand_density_70.png'),
           ('仅沙量着色采样改线性', 'layers_v3/sand_amount_linear.png')]
crop = (430, 490, 930, 710)
sheet = Image.new('RGB', (1500, 280), '#15202b')
draw = ImageDraw.Draw(sheet)
for i, (title, path) in enumerate(columns):
    draw.text((i * 500 + 12, 10), title, font=font, fill='white')
    sheet.paste(Image.open(OUT / path).crop(crop).convert('RGB'), (i * 500, 50))
sheet.save(OUT / 'sand_comparison.png')
result['comparison'] = dict(**identity(OUT / 'sand_comparison.png'), crop=list(crop), columns=columns,
                            note='No resizing or color correction; these are independent changes, not a combined candidate.')
rdc = json.loads((OUT / 'rdc/manifest.json').read_text())
result['rdc'] = dict(manifest=identity(OUT / 'rdc/manifest.json'), source=rdc['sources'][0],
                     pass_as_recorded=rdc['pass'], exports_verified=all(
                         Path(r['path']).is_file() and hashlib.sha256(Path(r['path']).read_bytes()).hexdigest() == r['sha256']
                         for r in rdc['exports']))
result['archive'] = identity(OUT / 'inspected_sources.zip')
(OUT / 'analysis.json').write_text(json.dumps(result, indent=2, ensure_ascii=False) + '\n', encoding='utf8')
print(json.dumps({k:dict(pass_as_recorded=v['pass_as_recorded'], failed_checks=v['failed_checks'], source_drift=v['source_drift']) for k,v in result['runs'].items()}, ensure_ascii=False))
