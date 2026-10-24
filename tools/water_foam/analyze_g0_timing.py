"""Report raw viewport/frame percentiles and A/A noise; never infer a pass."""
import argparse
import csv
import json
import math
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'task/water_foam_visual/验收/G0/timing_20261024'

def percentile(values,p):
    values=sorted(values)
    if not values:return None
    at=(len(values)-1)*p
    low=int(at)
    return values[low]+(values[math.ceil(at)]-values[low])*(at-low)

def main():
    global OUT
    parser=argparse.ArgumentParser()
    parser.add_argument('--run-id',default='timing_20261024')
    args=parser.parse_args()
    OUT=OUT.parent/args.run_id
    if not OUT.is_dir():raise SystemExit('Run directory missing')
    runs={}
    for file in sorted(OUT.glob('*/capture.json')):
        d=json.loads(file.read_text(encoding='utf-8-sig'))
        m=d['metadata']
        phases={}
        for interval in m['intervals']:
            rows=[r for r in d['frames'] if r['phase']==interval['phase']]
            wall=(interval['end_us']-interval['start_us'])/1e6
            phase=dict(sample_count=len(rows),wall_s=wall,sim_s_per_wall_s=(interval['end_sim_s']-interval['start_sim_s'])/wall)
            for field in ['render_gpu_ms','frame_ms','render_cpu_ms']:
                values=[r[field] for r in rows if isinstance(r.get(field),(int,float)) and math.isfinite(r[field])]
                phase[field]={f'p{int(p*100)}':percentile(values,p) for p in [.5,.95]}
                phase[field]['nonpositive_count']=sum(v<=0 for v in values)
            phase['focused_fraction']=sum(bool(r.get('focused')) for r in rows)/len(rows) if rows else None
            phase['viewport_gpu_valid']=bool(rows) and phase['render_gpu_ms']['nonpositive_count']==0
            phases[interval['phase']]=phase
            with file.with_name(interval['phase']+'.csv').open('w',newline='',encoding='utf-8') as f:
                keys=['us','phase','tick','sim_s','frame_ms','render_gpu_ms','render_cpu_ms','focused','draw_calls']
                writer=csv.DictWriter(f,keys,extrasaction='ignore');writer.writeheader();writer.writerows(rows)
        status_path=file.with_name('result.json')
        status=json.loads(status_path.read_text(encoding='utf-8')) if status_path.exists() else None
        provenance='unverified' if status is None or 'source_drift' not in status else ('drifted' if status['source_drift'] else 'stable')
        runs[file.parent.name]=dict(phases=phases,window=m['window'],viewport=m['viewport'],engine=m['engine'],adapter=m['adapter'],driver=m['driver'],vsync=m['vsync'],last_error=m['last_error'],source_provenance=provenance,process_result=status)
    pairs={}
    for name,first in runs.items():
        if not name.endswith('_A1'):continue
        second=runs.get(name[:-1]+'2')
        if not second:continue
        delta={}
        for phase in first['phases']:
            a=first['phases'][phase];b=second['phases'][phase]
            delta[phase]={field:{p:b[field][p]-a[field][p] for p in ['p50','p95']} for field in ['frame_ms','render_gpu_ms','render_cpu_ms']}
            delta[phase]['throughput_ratio']=b['sim_s_per_wall_s']/a['sim_s_per_wall_s'] if a['sim_s_per_wall_s'] else None
        pairs[name[:-3]]=delta
    result=dict(runs=runs,aa_deltas=pairs,expected_runs=8,completed_runs=len(runs),gate_status='not_evaluated',note='Viewport GPU render timing excludes a claim about asynchronous compute. Sampling identical A twice measures noise; no candidate measured, no performance pass asserted.')
    (OUT/'analysis.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(result,ensure_ascii=False,indent=2))

if __name__=='__main__':main()
