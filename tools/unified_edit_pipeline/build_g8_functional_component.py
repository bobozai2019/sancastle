"""Current frozen functional evidence only; endurance/cost remain separate."""
import hashlib
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
TASK=ROOT/'task/sandcastle_unified_edit_pipeline'
def identity(p):return {'path':p.relative_to(ROOT).as_posix(),'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
def main():
    folder=ROOT/'test_output/unified_edit_pipeline/g8_formal_frozen01';matrix=json.loads((folder/'matrix.json').read_text('utf-8'));assert matrix['pass']
    evidence=[identity(folder/name) for name in ['matrix.json','frozen.json','frozen_sources.zip']];gpu=0;runs=0;independent=0
    for group in ['formal','boundaries','remaining','completions']:
        report=json.loads((folder/group/'report.json').read_text('utf-8'));audit=json.loads((folder/group/'audit.json').read_text('utf-8'));assert report['pass'] and audit['pass'];independent+=len(audit['checks']);runs+=len(report['runs'])
        for row in report['runs']:
            d=json.loads(Path(row['evidence']).read_text('utf-8'));assert d['pass'];gpu+=len(d['checks'])
        for name in ['report.json','audit.json','sources.zip','verification_sources.zip','artifact-index.json']:
            evidence.append(identity(folder/group/name))
    for p in [folder/'remaining/independent_audit.json',ROOT/'test_output/unified_edit_pipeline/g8_static01/audit.json',ROOT/'test_output/unified_edit_pipeline/g8_retirement01/report.json']:
        data=json.loads(p.read_text('utf-8'));assert data['pass'];independent+=len(data['checks']);evidence.append(identity(p))
    assert runs==43 and gpu==1355 and independent==3379
    result={'schema':1,'status':'component_pass','date':'2026-10-18','G8_pass':False,'overall_completed':33,'overall_total':36,'T08_completed':1,'completed_subgoals':['T08.1'],'gpu_runs':runs,'gpu_checks':gpu,'independent_checks':independent,'frozen_sources':len(matrix['sources']),'evidence':evidence,'scope':'Fresh complete formal four-entry/default/service/function/fault/ownership matrix and current raw/static source verification. No historical run counted toward this component. Endurance and phase/frame cost are separate unfinished goals.','remaining':['T08.2 ten lifecycle rounds and at least three minutes actual mixed inputs','T08.3 final paired visible stage/frame cost comparison','T08.4 final source/docs/HTML/36-goal proof']}
    p=TASK/'验收/G8_功能组件.json';assert not p.exists();p.write_text(json.dumps(result,ensure_ascii=False,indent=2),'utf-8');print('G8_FUNCTIONAL_PASS',runs,gpu,independent)
if __name__=='__main__':main()
