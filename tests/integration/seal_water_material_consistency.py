"""Seal the actual frozen-state material audit and controlled images."""
import hashlib
import json
from pathlib import Path
from PIL import Image
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'test_output/water_material_consistency_delivery_20261013'
OUT.mkdir(exist_ok=True)
RUN = ROOT / 'test_output/water_material_consistency_20261013_v2'
report = json.loads((RUN / 'result.json').read_text(encoding='utf-8'))
assert report['pass'] and len(report['checks']) == 30
log = ROOT / 'test_output/water_material_consistency_20261013_v2.log'
assert not any(line.startswith(('ERROR:', 'SCRIPT ERROR:', 'SHADER ERROR:')) for line in log.read_text(encoding='utf-8').splitlines())
assert len({scene['sun'] for scene in report['scenes']}) == 1

def indexed(path, kind):
    return {'path': str(path.resolve()), 'kind': kind, 'bytes': path.stat().st_size,
            'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}

files = []
for version in ['v1', 'v2']:
    directory = ROOT / ('test_output/water_material_consistency_20261013_' + version)
    for path in directory.rglob('*'):
        if path.is_file():
            files.append(indexed(path, 'evidence_' + version))
    files.append(indexed(directory.with_suffix('.log'), 'log_' + version))

sources = set(['project.godot', 'scenes/main.tscn', 'scenes/playable/test1_capture.tscn',
    'scenes/playable/test1_backwash.tscn', 'scripts/beach/beach_playable_entry.gd',
    'scripts/scenarios/test1_playable_layout.gd', 'scripts/beach/beach_scene_service.gd',
    'assets/test1_water_motion/capture_state.rgba32f', 'assets/test1_water_motion/capture_profile.json',
    'tests/integration/water_material_consistency_probe.gd', 'tests/integration/seal_water_material_consistency.py',
    'tests/visual_water_alignment/prototypes/rock_reflection_candidate_entry.gd'])
for directory in ['assets/water_material_natural_candidate', 'scenes/water_material_natural_candidate']:
    for path in (ROOT / directory).rglob('*'):
        if path.is_file() and path.suffix in ['.json', '.gd', '.gdshader', '.tscn']:
            sources.add(path.relative_to(ROOT).as_posix())
for scene in report['scenes']:
    for material in scene['materials'].values():
        sources.add(material['shader'].removeprefix('res://'))
        for value in material['parameters'].values():
            if isinstance(value, dict) and value.get('resource', '').startswith('res://'):
                sources.add(value['resource'].removeprefix('res://'))
for source in sorted(sources):
    path = ROOT / source
    files.append(indexed(path, 'source'))
    snapshot = OUT / 'source_snapshot' / (source + '.source')
    snapshot.parent.mkdir(parents=True, exist_ok=True)
    snapshot.write_bytes(path.read_bytes())
    files.append(indexed(snapshot, 'frozen_source'))

contributions = {}
for key in ['test1_capture', 'test1_backwash']:
    baseline = np.asarray(Image.open(RUN / (key + '_default.png')).convert('RGB')).astype(np.int16)
    contributions[key] = {}
    for variant in ['no_detail_normal', 'no_absorption']:
        candidate = np.asarray(Image.open(RUN / (key + '_' + variant + '.png')).convert('RGB')).astype(np.int16)
        difference = np.abs(candidate - baseline)
        contributions[key][variant] = {'pixels_changed_gt2': int((difference.max(axis=2) > 2).sum()),
            'rgb_byte_mean_abs_difference': float(difference.mean()), 'scope': 'same fields, camera and frozen clock; one shading toggle'}

manifest = {'scope': 'Current Godot editable scene materials and frozen initial inputs; not original competitor units or timing.',
    'pass': True, 'checks': 30, 'actual_exec_exit_code': 0, 'engine': report['engine'], 'adapter': report['adapter'],
    'command': "D:/godot/Godot_v4.7.1-stable/Godot_v4.7.1-stable_win64_console.exe --path D:/godot/project/sandcastle --script res://tests/integration/water_material_consistency_probe.gd",
    'replay_note': 'Preserve existing outputs; copy the frozen probe and replace its output directory with a fresh English absolute path before rerunning.',
    'window': [1280, 720], 'backend': 'D3D12 Forward+', 'contributions': contributions,
    'uniform_counts': {key: len(value['parameters']) for key, value in report['scenes'][0]['materials'].items()},
    'history': 'v1 incorrectly classified the camera-computed reflection matrix as a fixed parameter; failures retained. v2 separates that runtime input. v1 source was not frozen.',
    'files': files}
(OUT / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps({'checks': 30, 'files': len(files), 'uniform_counts': manifest['uniform_counts'], 'contributions': contributions}, ensure_ascii=False))
