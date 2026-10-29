"""Audit pilot trace closure and report CPU observations without GPU/time acceptance."""
import argparse
import collections
import datetime
import json
import shutil
from pathlib import Path
from evidence_contract import identity

def property_value(dispatch,name,scope='parameters'):
    return next((v.get('value') for v in dispatch.get(scope,{}).values() if v.get('property')==name),None)


def water_events(raw):
    """Resolve schema 2 preceding immutable snapshots; legacy schema 1 stays intact."""
    events=[e for row in raw if row.get('payload',{}).get('kind')=='water_trace' for e in row['payload']['events']]
    schemas={e.get('trace_schema','1.0') for e in events if e['kind']=='observer_loaded'}
    if len(schemas)>1 or any(v not in ['1.0','2.0'] for v in schemas):raise ValueError('TRACE_SCHEMA_UNSUPPORTED')
    version=next(iter(schemas),'1.0');snapshots={}
    for index,event in enumerate(events):
        if event['kind']=='state_snapshot':
            key=event['snapshot_id']
            if type(key) is not int or key<=0 or event['scope'] not in ['parameters','bindings','global_parameters'] or not isinstance(event['values'],dict):raise ValueError('SNAPSHOT_INVALID')
            if key in snapshots:raise ValueError('SNAPSHOT_ID_REUSED:'+str(key))
            snapshots[key]=event
        elif event['kind']=='dispatch_enter':
            if version=='2.0' and 'state_refs' not in event:raise ValueError('SNAPSHOT_REFS_MISSING')
            if 'state_refs' not in event:continue
            if set(event['state_refs'])!={'parameters','bindings','global_parameters'}:raise ValueError('SNAPSHOT_REFS_INCOMPLETE')
            expanded={**event}
            for scope,key in event['state_refs'].items():
                if scope not in ['parameters','bindings','global_parameters']:raise ValueError('UNKNOWN_STATE_SCOPE:'+scope)
                if key not in snapshots:raise ValueError('SNAPSHOT_NOT_PRECEDING:'+str(key))
                snapshot=snapshots[key]
                if snapshot['scope']!=scope or (scope!='global_parameters' and snapshot['key']!=event['shader']):raise ValueError('SNAPSHOT_SCOPE_MISMATCH:'+str(key))
                expanded[scope]=snapshot['values']
            events[index]=expanded
    return events

def closure(events,stats):
    ids=[e['seq'] for e in events];errors=[]
    if not stats:return ['NO_FINAL_STATS']
    if stats['dropped']:errors.append('LOG_DROPPED')
    if stats['errors']:errors.append('HOOK_ERRORS')
    if stats['inflight']:errors.append('INFLIGHT_CALLS')
    if any(e['kind'] in ['water_hooks_detached','water_hooks_reattached'] for e in events):errors.append('DIAGNOSTIC_TRACE_GAP')
    if ids!=list(range(1,stats['last_seq']+1)) or len(events)!=stats['events']:errors.append('SEQUENCE_NOT_CLOSED')
    enter=[e['call_id'] for e in events if e['kind']=='dispatch_enter'];leave=[e['call_id'] for e in events if e['kind']=='dispatch_return']
    if len(set(enter))!=len(enter) or collections.Counter(enter)!=collections.Counter(leave) or len(enter)!=stats['dispatches']:errors.append('CALLS_NOT_CLOSED')
    return errors

def audit(run):
    manifest=json.loads((run/'manifest.json').read_text())
    raw=json.loads((run/'logs/events.json').read_text());events=water_events(raw)
    stats_path=run/'observer_final.json';stats=json.loads(stats_path.read_text()) if stats_path.exists() else None
    errors=closure(events,stats) if events else ['NO_WATER_TRACE']
    artifact_errors=[]
    for expected in manifest['artifacts']:
        actual=identity(expected['path'])
        if actual['sha256']!=expected['sha256'] or actual['size_bytes']!=expected['size_bytes']:artifact_errors.append(expected['path'])
    dispatch=[e for e in events if e['kind']=='dispatch_enter'];kinds=collections.Counter(e['kind'] for e in events)
    frequencies={e['qpc_frequency'] for e in events if e['kind'] in ['observer_loaded','observer_installed']}
    if len(frequencies)!=1 and events:errors.append('QPC_FREQUENCY_NOT_CLOSED')
    frequency=int(next(iter(frequencies))) if len(frequencies)==1 else None
    cycles=[];current=None;partial=[]
    for d in dispatch:
        n=d['kernel_name']
        if n=='UpdateFloor':
            if current:partial.append(current)
            current={'start_seq':d['seq'],'start_qpc':d['qpc'],'shader':d['shader'],'stages':[n],'frameCount_start':property_value(d,'frameCount','global_parameters')}
        elif current:
            current['stages'].append(n)
            if n=='UpdateAmount':current.update(source_seq=d['seq'],source_qpc=d['qpc'],source_dt=property_value(d,'deltaTime'),playTime=property_value(d,'playTime','global_parameters'),frameCount_source=property_value(d,'frameCount','global_parameters'))
            if n=='UpdateTangent':
                current['end_seq']=d['seq'];current['end_qpc']=d['qpc'];middle=current['stages'][1:-2]
                valid='source_seq' in current and current['stages'][-2]=='UpdateAmount' and len(middle)%3==0 and middle==['VelocityIntegration','HeightIntegration','Advection']*(len(middle)//3)
                current['ordered_triples']=valid;current['rounds']=len(middle)//3 if valid else None
                cycles.append(current);current=None
    if current:partial.append(current)
    valid=[c for c in cycles if c['ordered_triples'] and c['rounds']>0]
    frames=collections.Counter(c['frameCount_source'] for c in valid if c.get('frameCount_source') is not None)
    params=[]
    for kernel in sorted({d['kernel_name'] for d in dispatch}):
        rows=[d for d in dispatch if d['kernel_name']==kernel]
        params.append(dict(kernel=kernel,count=len(rows),deltaTime_values=dict(collections.Counter(str(property_value(d,'deltaTime')) for d in rows)),groups=dict(collections.Counter(str(d['groups']) for d in rows))))
    clock=None
    timed=[c for c in valid if isinstance(c.get('playTime'),(int,float))]
    if len(timed)>1 and frequency:
        first,last=timed[0],timed[-1];wall=(int(last['source_qpc'])-int(first['source_qpc']))/frequency
        clock=dict(first=first,last=last,cpu_entry_elapsed_seconds=wall,shader_playTime_delta=last['playTime']-first['playTime'],endpoint_ratio=(last['playTime']-first['playTime'])/wall if wall else None,meaning='Pilot CPU snapshots only; not a frozen clock mapping, Present cadence, GPU completion, or observer-free rate')
    redirects=[x['payload'] for x in raw if x.get('payload',{}).get('kind')=='isolation_path_redirect']
    return dict(run=run.as_posix(),manifest=identity(run/'manifest.json'),operation_status=manifest['operation_status'],source_and_watched_user_unchanged=manifest['watched_source_and_user_data_unchanged'],artifact_identity_errors=artifact_errors,observer_stats=stats,trace_errors=errors,trace_closed=bool(events) and not errors,event_counts=dict(kinds),qpc_frequency=frequency,parameter_observations=params,cycle_count=len(cycles),valid_positive_round_cycles=len(valid),round_distribution=dict(collections.Counter(str(c['rounds']) for c in valid)),shader_global_frameCount_cycles=dict(collections.Counter(str(n) for n in frames.values())),partial_cycles=len(partial),clock_pilot=clock,path_redirect_count=len(redirects),redirects=redirects,hook_coverage=[e for e in events if e['kind'] in ['hook_installed','hook_alias_skipped','coverage_limit']],unaccepted=['GPU constant correspondence','DXBC identity correspondence','No-observer/light/capture perturbation','Window D07','Full API and command-buffer lifecycle coverage'])

def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--runs',nargs='+',required=True,type=Path);ap.add_argument('--output',required=True,type=Path);args=ap.parse_args()
    out=args.output.resolve()
    if not str(out).isascii():raise ValueError('ASCII output required')
    out.mkdir(parents=True,exist_ok=False);shutil.copyfile(__file__,out/'audit_runtime_pilot.py')
    reports=[audit(r.resolve()) for r in args.runs]
    for report in reports:(out/(Path(report['run']).name+'.json')).write_text(json.dumps(report,indent=2),encoding='utf-8')
    latest=reports[-1]
    (out/'runtime_setup.json').write_text(json.dumps(dict(run=latest['run'],source_and_watched_user_unchanged=latest['source_and_watched_user_unchanged'],path_redirect_count=latest['path_redirect_count'],scope='Process-local guard and explicit watched paths; not an OS sandbox or all-process audit',ready_for_G01=False),indent=2),encoding='utf-8')
    (out/'hook_coverage.json').write_text(json.dumps(dict(run=latest['run'],trace_closed=latest['trace_closed'],coverage=latest['hook_coverage'],remaining=latest['unaccepted']),indent=2),encoding='utf-8')
    manifest=dict(operation_status='complete',verification_status='partial',created_at=datetime.datetime.now(datetime.timezone.utc).isoformat(),scope='Retrospective pilot audit, not G4',runs=[r['manifest'] for r in reports],artifacts=[identity(p) for p in out.iterdir() if p.is_file()])
    (out/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
    print(json.dumps([dict(run=Path(r['run']).name,trace_closed=r['trace_closed'],errors=r['trace_errors'],artifact_errors=len(r['artifact_identity_errors']),cycles=r['valid_positive_round_cycles'],rounds=r['round_distribution']) for r in reports]))

if __name__=='__main__':main()
