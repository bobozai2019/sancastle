"""Describe bounded activation costs and A/A drift without upgrading previous Gates."""
from pathlib import Path
import argparse,json,statistics
p=argparse.ArgumentParser();p.add_argument('folder',type=Path);args=p.parse_args()
def quantile(values,q):
    ordered=sorted(values)
    return ordered[min(len(ordered)-1,int((len(ordered)-1)*q))]
records=[];identity=None
for scene in ['main','test1_geometry']:
    for label in ['A1','B1','B2','A2']:
        folder=args.folder/(scene+'_'+label)
        result=json.loads((folder/'result.json').read_text('utf-8'))
        capture=json.loads((folder/'capture.json').read_text('utf-8'))
        sources=json.loads((folder/'sources_after.json').read_text('utf-8'))
        if identity is None:identity=sources
        assert identity==sources
        m=capture['metadata']
        row={'scene':scene,'label':label,'enabled':m['splash_variant']=='enabled','result':result,'phases':{},'props_errors':[m['props_error_before'],m['props_error_after']],'window':m['window'],'vsync':m['vsync']}
        for interval in m['intervals']:
            name=interval['phase'];frames=[f for f in capture['frames'] if f['phase']==name]
            elapsed=(interval['end_us']-interval['start_us'])/1e6
            row['phases'][name]={'seconds':elapsed,'frames':len(frames),'frame_p50_ms':quantile([f['frame_ms'] for f in frames],.5),'frame_p95_ms':quantile([f['frame_ms'] for f in frames],.95),'viewport_gpu_p50_ms':quantile([f['render_gpu_ms'] for f in frames],.5),'viewport_gpu_p95_ms':quantile([f['render_gpu_ms'] for f in frames],.95),'simulation_seconds_per_wall_second':(interval['end_sim_s']-interval['start_sim_s'])/elapsed,'focused_fraction':statistics.mean(float(f['focused']) for f in frames),'draw_calls_p50':quantile([f['draw_calls'] for f in frames],.5)}
        row['valid']=result['exit_code']==0 and not result['source_drift'] and not result['fatal_log'] and not any(row['props_errors']) and all(x['seconds']>=12 and x['frames']>=100 and x['focused_fraction']>=.95 for x in row['phases'].values())
        records.append(row)
summary={'scope':'720p bounded off/on/on/off activation comparison, 3s warmup +12s each paused/live; common authored empty pool/mesh vertex and node costs remain in off runs. Viewport GPU excludes asynchronous compute. Not a full cost acceptance or update to historical foam Gates.','all_valid':all(r['valid'] for r in records),'same_source_identities':True,'records':records,'comparisons':[]}
lines=['# 冲岸水花成本观察','','同一最终来源，1280×720、原VSync、完整场景，A为启动关闭计算，B为开启；顺序A1/B1/B2/A2。每阶段3秒预热、12秒墙钟采样。A仍保留同样的空池与静态节点，差值不包含其共同的固定顶点/节点成本；视口GPU不代表全部异步计算。此短对照不升级此前泡沫性能门。','', '| 场景 | 暂停GPU P50：A / B ms | 实时帧P95：A / B ms | 模拟秒/墙钟秒：A / B |','|---|---|---|---|']
for scene in ['main','test1_geometry']:
    rows=[r for r in records if r['scene']==scene]
    off=[r for r in rows if not r['enabled']];on=[r for r in rows if r['enabled']]
    def values(rs,phase,metric):return [r['phases'][phase][metric] for r in rs]
    def fmt(rs,phase,metric):return ', '.join(f'{x:.3f}' for x in values(rs,phase,metric))
    lines.append(f'| {scene} | {fmt(off,"paused","viewport_gpu_p50_ms")} / {fmt(on,"paused","viewport_gpu_p50_ms")} | {fmt(off,"live","frame_p95_ms")} / {fmt(on,"live","frame_p95_ms")} | {fmt(off,"live","simulation_seconds_per_wall_second")} / {fmt(on,"live","simulation_seconds_per_wall_second")} |')
    a1,a2=off
    aa_frame=abs(a2['phases']['live']['frame_p95_ms']-a1['phases']['live']['frame_p95_ms'])
    aa_throughput=a2['phases']['live']['simulation_seconds_per_wall_second']/a1['phases']['live']['simulation_seconds_per_wall_second']-1
    summary['comparisons'].append({'scene':scene,'off_aa_live_frame_p95_spread_ms':aa_frame,'off_aa_live_throughput_relative_change':aa_throughput})
invalid=[r['scene']+' '+r['label'] for r in records if not r['valid']]
if invalid:lines+=['','无效样本：'+', '.join(invalid)+'。原始数值保留在上表，但不纳入性能结论；test1_geometry B2在采样中失去窗口焦点。']
lines+=['','原始样本及焦点、道具错误、窗口时长检查见analysis.json。A/A自身变化与B样本散布共同限制成本归因；不将单个较好样本当作稳定性能保证。']
(args.folder/'analysis.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),'utf-8')
(args.folder/'成本观察.md').write_text('\n'.join(lines)+'\n','utf-8')
print(json.dumps({'all_valid':summary['all_valid'],'comparisons':summary['comparisons']},ensure_ascii=False))
