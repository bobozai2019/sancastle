"""Evaluate immutable raw A/A and ABBA samples against the frozen C05 limits."""
import argparse
import csv
import json
import math
from pathlib import Path
from analyze_g0_timing import percentile
ROOT=Path(__file__).resolve().parents[2]

def summarize(path):
    d=json.loads(path.read_text('utf-8-sig'));m=d['metadata'];phases={}
    for interval in m['intervals']:
        rows=[r for r in d['frames'] if r['phase']==interval['phase']]
        wall=(interval['end_us']-interval['start_us'])/1e6
        row={'samples':len(rows),'wall_s':wall,'sim_s_per_wall_s':(interval['end_sim_s']-interval['start_sim_s'])/wall,'start_tick':interval['start_tick'],'end_tick':interval['end_tick'],'focused_fraction':sum(bool(r.get('focused')) for r in rows)/len(rows) if rows else 0}
        for field in ['render_gpu_ms','frame_ms','render_cpu_ms','process_ms','physics_ms','setup_cpu_ms']:
            values=[r[field] for r in rows if isinstance(r.get(field),(int,float)) and math.isfinite(r[field])]
            row[field]={'p50':percentile(values,.5),'p95':percentile(values,.95),'nonpositive':sum(v<=0 for v in values)}
        phases[interval['phase']]=row
    status=json.loads(path.with_name('result.json').read_text('utf-8'))
    return {'metadata':{k:m[k] for k in ['engine','adapter','driver','window','viewport','vsync','max_fps','last_error','foam_variant','water_shader_sha256','contact_gain']},'phases':phases,'valid':status['exit_code']==0 and not status['source_drift'] and not status.get('fatal_log') and not m['last_error'] and all(p['samples']>=100 and p['wall_s']>=29.9 and p['render_gpu_ms']['nonpositive']==0 for p in phases.values())}

def delta(a,b,height,absolute=False):
    result={}
    for name in ['paused','live']:
        x,y=a['phases'][name],b['phases'][name]
        diff={k:y[k][p]-x[k][p] for k,p in [('render_gpu_ms','p50'),('frame_ms','p95')]}
        gpu50=y['render_gpu_ms']['p50']-x['render_gpu_ms']['p50']
        gpu95=y['render_gpu_ms']['p95']-x['render_gpu_ms']['p95']
        frame95=y['frame_ms']['p95']-x['frame_ms']['p95']
        limits={'gpu_p50_ms':.5 if height==720 else .8,'gpu_p95_ms':1.0 if height==720 else 1.5,'frame_p95_ms':max(1.0,.05*x['frame_ms']['p95'])}
        compare=abs if absolute else lambda n:n
        checks={'gpu_p50':compare(gpu50)<=limits['gpu_p50_ms'],'gpu_p95':compare(gpu95)<=limits['gpu_p95_ms'],'frame_p95':compare(frame95)<=limits['frame_p95_ms']}
        ratio=None
        if name=='live':
            ratio=y['sim_s_per_wall_s']/x['sim_s_per_wall_s']
            checks['throughput']=abs(ratio-1)<=.03 if absolute else ratio>=.97
        result[name]={'gpu_p50_delta_ms':gpu50,'gpu_p95_delta_ms':gpu95,'frame_p95_delta_ms':frame95,'throughput_ratio':ratio,'limits':limits,'checks':checks,'pass':all(checks.values())}
    return {'phases':result,'pass':a['valid'] and b['valid'] and all(p['pass'] for p in result.values())}

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--run-id',required=True);parser.add_argument('--csv',action='store_true');args=parser.parse_args()
    out=ROOT/'task/water_foam_visual/验收/G5'/args.run_id
    runs={p.parent.name:summarize(p) for p in sorted(out.glob('*/capture.json')) if p.with_name('result.json').exists()}
    groups={}
    for scene in ['main','test1_geometry']:
        for height in [720,1080]:
            prefix=f'{scene}_{height}'
            labels={label:runs.get(prefix+'_'+label) for label in ['A1','A2','B1','B2','A3']}
            if not labels['A1'] or not labels['A2']:continue
            aa=delta(labels['A1'],labels['A2'],height,True)
            terminal_aa=delta(labels['A2'],labels['A3'],height,True) if labels['A3'] else None
            pairs=[]
            for a,b in [('A2','B1'),('A3','B2')]:
                if labels[a] and labels[b]:pairs.append({'baseline':a,'candidate':b,**delta(labels[a],labels[b],height)})
            groups[prefix]={'aa':aa,'terminal_aa':terminal_aa,'ab_pairs':pairs,'complete':all(labels.values()),'pass':all(labels.values()) and aa['pass'] and terminal_aa is not None and terminal_aa['pass'] and len(pairs)==2 and all(p['pass'] for p in pairs)}
    report={'runs':runs,'groups':groups,'complete':len(runs)==20,'pass':len(groups)==4 and all(g['pass'] for g in groups.values()),'scope':'Viewport GPU render timing does not assert asynchronous compute coverage; full frame and completed simulation throughput are separately measured. Original pre-integration water shader and contact gain 1.0 versus final formal shader and gain 0.55. No optimization or automatic tuning.'}
    (out/'analysis.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    if args.csv:
        fields=['phase','us','frame_ms','process_ms','physics_ms','render_cpu_ms','render_gpu_ms','setup_cpu_ms','tick','sim_s','pending','active','ready','draw_calls','focused']
        for path in sorted(out.glob('*/capture.json')):
            document=json.loads(path.read_text('utf-8-sig'))
            with path.with_name('timings.csv').open('w',newline='',encoding='utf-8') as stream:
                writer=csv.DictWriter(stream,fields,extrasaction='ignore');writer.writeheader();writer.writerows(document['frames'])
    print(json.dumps({k:v for k,v in report.items() if k!='runs'},ensure_ascii=False,indent=2))

if __name__=='__main__':main()
