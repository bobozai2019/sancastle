"""Index the authorized free sand tool change and actual validation runs."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'test_output/free_tools_delivery_20261013'
OUT.mkdir(exist_ok=True)

def row(path, kind):
    return {'path': str(path.resolve()), 'bytes': path.stat().st_size,
            'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'kind': kind}

files = []
runs = {}
for directory, filename, collection in [
    ('free_tools_camera_20261013_v2', 'result.json', 'checks'),
    ('free_tools_contract_20261013', 'contract_probe.json', 'checks'),
    ('free_tools_inventory_regression_20261013', 'scheduler_admission_probe.json', 'rows'),
]:
    path = ROOT / 'test_output' / directory
    result = json.loads((path / filename).read_text(encoding='utf-8'))
    log = path.with_suffix('.log')
    assert result['pass'] and all(item['pass'] for item in result[collection])
    assert not any(line.startswith(('ERROR:', 'SCRIPT ERROR:', 'SHADER ERROR:')) for line in log.read_text(encoding='utf-8').splitlines())
    runs[directory] = {'pass': True, 'actual_exec_exit_code': 0, 'checks': len(result[collection]),
                       'result': str(path / filename), 'log': str(log)}
    files.append(row(log, 'log'))
    for item in path.rglob('*'):
        if item.is_file(): files.append(row(item, 'evidence'))

history = ROOT / 'test_output/free_tools_camera_20261013_v1'
for item in history.rglob('*'):
    if item.is_file(): files.append(row(item, 'historical_failure'))
files.append(row(history.with_suffix('.log'), 'historical_failure_log'))
files.append(row(ROOT / 'test_output/free_tools_20261013_smoke_v1.log', 'historical_compile_failure'))

sources = ['scenes/main.tscn', 'scenes/playable/test1_capture.tscn', 'scenes/playable/test1_backwash.tscn',
    'scripts/beach/free_camera.gd', 'scripts/beach/beach_gpu_entry.gd',
    'scripts/beach/beach_interaction_entry.gd', 'scripts/beach/beach_recovery_entry.gd',
    'scripts/beach/beach_playable_entry.gd', 'scripts/beach/beach_scene_service.gd',
    'scripts/simulation/edit_validation/gpu_edit_scheduler.gd',
    'scripts/simulation/edit_validation/gpu_checkpoint_codec.gd',
    'scripts/simulation/edit_validation/edit_protocol.gd',
    'tests/integration/free_tools_camera_probe.gd', 'tests/integration/seal_free_tools.py',
    'tests/edit_validation/contract_probe.gd', 'tests/edit_validation/scheduler_admission_probe.gd',
    'docs/knowledge/water_sand/ADR_自由挖填沙_external_v1.md', 'docs/主场景操作.md',
    'docs/场景切换与功能复用.md']
for source in sources:
    path = ROOT / source
    files.append(row(path, 'source'))
    snapshot = OUT / 'source_snapshot' / (source + '.source')
    snapshot.parent.mkdir(parents=True, exist_ok=True)
    snapshot.write_bytes(path.read_bytes())
    files.append(row(snapshot, 'frozen_source'))

manifest = {'scope': 'Authorized main free sand editing, inherited playable layouts, native recovery and camera input. No competitor business analysis or cost gate.',
    'checks': sum(result['checks'] for result in runs.values()), 'runs': runs,
    'engine_path': 'D:/godot/Godot_v4.7.1-stable/Godot_v4.7.1-stable_win64_console.exe',
    'commands': {name: '--path D:/godot/project/sandcastle ' + ('--headless ' if 'contract' in name else '') + '--script res://' + script + ' -- --output=D:/godot/project/sandcastle/test_output/' + name
        for name, script in [('free_tools_camera_20261013_v2', 'tests/integration/free_tools_camera_probe.gd'),
        ('free_tools_contract_20261013', 'tests/edit_validation/contract_probe.gd'),
        ('free_tools_inventory_regression_20261013', 'tests/edit_validation/scheduler_admission_probe.gd')]},
    'camera_and_gpu_backend': 'D3D12 Forward+; GTX 1050; 1280x720 visible window',
    'replay': 'Use a fresh English absolute output path; saved checkpoints retain strict source signatures.',
    'editor_tool': {'verdict': 'INCONCLUSIVE', 'phase': 'tool_error', 'error': "GodotIQSession object has no attribute root", 'counted_as_pass': False},
    'historical_failures': ['smoke v1 camera motion type inference, fixed with explicit Vector2', 'camera v1: 2 exact-float default-value assertions; v2 uses approximate comparisons'],
    'files': files}
assert manifest['checks'] == 92
(OUT / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps({'checks': manifest['checks'], 'runs': len(runs), 'files': len(files)}))
