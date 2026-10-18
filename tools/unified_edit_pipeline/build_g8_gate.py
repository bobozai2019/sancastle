"""Issue G8 only after real component, architecture, document and visual evidence."""
import hashlib
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
TASK=ROOT/'task/sandcastle_unified_edit_pipeline'
def identity(path):return {'path':path.relative_to(ROOT).as_posix(),'bytes':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
def main():
    evidence=[];components={}
    for name in ['G8_功能组件.json','G8_长稳组件.json','G8_成本组件.json']:
        path=TASK/'验收'/name;data=json.loads(path.read_text('utf-8'));assert data['status']=='component_pass';components[name]=data;evidence.append(identity(path))
    assert components['G8_成本组件.json']['performance_pass']
    for path in [ROOT/'test_output/unified_edit_pipeline/g8_architecture_final01/report.json',TASK/'验收/G8_文档候选核对.json',TASK/'验收/G8_HTML终验.json']:
        data=json.loads(path.read_text('utf-8'));assert data['pass'];evidence.append(identity(path))
    visual=json.loads((TASK/'验收/G8_HTML终验.json').read_text('utf-8'));assert visual['html_sha256']==identity(ROOT/'docs/project-execution-guide.html')['sha256']
    prior={}
    for i in range(1,8):
        path=TASK/'验收'/f'G{i}_联合门.json';data=json.loads(path.read_text('utf-8'));assert data.get('pass',False) or data.get('status') in {'pass',f'G{i}_pass'} or data.get(f'G{i}_pass',False);prior[f'G{i}']=identity(path)
    path=TASK/'验收/G0_基线噪声与比较门.json';assert json.loads(path.read_text('utf-8'))['pass'];prior['G0']=identity(path)
    fixture=json.loads((ROOT/'assets/unified_edit/extensions/fixture_identity.json').read_text('utf-8'))
    for name,digest in fixture['core_before'].items():assert identity(ROOT/name)['sha256']==digest
    docs=['docs/统一沙水主流程.md','docs/unified-edit-extension-guide.md','docs/当前项目技术方案.md','docs/主场景操作.md','docs/场景切换与功能复用.md','tools/docs/build_execution_guide.py','tools/docs/build_unified_execution_guide.py']
    objectives=[]
    for i in range(8):
        for j in range(1,5):objectives.append({'id':f'T{i:02d}.{j}','status':'complete','evidence':prior[f'G{i}']})
    for j,name in [(1,'G8_功能组件.json'),(2,'G8_长稳组件.json'),(3,'G8_成本组件.json')]:objectives.append({'id':f'T08.{j}','status':'complete','evidence':identity(TASK/'验收'/name)})
    objectives.append({'id':'T08.4','status':'complete','evidence':evidence[-3:]})
    result={'schema':1,'status':'pass','date':'2026-10-18','G8_pass':True,'performance_pass':True,'overall_completed':36,'overall_total':36,'T08_completed':4,'objectives':objectives,'prior_gates':prior,'evidence':evidence,'documentation_sources':[identity(ROOT/name) for name in docs],'functional_gpu_runs':43,'functional_gpu_checks':1355,'functional_independent_checks':3379,'endurance_gpu_checks':475,'endurance_independent_checks':239,'actual_input_span_ms':180557,'lifecycle_rounds':10,'cost_runs':48,'cost_metrics':components['G8_成本组件.json']['metrics'],'cost_independent_checks':components['G8_成本组件.json']['independent_checks'],'core_unchanged_since_extension_fixtures':51,'scope':'Current unique formal backend, native lifecycle, data-only configuration extension and independent matched visible cost acceptance within the frozen G0 paused/dry/straight-input scope. Final HTML candidate bytes were actually inspected; derived final source index is checked after gate issuance.','limitations':components['G8_成本组件.json']['limitations'],'preserved_failures':['G7 first feature matrix single digest anomaly without full snapshots: cause unknown, not counted as final evidence; final captured snapshots are equal.','G8 cost pilot01 generic decorator type mismatch; own stuck process terminated after verified failure, 223 sources archived.','G8 cost final01 one old reference initialization missed its original 60-second observer allowance before inputs; raw failure excluded. Six completed detailed dig samples retained; normalized-identical 180-second observer loop completed only the remaining 42 runs.','Pilot02 first independent audit expected 24 total receipts instead of 24 samples plus controls and expected an authoring scene path despite packed flattening; original failure and exact old auditor bytes retained. Revised audit verifies actual sample IDs and consumed geometry resources.'],'derived_delivery':{'html':'docs/project-execution-guide.html','source_index':'docs/project-execution-guide.sources.json','final_audit':'task/sandcastle_unified_edit_pipeline/验收/G8_文档终核对.json','delivery_index':'task/sandcastle_unified_edit_pipeline/验收/G8_交付索引.json','note':'Final hashes are stored in the delivery index to avoid a circular hash dependency between this gate and the generated source index.'}}
    assert len(objectives)==36
    path=TASK/'验收/G8_联合门.json';assert not path.exists();path.write_text(json.dumps(result,ensure_ascii=False,indent=2),'utf-8');print('G8_GATE_PASS 36/36')
if __name__=='__main__':main()
