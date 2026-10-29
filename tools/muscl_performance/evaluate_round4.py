"""Frozen C5 engineering decision; numerical gates are separate prerequisites."""
import argparse
import json
import math
from pathlib import Path
import statistics


def metric(value):
    a,b=value.get('a',[]),value.get('b',[])
    if len(a)!=2 or len(b)!=2 or any(not isinstance(x,(int,float)) or not math.isfinite(x) or x<=0 for x in a+b):
        return None
    noise=abs(a[0]-a[1])/statistics.mean(a)
    gain=1-statistics.mean(b)/statistics.mean(a)
    paired=[1-y/x for x,y in zip(a,b)]
    return {'a':a,'b':b,'noise':noise,'mean_gain':gain,'paired_gains':paired,
            'both_improve':all(x>0 for x in paired),'both_regress':all(x<0 for x in paired),
            'regression_limit':max(.02,noise)}


def decide(scene,cost,expected_sources):
    reasons=[];unknown=[];channels={};wins=[];regressions=[]
    for label,report in [('scene',scene),('cost',cost)]:
        if not report.get('valid_identities'):unknown.append(label+':invalid_identities')
        if set(report.get('source_differences',[]))!=set(expected_sources):unknown.append(label+':unexpected_source_union')
        if len(report.get('progress',[]))!=2:unknown.append(label+':missing_progress_pairs')
        for row in report.get('progress',[]):
            if abs(row['ratio_change'])>row['endpoint_bound']+1e-12:unknown.append(label+':progress_not_equivalent:'+row['a'])
        names=['frame_mean_ms','frame_p95_ms','frame_p99_ms','viewport_gpu_ms','render_cpu_ms']
        if label=='cost':names+=['gpu_ms_per_sim_s','cpu_record_us']
        for name in names:
            key=label+':'+name;row=metric(report.get('metrics',{}).get(name,{}));channels[key]=row
            if row is None:unknown.append(key+':missing_or_invalid');continue
            if row['both_regress'] and -row['mean_gain']>row['regression_limit']:regressions.append(key)
    for key,floor in [('scene:viewport_gpu_ms',.05),('cost:gpu_ms_per_sim_s',.05),('cost:cpu_record_us',.10)]:
        row=channels.get(key)
        if row is not None:
            row['required_gain']=max(floor,row['noise'])
            if row['both_improve'] and row['mean_gain']>=row['required_gain']:wins.append(key)
    if not wins:reasons.append('no_reliable_gain_meets_C5')
    if regressions:reasons.append('major_channel_regression')
    decision='uncertain' if unknown else ('retain_full_B' if wins and not regressions else 'withdraw_full_B')
    return {'decision':decision,'eligible_metrics':wins,'regressions':regressions,'unknown':unknown,'reasons':reasons,'channels':channels,
            'policy':'GPU/root viewport >=max(5%,A noise) or CPU record >=max(10%,A noise), both paired directions positive; every measured major channel rejects two-pair mean regression >max(2%,A noise). Actual progress within predeclared endpoint bounds. No statistical-confidence claim.'}


def selfcheck():
    def fixture():
        metrics={name:{'a':[100,100],'b':[100,100]} for name in ['frame_mean_ms','frame_p95_ms','frame_p99_ms','viewport_gpu_ms','render_cpu_ms','gpu_ms_per_sim_s','cpu_record_us']}
        return {'valid_identities':True,'source_differences':['state.gd'],'progress':[{'a':name,'ratio_change':0,'endpoint_bound':.01} for name in ['a1','a2']],'metrics':metrics}
    checks={};s,c=fixture(),fixture();checks['no_gain_withdraws']=decide(s,c,['state.gd'])['decision']=='withdraw_full_B'
    c['metrics']['gpu_ms_per_sim_s']['b']=[94,94];checks['gpu_6pct_retains']=decide(s,c,['state.gd'])['decision']=='retain_full_B'
    s['metrics']['frame_p99_ms']['b']=[103,103];checks['frame_3pct_rejects']=decide(s,c,['state.gd'])['decision']=='withdraw_full_B'
    s,c=fixture(),fixture();c['metrics']['cpu_record_us']['b']=[91,91];checks['cpu_9pct_rejects']=decide(s,c,['state.gd'])['decision']=='withdraw_full_B'
    c['metrics']['cpu_record_us']['b']=[89,89];checks['cpu_11pct_retains']=decide(s,c,['state.gd'])['decision']=='retain_full_B'
    c['metrics']['cpu_record_us']['b']=[70,101];checks['opposing_pairs_reject']=decide(s,c,['state.gd'])['decision']=='withdraw_full_B'
    c['metrics']['cpu_record_us']['b']=[89,89];s['metrics']['viewport_gpu_ms']['b']=[None,None];checks['missing_gpu_unknown']=decide(s,c,['state.gd'])['decision']=='uncertain'
    s,c=fixture(),fixture();c['metrics']['gpu_ms_per_sim_s']={'a':[96,104],'b':[94,94]};checks['noise_above_gain_rejects']=decide(s,c,['state.gd'])['decision']=='withdraw_full_B'
    c['progress'][0]['ratio_change']=.02;checks['less_work_not_gain']=decide(s,c,['state.gd'])['decision']=='uncertain'
    s,c=fixture(),fixture();c['source_differences'].append('new.glsl');checks['unexpected_new_source_rejects']=decide(s,c,['state.gd'])['decision']=='uncertain'
    return {'pass':all(checks.values()),'checks':checks,'scope':'Synthetic decision negative controls, not performance evidence'}


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--scene',type=Path);p.add_argument('--cost',type=Path);p.add_argument('--candidate',type=Path);p.add_argument('--output',type=Path,required=True);p.add_argument('--selfcheck',action='store_true');a=p.parse_args()
    if a.output.exists():raise SystemExit('Fresh output required')
    if a.selfcheck:result=selfcheck()
    else:
        result=decide(json.loads(a.scene.read_text('utf-8')),json.loads(a.cost.read_text('utf-8')),json.loads(a.candidate.read_text('utf-8'))['files'])
    a.output.write_text(json.dumps(result,indent=2),'utf-8');print(json.dumps(result,indent=2))
    raise SystemExit(1 if a.selfcheck and not result['pass'] else 0)
