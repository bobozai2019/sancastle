import hashlib
import json
import shutil
import zipfile
from pathlib import Path

project = Path(__file__).resolve().parents[2]
task = Path(__file__).resolve().parent
temporary = project / 'test_output/wet_sand_diagnosis'
digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
report = {'scope': 'Two formal scenes, D3D12 GTX 1050, 1280x720, generation 1001, fixed authored cameras, default parameters, manual 0.1 m / 3 s wave plus normal boundary. Snapshots at completed simulation time targets 0/3/6/10/16/24 s, then frozen material-only forced-wetness tests. No new competitor claim; no production modification.', 'runs': {}}
for name in ['main', 'main_v2', 'geometry']:
    src = temporary / name
    dst = task / 'evidence' / name
    dst.mkdir(parents=True, exist_ok=True)
    for path in src.iterdir():
        if path.is_file() and path.suffix in ['.json', '.png', '.bin', '.log']:
            shutil.copy2(path, dst / path.name)
    row = {'files': [{'path': p.relative_to(project).as_posix(), 'bytes': p.stat().st_size, 'sha256': digest(p)} for p in sorted(dst.iterdir()) if p.is_file()]}
    if (src / 'probe.json').exists():
        probe = json.loads((src / 'probe.json').read_text(encoding='utf-8'))
        row['pass'] = probe['pass']
        row['failed_checks'] = [c for c in probe['checks'] if not c['pass']]
        observations = probe['observations']
        row['source_drift'] = [p for p,h in observations['sources'].items() if digest(project / p.removeprefix('res://')) != h]
        before, after = observations['snapshots'][-2:]
        row['all_captured_authority_unchanged_by_visual_variants'] = all(before['fields'][f]['sha256'] == after['fields'][f]['sha256'] for f in ['rock','sand','water','wetness','compaction'])
        row['clock_unchanged_by_visual_variants'] = (before['tick'],before['time']) == (after['tick'],after['time'])
        row['cohort'] = json.loads((src / 'cohort.json').read_text(encoding='utf-8'))
        row['command'] = ['D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe','--path',str(project),'--rendering-driver','d3d12','--script','res://task/wet_sand_diagnosis/probe.gd','--log-file',str(src/'godot.log'),'--','--output='+str(src),'--scene='+('test1_geometry' if name=='geometry' else 'main'),'--ignore-parameter-config']
        shutil.copy2(task/'probe.gd',dst/'executed_probe.gd')
    else:
        row['pass'] = False
        row['failure'] = 'Initial diagnostic script parse error; no scene executed. Preserved original log.'
    report['runs'][name] = row
paths = ['assets/water_material_natural_candidate/async_rdc_bed.gdshader','scripts/simulation/unified_edit/coupled.gd','scripts/simulation/unified_edit/views.gd','scripts/simulation/unified_edit/view_publish.glsl','scripts/simulation/unified_edit/pipeline.gd','shaders/simulation/material/material_step.glsl','scripts/simulation/unified_edit/water_muscl.gd','assets/unified_edit/presentation/main.json','assets/unified_edit/presentation/test1_geometry.json','assets/test1_geometry/water_cycle.json']
with zipfile.ZipFile(task/'inspected_sources.zip','w',zipfile.ZIP_DEFLATED) as archive:
    for path in paths: archive.write(project/path,path)
report['source_archive'] = {'path':'task/wet_sand_diagnosis/inspected_sources.zip','sha256':digest(task/'inspected_sources.zip')}
(task/'result.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({n:{k:v for k,v in r.items() if k not in ['files','command']} for n,r in report['runs'].items()},ensure_ascii=False,indent=2))
