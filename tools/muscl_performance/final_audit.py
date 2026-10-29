"""Verify final evidence and retain reconstructable tools/source snapshots."""
from pathlib import Path
import hashlib
import json
import shutil

ROOT=Path(__file__).resolve().parents[2]
E=ROOT/'task/muscl_performance_round2/验收'

def read(p):
    return json.loads(p.read_text(encoding='utf-8'))

def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

checks={}
for name in ('t04_state_comparison_final','t04_formal_comparison','t07_inputs_comparison'):
    checks[name]=read(E/(name+'.json'))['pass']
for name in ('t07_wave_cost_comparison','t07_shovel_cost_comparison'):
    checks[name]=read(E/(name+'.json'))['valid_identities']
for name,key in [('t07_main_inputs_v3/variant.json','pass'),('t07_main_live/result.json','pass'),('t07_continuous_summary.json','pass'),('t07_document_qa/result.json','pass')]:
    checks[name]=read(E/name)[key]
checks['cold_restart']=read(E/'t07_current_restart_comparison/comparison.json')['outcome']=='pass'
checks['final_math_identity']=read(E/'t07_combined_architecture.json')['root_matches_measured_candidate']
core=read(E/'t07_combined_architecture.json')['source_hashes']
checks['current_core_identity']=all(sha(ROOT/p)==h for p,h in core.items())
runs=['t07_inputs_a','t07_inputs_b','t07_main_inputs_v3','t07_main_live','t07_continuous','t07_current_restart_seed','t07_current_restart_resume']
runs += [f't07_{case}_cost_{part}' for case in ('wave','shovel') for part in ('a1','b1','b2','a2')]
for name in runs:
    m=read(E/name/'manifest.json')
    checks[name+':manifest']=m['validated_exit_code']==0 and not m['source_drift'] and m['user_unchanged']
sources=read(ROOT/'docs/technical-panorama.sources.json')
checks['panorama_source_hashes']=all(sha(ROOT/p)==h for p,h in sources['sources'].items())
checks['panorama_document_hash']=sha(ROOT/sources['document'])==sources['document_sha256']
checks['panorama_qa_identity']=sha(ROOT/sources['document'])==read(E/'t07_document_qa/result.json')['docx_sha256']
memory=read(E/'t07_continuous_summary.json')
checks['continuous_bounded']=memory['wall_s']>=120 and memory['focused_fraction']==1 and memory['max_pending']<=4 and memory['max_active']<=3 and len(memory['texture_bytes'])==len(memory['buffer_bytes'])==1
assert all(checks.values()),{k:v for k,v in checks.items() if not v}
tools=E/'t07_tools';tools.mkdir(exist_ok=False)
for p in (ROOT/'tools/muscl_performance').iterdir():
    if p.is_file():shutil.copy2(p,tools/p.name)
snapshot=E/'t07_final_sources'
for relative in list(core)+['assets/water_sides/geometry_manifest.json']:
    target=snapshot/relative;target.parent.mkdir(parents=True,exist_ok=True)
    shutil.copy2(ROOT/relative,target)
result={'pass':True,'checks':checks,'retained':['T04'],'withdrawn':['T03','T05','T06'],'completed_tasks':8,'total_tasks':8,
        'snapshots':{p.relative_to(E).as_posix():sha(p) for folder in (tools,snapshot) for p in folder.rglob('*') if p.is_file()},
        'reconstruction':'T00 runtime.zip plus run-specific sources overlays; imported cache is derived. Do not combine incompatible private shader layouts. Final developer tools snapshot is separate from each historical executed harness.',
        'limits':'GPU same-tick gain about 6.95 percent; no fixed FPS or CPU gain promise. Fixed input manual scheduling is not ordinary realtime FPS. One 120-second run is bounded stability evidence.'}
(E/'t07_final_audit.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print('FINAL_AUDIT PASS',len(checks),'checks',len(result['snapshots']),'retained files')
