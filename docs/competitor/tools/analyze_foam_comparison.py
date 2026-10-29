"""Derive foam statistics and a labeled screenshot comparison without recoloring."""
import hashlib
import json
import shutil
from pathlib import Path
import numpy as np
from PIL import Image
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'docs/competitor/evidence/foam_comparison_20261024'
plt.rcParams['font.sans-serif'] = ['Microsoft YaHei', 'SimHei', 'DejaVu Sans']
plt.rcParams['axes.unicode_minus'] = False

def identity(path):
    return {'path': path.relative_to(ROOT).as_posix(), 'bytes': path.stat().st_size,
            'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}

vertices = np.fromfile(OUT / 'rdc/e6196_vsout.bin', dtype='<f4').reshape(-1, 4, 10)
widths = np.ptp(vertices[:, :, 4], axis=1)
summary = {'scope': 'Per-image ablation footprints, not additive layer area or cross-game similarity. Only a single captured competitor frame.',
           'competitor': {'instances': len(vertices), 'flat_y_max_range': float(np.ptp(vertices[:, :, 5], axis=1).max()),
                          'width_percentiles_0_5_50_95_100_scene_units': np.percentile(widths, [0, 5, 50, 95, 100]).tolist(),
                          'strength_percentiles_0_50_100': np.percentile(vertices[:, 0, 9], [0, 50, 100]).tolist(),
                          'alpha_center_upper_bound_from_instructions': 0.2}, 'scenes': {}, 'source_snapshots': []}
sources = set(['shaders/simulation/visual_foam_step.glsl', 'scripts/simulation/unified_edit/visuals.gd',
               'assets/water_material_natural_candidate/foam_distribution.gdshader',
               'assets/water_material_natural_candidate/contact_shape.gdshader',
               'assets/water_material_natural_candidate/async_rdc_water.gdshader',
               'assets/test1_beach/test1_front_foam_sparse_mesh.tres',
               'tests/visual_water_alignment/prototypes/reference_local_front_x.glsl',
               'tests/visual_water_alignment/prototypes/reference_local_front_x_wide.glsl',
               'tests/visual_water_alignment/prototypes/reference_local_front_z.glsl'])
for scene in ('main', 'geometry'):
    probe = json.loads((OUT / scene / 'probe.json').read_text(encoding='utf-8'))
    obs = probe['observations']
    entry = {'probe_pass': probe['pass'], 'frames': obs['frames'], 'render': obs['render'], 'camera': obs['camera'], 'layers': {}}
    summary['scenes'][scene] = entry
    for layer, data in obs['layers'].items():
        entry['layers'][layer] = {'visible': data['visible'], 'vertices': data['vertices'], 'shader': data['shader'], 'shader_sha256': data['shader_sha256']}
    entry['ablation_pixels_channel_delta_gt_2_of_255'] = {}
    for tick in (240, 360):
        base = np.asarray(Image.open(OUT / scene / f't{tick}.png')).astype(np.int16)
        entry['ablation_pixels_channel_delta_gt_2_of_255'][str(tick)] = {}
        for path in (OUT / scene).glob(f't{tick}_no_*.png'):
            delta = np.max(np.abs(base - np.asarray(Image.open(path)).astype(np.int16)), axis=2)
            entry['ablation_pixels_channel_delta_gt_2_of_255'][str(tick)][path.stem] = int(np.count_nonzero(delta > 2))
    key = 'main' if scene == 'main' else 'test1_geometry'
    sources.update([f'scenes/unified_edit/presentation/{key}.tscn', f'assets/unified_edit/presentation/{key}.json', 'scripts/beach/unified_playable_entry.gd'])
for relative in sorted(sources):
    source = ROOT / relative
    dest = OUT / 'sources' / relative
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, dest)
    summary['source_snapshots'].append({'source': identity(source), 'snapshot': identity(dest)})

panels = [
    ('竞品 test1：浪头细沫（捕帧局部）', 'rdc/capture_thumbnail.png', (1000, 230, 1450, 610)),
    ('当前原比例场景：8 模拟秒', 'geometry/t240.png', (530, 235, 845, 515)),
    ('当前主场景：12 模拟秒', 'main/t360.png', (380, 405, 760, 710)),
    ('同一状态：关闭水面内白沫', 'geometry/t240_no_water_foam.png', (530, 235, 845, 515)),
    ('同一状态：关闭独立细沫', 'geometry/t240_no_PrototypeFrontFoamDense.png', (530, 235, 845, 515)),
    ('同一状态：关闭岸边接触层', 'main/t360_no_ShoreContactOverlay.png', (380, 405, 760, 710)),
]
fig, axes = plt.subplots(2, 3, figsize=(15, 10), dpi=120, facecolor='#f5f3ec')
summary['figure_panels'] = []
for ax, (title, relative, box) in zip(axes.flat, panels):
    pixels = np.asarray(Image.open(OUT / relative))
    left, top, right, bottom = box
    ax.imshow(pixels[top:bottom, left:right], interpolation='nearest')
    ax.set_title(title, fontsize=12, pad=10)
    ax.axis('off')
    summary['figure_panels'].append({'title': title, 'source': relative, 'crop_xyxy': box, 'resampling': 'nearest; original RGB unchanged'})
fig.suptitle('泡沫差距与分层归因', fontsize=21, y=0.98)
fig.text(0.5, 0.035, '原图裁切，未调色；局部缩放不同。竞品与项目机位、波相、曝光不同，不作尺寸或亮度定量比较。\n下排为项目固定 tick / 完成态 / 相机的单变量开关对照；仅定位该层的可见贡献。', ha='center', fontsize=11)
fig.subplots_adjust(left=0.02, right=0.98, top=0.91, bottom=0.11, wspace=0.08, hspace=0.15)
fig.savefig(OUT / 'comparison.png', facecolor=fig.get_facecolor())
plt.close(fig)
(OUT / 'analysis.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding='utf-8')
manifest = {'date': '2026-10-24', 'sources': summary['source_snapshots'],
            'tools': [identity(ROOT / 'docs/competitor/tools' / name) for name in ('export_foam_comparison.py', 'probe_foam_comparison.gd', 'analyze_foam_comparison.py')],
            'competitor_manifest': 'rdc/manifest.json', 'probe': 'docs/competitor/tools/probe_foam_comparison.gd',
            'commands': ['godot.windows.opt.tools.64.exe --path D:/godot/project/sandcastle --script res://docs/competitor/tools/probe_foam_comparison.gd -- --scene=main --output=res://docs/competitor/evidence/foam_comparison_20261024/main',
                         'godot.windows.opt.tools.64.exe --path D:/godot/project/sandcastle --script res://docs/competitor/tools/probe_foam_comparison.gd -- --scene=test1_geometry --output=res://docs/competitor/evidence/foam_comparison_20261024/geometry',
                         'python -X utf8 docs/competitor/tools/analyze_foam_comparison.py'],
            'attempts': [{'kind': 'initial_renderdoc_launch', 'status': 'no output observed', 'detail': 'Initial script used __file__ before report initialization; changed to an explicit script path. No raw evidence was produced by that attempt; exact UI exception was not captured.'}],
            'files': [identity(p) for p in sorted(OUT.rglob('*')) if p.is_file() and p.name != 'inventory.json']}
(OUT / 'inventory.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps({k: v['ablation_pixels_channel_delta_gt_2_of_255'] for k, v in summary['scenes'].items()}, indent=2))
