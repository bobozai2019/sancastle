"""Seal independently audited real input duration and lifecycle rounds."""
import hashlib
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
TASK=ROOT/'task/sandcastle_unified_edit_pipeline'
def identity(p):return {'path':p.relative_to(ROOT).as_posix(),'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
def main():
    folder=ROOT/'test_output/unified_edit_pipeline/g8_endurance01';r=json.loads((folder/'report.json').read_text('utf-8'));a=json.loads((folder/'audit.json').read_text('utf-8'));assert r['pass'] and a['pass'];d=json.loads(Path(r['runs'][0]['evidence']).read_text('utf-8'));assert d['pass'];o=d['observations']
    result={'schema':1,'status':'component_pass','date':'2026-10-18','G8_pass':False,'overall_completed':34,'overall_total':36,'T08_completed':2,'completed_subgoals':['T08.1','T08.2'],'gpu_runs':1,'gpu_checks':len(d['checks']),'independent_checks':len(a['checks']),'actual_input_span_ms':a['interaction_window_ms'],'max_input_gap_ms':a['max_input_gap_ms'],'mixed_gestures':len(o['interactions']),'real_gpu_receipts':len(o['mixed_results']),'lifecycle_rounds':len(o['rounds']),'evidence':[identity(folder/name) for name in ['report.json','audit.json','sources.zip','verification_sources.zip','artifact-index.json']],'scope':'Actual mixed declarations and water ticks followed by ten full native save/restore/formal switch/old-root close rounds. Lifecycle duration excluded from actual input span. Live fixed GPU ownership and terminal release verified; process memory includes retained observer evidence. No final cost acceptance.','remaining':['T08.3 matched visible alternating old/current cost comparison','T08.4 final unique-path/source/docs/HTML/36-goal delivery']}
    assert result['gpu_checks']==475 and result['independent_checks']==239 and result['actual_input_span_ms']>=180000 and result['lifecycle_rounds']==10
    p=TASK/'验收/G8_长稳组件.json';assert not p.exists();p.write_text(json.dumps(result,ensure_ascii=False,indent=2),'utf-8');print('G8_ENDURANCE_PASS',result['actual_input_span_ms'],result['mixed_gestures'],result['real_gpu_receipts'])
if __name__=='__main__':main()
