import hashlib
import json
import shutil
from pathlib import Path

project = Path(__file__).resolve().parents[2]
task = Path(__file__).resolve().parent
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
report = {'scope': 'Experimental in-memory publisher and sand material replacement on both formal scenes. Production files unchanged. No checkpoint integration or full acceptance.', 'runs': {}}
for name in ['main', 'geometry', 'cost']:
    src = project / 'test_output/wet_sand_trial' / name
    dst = task / 'evidence/trial' / name
    dst.mkdir(parents=True, exist_ok=True)
    probe = json.loads((src / 'probe.json').read_text(encoding='utf-8'))
    for p in src.iterdir():
        if p.is_file() and p.suffix in ['.json', '.png', '.bin', '.log']:
            shutil.copy2(p, dst / p.name)
    row = {'pass': probe['pass'], 'failed_checks': [c for c in probe['checks'] if not c['pass']], 'files': [{'path': str(p.relative_to(project)), 'bytes': p.stat().st_size, 'sha256': sha(p)} for p in sorted(dst.iterdir()) if p.is_file()]}
    row['production_source_drift'] = [p for p, h in probe['observations']['sources'].items() if sha(project / p.removeprefix('res://')) != h]
    row['command'] = ['D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe', '--path', str(project), '--rendering-driver', 'd3d12', '--script', 'res://task/wet_sand_visual/' + ('cost_probe.gd' if name == 'cost' else 'trial_probe.gd'), '--log-file', str(src / 'godot.log'), '--', '--output=' + str(src), '--scene=' + ('test1_geometry' if name == 'geometry' else 'main'), '--ignore-parameter-config']
    report['runs'][name] = row
report['experimental_sources'] = [{'path': str(p.relative_to(project)), 'sha256': sha(p)} for p in [task / 'fused_publish.glsl', task / 'trial_probe.gd', task / 'cost_probe.gd', task / 'seal_trial.py']]
(task / 'evidence/trial/index.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps({k: {'pass': v['pass'], 'source_drift': v['production_source_drift']} for k, v in report['runs'].items()}, ensure_ascii=False))
