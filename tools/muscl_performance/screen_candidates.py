"""Estimate target-cost upper bounds; sparse spans are not additive frame accounting."""
import json
from pathlib import Path
import statistics

ROOT=Path(__file__).resolve().parents[2]
EVIDENCE=ROOT/'task/muscl_performance_round2/验收'
gpu=json.loads((EVIDENCE/'diagnostic_scene_v1/diagnostic_analysis.json').read_text(encoding='utf-8'))
cpu=json.loads((EVIDENCE/'diagnostic_cpu_v1/capture.json').read_text(encoding='utf-8'))
n=gpu['valid_samples']
counts={k:v/n for k,v in gpu['audited_attempts'].items()}
def cost(kind,stage):
    return gpu['gpu_ms'].get(kind+'/'+stage,{}).get('mean',0)
whole=gpu['whole_tick_gpu_ms']['mean']
edge=sum((cost(kind,'edge_p0')+cost(kind,'edge_p1'))*counts.get(kind,0) for kind in ('accepted','rejected','invalid'))+cost('per_tick','initial')
retry=cost('rejected','edge_p0')*counts['rejected']
copies=(cost('accepted','normalize_p-1')+cost('accepted','coupled_01_p-1')+cost('accepted','coupled_08_p-1'))*counts['accepted']
records=[r['end_us']-r['start_us'] for r in cpu['diagnostic']['cpu_ticks'] if not r['sampled']]
result={'method':'Per-class selected-slot mean times mean audited count; screening upper bounds only, not additive decomposition.',
        'mean_counts_per_tick':counts,'whole_sample_gpu_ms':whole,'cpu_unsampled_record_us':statistics.mean(records),
        'cpu_n':len(records),'cpu_gpu_added':False,
        'candidates':{
            'T03':{'target_ms':edge,'fraction_gpu':edge/whole,'screen':'continue','assumption':'All edge target time removed is only an upper bound; includes initial validation bound.'},
            'T04':{'target_ms':retry,'fraction_gpu':retry/whole,'screen':'continue','assumption':'Only repeated first-stage edge after rejection; drain/euler/second stage excluded.'},
            'T05':{'target_ms':copies,'fraction_gpu':copies/whole,'screen':'architecture review','assumption':'Copies span Water and Coupled; cannot claim all can be fused while preserving ownership.'},
            'T06':{'target_cpu_us':statistics.mean(records),'fraction_cpu_upper_bound':1.0,'screen':'continue','assumption':'CPU recording interval excludes submit/publish; list-boundary fraction remains to be measured.'}},
        'limitations':['Sparse extrapolation is not a prediction of speedup or a sum to whole tick.',
                       'CPU-only run uses no GPU timestamp/snapshot sampling; CPU timeline remains attached.',
                       'GPU and CPU data come from separate controlled modes and must not be added.',
                       'Normal-window FPS thresholds use independent A/B after numerical gates.']}
(EVIDENCE/'candidate_screening.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps(result,indent=2))
