"""Index sources, selected raw data, derivatives, source snapshots, and known limitations."""
import hashlib,json,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3];BASE=ROOT/'test_output/test1_water_motion'
cap=json.loads((BASE/'capture_v1/manifest.json').read_text());pkg=json.loads((BASE/'package_v1/manifest.json').read_text())
def identity(p):return {'path':str(p),'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
for source in [ROOT/'sandcastlegame/test1.rdc',ROOT/'rdc/test1.rdc']:
 assert identity(source)['sha256']==cap['source']['sha256']
assert identity(Path(pkg['source']))['sha256']==pkg['source_sha256']
assert identity(BASE/'capture_v1/export_capture.source.py')['sha256']==cap['script']['sha256']
assert identity(BASE/'package_v1/export_package.source.py')['sha256']==pkg['script_sha256']
matches=[]
for row in cap['events']:
 if row['stage']!='ShaderStage.Compute':continue
 kernels=[k for k in pkg['kernels'] if k['bytecode_sha256']==row['bytecode']['sha256']]
 assert len(kernels)==1
 matches.append({'event':row['event'],'name':kernels[0]['name'],'sha256':row['bytecode']['sha256']})
run_status={}
for run in ['gpu_release_v3','gpu_hold_v2','gpu_repeat_v1']:
 d=json.loads((BASE/run/'manifest.json').read_text());assert d['operation_complete'] and d['sources_unchanged']
 run_status[run]={'actual_process_exit_code':0,'observation':'exec session completion exit_code0, matching run log and manifest',
  'samples':len(d['samples']),'controls':d['controls'],'operation_complete':True}
report={'date':'2026-10-12 Asia/Shanghai','capture_source':cap['source'],'package_source':{k:pkg[k] for k in ['source','source_bytes','source_sha256','path_id','object_byte_start','object_bytes']},
 'kernel_matches':matches,'raw_export_selectors':cap['exports'],'package_exports':pkg['exports'], 'executed_script_snapshots':[identity(BASE/'capture_v1/export_capture.source.py'),identity(BASE/'package_v1/export_package.source.py')],
 'run_status':run_status,'direct_start':{'actual_process_exit_code':0,'frames':180,'scene':'res://scenes/test1_water_motion_trial.tscn','log':'test_output/test1_water_motion/direct_start.log'},
 'early_attempt':{'status':'no manifest or exports observed','owned_pid':21476,'source_snapshot':'not captured','note':'Initial script used __file__; retry used an explicit script path. Initial exception stack was unavailable. Only the owned helper was stopped.'},
 'limits':['single capture does not establish original future customWave/playTime series or real seconds/metres','original in-place UAV differs from immutable Godot phase inputs; local maximum error retained','earlier unsealed GPU runs retained as diagnostics','other task Sandcastle process PID7188 was present initially; no exclusive performance measurement'],
 'files':[]}
sources=list((ROOT/'tests/investigation/test1_water_motion').glob('*'))+list((ROOT/'assets/test1_water_motion').glob('*'))+[
 ROOT/'scripts/visual/test1_water_motion_trial.gd',ROOT/'shaders/simulation/test1_water_motion.glsl',ROOT/'scenes/test1_water_motion_trial.tscn',ROOT/'docs/competitor/水体运动与回落.md',ROOT/'docs/水体运动_独立测试.md']
files=list(BASE.rglob('*'))+sources
for p in sorted(set(files)):
 if not p.is_file() or p.suffix in ['.import','.uid','.pyc'] or p.name=='evidence_inventory.json':continue
 rel=str(p.relative_to(ROOT)).replace('\\','/')
 kind='derived_or_diagnostic'
 if '/capture_v1/raw/' in rel:kind='captured_raw_or_disassembly; exact selector in raw_export_selectors'
 elif '/package_v1/' in rel:kind='package_object_raw_or_derivative; selector in package_exports'
 elif p.suffix=='.rgba32f' and 'gpu_' in rel:kind='experimental_GPU_complete_state'
 elif '/source_snapshot/' in rel:kind='run_source_snapshot'
 report['files'].append(dict(identity(p),kind=kind))
links=[]
for p in [ROOT/'docs/competitor/水体运动与回落.md',ROOT/'docs/水体运动_独立测试.md']:
 for target in re.findall(r'\]\(([^)]+)\)',p.read_text(encoding='utf-8')):
  if '://' in target:continue
  q=(p.parent/target.split('#')[0]).resolve()
  if q.name=='evidence_inventory.json':continue
  if not q.exists():links.append({'document':str(p),'target':target})
assert not links,links
report['internal_links_valid']=True
(BASE/'evidence_inventory.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print(json.dumps({'indexed_files':len(report['files']),'source_unchanged':True,'kernel_matches':len(matches),'links_valid':True}))
