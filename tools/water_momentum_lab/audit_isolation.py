import hashlib,json,re,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'test_output/water_momentum_lab'
baseline=json.loads((OUT/'g0_sources_20261019/workspace_baseline.json').read_text(encoding='utf-8'))
changes=[]
for row in baseline:
 p=Path(row['path'])
 if not p.is_file() or hashlib.sha256(p.read_bytes()).hexdigest()!=row['sha256']:changes.append(str(p.relative_to(ROOT)))
allowed=('task/sandcastle_water_momentum_lab/','docs/competitor/')
unexpected=[p for p in changes if not p.replace('\\','/').startswith(allowed)]
formal_refs=[]
for base in ['scripts','scenes','shaders','addons']:
 for p in (ROOT/base).rglob('*'):
  if not p.is_file() or p.suffix not in ['.gd','.tscn','.tres','.gdshader','.glsl']:continue
  if p==ROOT/'scenes/experiments/water_momentum_lab.tscn':continue
  text=p.read_text(encoding='utf-8',errors='replace')
  if 'water_momentum_lab' in text:formal_refs.append(str(p.relative_to(ROOT)))
globals=[]
for p in (ROOT/'tests/water_momentum_lab').rglob('*.gd'):
 if re.search(r'^class_name\s',p.read_text(encoding='utf-8'),re.M):globals.append(str(p.relative_to(ROOT)))
reference=[]
for row in json.loads((ROOT/'tests/water_momentum_lab/reference/sources.json').read_text(encoding='utf-8')):
 source=Path(row['path']);frozen=ROOT/'tests/water_momentum_lab/reference'/source.name
 reference.append({'source':str(source),'source_hash_matches':hashlib.sha256(source.read_bytes()).hexdigest()==row['sha256'],'copy_byte_identical':source.read_bytes()==frozen.read_bytes()})
for name in ['drain_scale','update_state']:
 original=(ROOT/f'tests/water_momentum_lab/reference/shallow_{name}.glsl').read_text(encoding='utf-8')
 expected=original.replace('layout(push_constant, std430) uniform Params','layout(set = 0, binding = 15, std430) readonly buffer Params')
 actual=(ROOT/f'tests/water_momentum_lab/shaders/shallow_{name}.glsl').read_text(encoding='utf-8')
 reference.append({'adaptation':name,'parameter_binding_only':actual==expected})
report={'passed':not unexpected and not formal_refs and not globals and all(all(v for k,v in row.items() if isinstance(v,bool)) for row in reference),'changed_baseline_files':changes,'unexpected_changes':unexpected,'formal_experiment_references':formal_refs,'global_class_registrations':globals,'frozen_math':reference,'git_status':subprocess.check_output(['git','status','--short'],cwd=ROOT).decode('utf-8',errors='replace')}
(OUT/'isolation_audit.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(report,ensure_ascii=False,indent=2))
