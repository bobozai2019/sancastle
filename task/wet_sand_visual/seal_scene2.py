import hashlib
import json
import shutil
from pathlib import Path

root = Path(__file__).resolve().parents[2]
out = root / 'task/wet_sand_visual/evidence/scene2_integration'
out.mkdir(parents=True, exist_ok=True)
(out / '.gdignore').write_text('')
digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
report = {'scope': 'Scene 2 default wet history; main stays disabled. Functional checks, not a full performance acceptance.', 'runs': {}}
for name in ['geometry_v1', 'geometry_v2', 'geometry_v3', 'geometry_v4', 'main_v1', 'main_v2', 'main_v3', 'main_v4']:
    src = root / 'test_output/wet_sand_scene2' / name
    dst = out / name
    dst.mkdir(exist_ok=True)
    for p in src.iterdir():
        if p.is_file() and p.suffix in ['.json', '.png', '.bin', '.sandue', '.log']:
            shutil.copy2(p, dst / p.name)
    row = {'files': [{'path': str(p.relative_to(root)), 'bytes': p.stat().st_size, 'sha256': digest(p)} for p in sorted(dst.iterdir()) if p.is_file()]}
    if (src / 'probe.json').exists():
        probe = json.loads((src / 'probe.json').read_text(encoding='utf-8'))
        row.update(passed=probe['pass'], failed_checks=[c for c in probe['checks'] if not c['pass']])
        if name in ['geometry_v4', 'main_v4']:
            row['source_drift'] = [p for p, h in probe['observations']['sources'].items() if digest(root / p.removeprefix('res://')) != h]
            row['command'] = ['D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe', '--path', str(root), '--rendering-driver', 'd3d12', '--script', 'res://tests/integration/surface_wetness_scene2_probe.gd', '--log-file', str(src / 'godot.log'), '--', '--output=' + str(src), '--scene=' + ('main' if name.startswith('main') else 'test1_geometry'), '--ignore-parameter-config']
            shutil.copy2(root / 'tests/integration/surface_wetness_scene2_probe.gd', dst / 'executed_probe.gd')
            if name == 'main_v4':
                p = dst / 'executed_probe.gd'
                code = p.read_text(encoding='utf-8')
                start = code.index('\tvar last_report:=started\n')
                end = code.index('\tcheck("formal_ready"', start)
                code = code[:start] + '\twhile (not scene.ready_for_ticks or scene._booting) and scene.last_error.is_empty() and Time.get_ticks_msec()-started<90000:await process_frame\n' + code[end:]
                p.write_text(code, encoding='utf-8')
            row['executed_probe_sha256'] = digest(dst / 'executed_probe.gd')
        else:
            row['note'] = 'Earlier diagnostic attempt preserved; intermediate probe source was not separately sealed.'
    else:
        row.update(passed=False, note='Test error or initialization timeout; process stopped after recording failure log. No completion report; reason is in the retained log.')
    report['runs'][name] = row
for name in ['architecture_v1', 'architecture_v2']:
    src = root / 'test_output/wet_sand_scene2' / name
    dst = out / name
    dst.mkdir(exist_ok=True)
    for p in src.iterdir():
        if p.is_file():shutil.copy2(p, dst / p.name)
(out / 'index.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps({k: {'passed': v['passed'], 'source_drift': v.get('source_drift')} for k, v in report['runs'].items()}, ensure_ascii=False))
