"""Report independently judged paired costs without upgrading other gates."""
import argparse
import hashlib
import json
from pathlib import Path
import statistics
ROOT=Path(__file__).resolve().parents[2]
TASK=ROOT/'task/sandcastle_unified_edit_pipeline'
def identity(p):return {'path':p.relative_to(ROOT).as_posix(),'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
def main():
    parser=argparse.ArgumentParser();parser.add_argument('joint',type=Path);args=parser.parse_args();folder=args.joint.resolve();r=json.loads((folder/'report.json').read_text('utf-8'));a=json.loads((folder/'audit.json').read_text('utf-8'));seal=json.loads((folder/'seal.json').read_text('utf-8'));assert r['pass'] and a['pass'] and a['performance_pass'] and seal['pass'] and len(r['runs'])==48
    metrics={}
    for tool in ['dig','fill','wall','shovel']:
        pairs=[p for p in a['pairs'] if p['mode']=='coarse' and p['tool']==tool];assert len(pairs)==3
        detailed=[p for p in a['pairs'] if p['mode']=='detailed' and p['tool']==tool]
        metrics[tool]={'old_coarse_p50_ms':[p['old_input_frame_p50_ms'] for p in pairs],'current_coarse_p50_ms':[p['current_input_frame_p50_ms'] for p in pairs],'old_coarse_median_of_p50_ms':statistics.median(p['old_input_frame_p50_ms'] for p in pairs),'current_coarse_median_of_p50_ms':statistics.median(p['current_input_frame_p50_ms'] for p in pairs),'frozen_guard_ms':pairs[0]['frozen_guard_ms'],'judgment':a['judgments'][tool],'old_tagged_gpu_ms_per_command':[p['old_tagged_gpu_ms_per_command'] for p in detailed],'current_complete_executor_gpu_ms_per_command':[p['current_complete_executor_gpu_ms_per_command'] for p in detailed]}
    evidence=[identity(folder/name) for name in ['report.json','audit.json','seal.json','sources.zip','artifact-index.json']]
    result={'schema':1,'status':'component_pass','date':'2026-10-18','G8_pass':False,'performance_pass':True,'overall_completed':35,'overall_total':36,'T08_completed':3,'completed_subgoals':['T08.1','T08.2','T08.3'],'cost_runs':48,'independent_checks':len(a['checks']),'metrics':metrics,'evidence':evidence,'excluded_failed_starts':r['excluded_failed_starts'],'scope':'Same eleven initial raw fields/camera/grid/visual values/current water-side geometry; three alternating pairs for each of four tools in detailed and coarse modes. Coarse input-window P50 judged independently using frozen G0 guards. Exact input declarations and actual real GPU terminals checked.','limitations':['P99 remains unknown per condition because each has fewer than 1000 input intervals.','CPU notification bounds are not GPU elapsed time, first visible pixels or display scanout.','Old GPU tagged sums omit untagged dispatch work; current decorator records the whole unchanged executor. No exact whole-CPU gain is asserted.','Original and current product HUD layouts differ; actual primitives/draw-call counts are retained. Full 3D scene/effects were preserved and no numerical precision or workload was lowered.','User editor PID23948 remains present; no isolated GPU claim.'],'remaining':['T08.4 final current architecture/source/docs/HTML/36-goal delivery']}
    p=TASK/'验收/G8_成本组件.json';assert not p.exists();p.write_text(json.dumps(result,ensure_ascii=False,indent=2),'utf-8');print('G8_COST_PASS',metrics)
if __name__=='__main__':main()
