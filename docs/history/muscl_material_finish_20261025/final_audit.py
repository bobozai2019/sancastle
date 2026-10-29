"""Verify actual P1-P4 integration artifacts without launching Godot."""
from pathlib import Path
import json,hashlib,shutil
ROOT=Path(__file__).resolve().parents[3]
E=Path(__file__).resolve().parent/'验收'
def read(rel):return json.loads((E/rel).read_text(encoding='utf-8'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
checks=[]
def check(label,okay,detail=None):checks.append({'name':label,'pass':bool(okay),'detail':detail})

ids=read('candidate_identity.json')
for rel,want in ids.items():
    check('production_and_tested_source:'+rel,sha(ROOT/rel)==sha(E/'candidate_sources'/rel)==want and sha(ROOT/'test_output/muscl_material_finish_20261025/projects/combined'/rel)==want)
for rel,count in [('variant_v1_comparison.json',71),('first_order_v1_comparison.json',5),('main_inputs_v3_comparison.json',120),('geometry_inputs_v3_comparison.json',120)]:
    d=read(rel);check(rel,d['pass'] and d['paired_ticks']==count)

runs=['variant_v1_a','variant_v1_b','first_order_v1_a','first_order_v1_b','negative_v1_a','negative_v1_b','nonfinite_v1_a','nonfinite_v1_b','init_compile_v1','footprint_v1_a','footprint_v1_b','main_inputs_v1_a','main_inputs_v3_b','geometry_inputs_v3_a','geometry_inputs_v3_b','main_live_v1','continuous_v1']
for case in ['ordinary','molded']:
    d=read('cold_'+case+'_v1_summary.json')
    check('cold_'+case,d['pass'] and len(d['readers'])==3)
    runs.append(d['writer'])
    for row in d['readers']:
        runs.append(row['reader']);c=read(row['reader']+'_comparison/comparison.json')
        check(row['reader']+':exact_restart',row['pass'] and not row['errors'] and c['outcome']=='pass' and all(x['pass'] for x in c['checks']))
for name in runs:
    m=read(name+'/manifest.json')
    check(name+':run_identity',m['exit_code']==0 and not m['source_drift'] and m['user_unchanged'] and not m['engine_errors'])
life=read('init_compile_v1/lifecycle.json')
check('partial_init_and_release',all(x['pass'] for x in life['checks']))
for side in ['a','b']:
    d=read('footprint_v1_'+side+'/footprint.json');check('footprint_'+side,d['pass'] and all(x['pass'] for x in d['checks']))
structure=read('structure_comparison.json')
check('observed_structure',structure['delta']['logical_texture_payload']==262144 and structure['delta']['texture_bytes']==262144 and structure['delta']['buffer_bytes']==0 and structure['a']['dispatch_descriptors']==1541 and structure['b']['dispatch_descriptors']==1285,structure)
live=read('main_live_v1/result.json');check('actual_root_main_consumers',live['pass'] and live['generations_ok'] and not live['errors'])
isolated=read('main_live_v1/isolation.json')
check('user_data_inside_project',Path(isolated['user_data_dir']).resolve().is_relative_to(ROOT.resolve()),isolated['user_data_dir'])
d=read('continuous_v1/capture.json');m=d['metadata']
check('120s_pause_resume_release',d['pass'] and m['end_us']-m['start_us']>=120000000 and m['pause_ok'] and m['resume_ok'] and m['released'] and not m['source_drift'] and not m['last_error'],{k:m[k] for k in ['start_us','end_us','start_tick','end_tick','pause_ok','resume_ok','released']})
qa=read('document_qa/result.json')
check('document_render_review',qa['pass'] and qa['reviewed_pages']==list(range(1,48)) and qa['document_sha256']==sha(ROOT/'docs/Sandcastle项目技术全景.docx'))
review=read('architecture_integration_review.json')
check('reviewed_integration_boundary',review['integration_review_pass'] and not review['new_failures'],{'remaining_preexisting_failures':len(review['remaining_failures']),'scope':review['scope']})
check('policy_applied',sha(ROOT/'tools/unified_edit_pipeline/architecture_policy.json')==sha(E/'architecture_policy_candidate.json'))

# Preserve the small supporting edits separately from the numerical candidate.
support=['tools/wave_propagation/coupling_gpu_probe.gd','tools/wave_propagation/soak_probe.gd','tools/unified_edit_pipeline/architecture_policy.json','tools/docs/technical_panorama_content.py','tools/docs/build_unified_execution_guide.py','docs/当前项目技术方案.md','docs/当前技术规格.md','docs/project-execution-guide.sources.json','docs/technical-panorama.sources.json']
supporting={}
for rel in support:
    p=E/'supporting_sources'/rel;p.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/rel,p);supporting[rel]=sha(p)
out={'pass':all(x['pass'] for x in checks),'checks':checks,'retained':['P1','P2','P3','P4'],'runtime_files':ids,'supporting_files':supporting,'accepted_runs':runs,'performance_remeasured':False,'limitations':['No new ABBA performance claim.','Existing unrelated architecture-policy source drift remains explicitly unresolved.','Strict source identity applies to checkpoint restore; no new migration bypass.'],'invalid_or_partial_artifacts':['main_inputs_v1_b ZIP corrupted during disk exhaustion','main_inputs_v2_b archival copy failed during disk exhaustion','formal_v3 wrapper stopped after engine exit; bounded-memory raw comparison completed separately'],'c_old_archive_files_remaining':[str(p) for p in Path('C:/Users/18205/Documents/sandcastle_validation/material_finish_20261025').rglob('*') if p.is_file()]}
(E/'final_audit.json').write_text(json.dumps(out,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'pass':out['pass'],'checks':len(checks),'failed':[x['name'] for x in checks if not x['pass']],'c_old_archive_files_remaining':len(out['c_old_archive_files_remaining'])},ensure_ascii=False))
raise SystemExit(not out['pass'])
