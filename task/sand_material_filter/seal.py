"""Preserve this task's raw probes and report the scoped ABBA render timings."""
from pathlib import Path
import hashlib
import json
import shutil
import statistics

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'task/sand_material_filter/evidence'
SRC = ROOT / 'test_output/sand_material_filter_20261024'

def ident(path):
    return dict(path=path.relative_to(ROOT).as_posix(), bytes=path.stat().st_size,
                sha256=hashlib.sha256(path.read_bytes()).hexdigest())

summary = dict(scope='Visible full-scene rendering at a frozen completed state after 4 seconds live smoke; ABBA, 2 seconds warmup + 4 seconds per window; whole main viewport GPU time, not simulation throughput.', runs={})
for name in ('main', 'main_v2', 'geometry'):
    target = OUT / name
    shutil.copytree(SRC / name, target, dirs_exist_ok=False)
    r = json.loads((target / 'probe.json').read_text(encoding='utf-8-sig'))
    o = r['observations']
    row = dict(pass_as_recorded=r['pass'], failed_checks=[x for x in r['checks'] if not x['pass']],
               error=o.get('error'), artifacts=[ident(p) for p in sorted(target.iterdir()) if p.is_file()])
    row['command'] = ['D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe',
        '--path',str(ROOT),'--rendering-driver','d3d12','--script','res://task/sand_material_filter/probe.gd',
        '--log-file',str(SRC/name/'godot.log'),'--','--output='+str(SRC/name),
        '--scene='+('test1_geometry' if name=='geometry' else 'main'),'--ignore-parameter-config']
    if 'cost' in o:
        medians = {}
        row['windows'] = []
        for phase in o['cost']:
            samples=phase['samples'];a=[s['gpu_ms'] for s in samples]
            assert a and min(a)>0
            median=statistics.median(a);medians[phase['phase']]=median
            row['windows'].append(dict(phase=phase['phase'],frames=len(a),gpu_median_ms=median,
                gpu_mean_ms=statistics.mean(a),focused_frames=sum(s['focused'] for s in samples)))
        before=statistics.mean(v for k,v in medians.items() if k.startswith('before'))
        after=statistics.mean(v for k,v in medians.items() if k.startswith('after'))
        row.update(before_gpu_ms=before,after_gpu_ms=after,delta_gpu_ms=after-before,
                   delta_percent=100*(after/before-1),render=o['render'],tick=o['cost_tick'],
                   source_drift=o['source_drift'])
    summary['runs'][name]=row
sources=['assets/water_material_natural_candidate/async_rdc_bed.gdshader',
         'assets/water_sides/geometry_manifest.json','assets/unified_edit/presentation/main.json',
         'assets/unified_edit/presentation/test1_geometry.json','task/sand_material_filter/probe.gd',
         'task/sand_material_filter/seal.py']
summary['sources']=[ident(ROOT/p) for p in sources]
summary['document_qa'] = dict(source_check='passed',render='unavailable',
    reason='Packaged render_docx.py raised FileNotFoundError: LibreOffice soffice.exe was not found on PATH. Existing environment limitation also recorded in task/parameter_windows/执行状态.md. No pagination QA claim.')
(ROOT/'task/sand_material_filter/result.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
print(json.dumps({k:{a:v.get(a) for a in ('pass_as_recorded','error','before_gpu_ms','after_gpu_ms','delta_gpu_ms','delta_percent')} for k,v in summary['runs'].items()},ensure_ascii=False))
