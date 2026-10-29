"""Inspect CPU/native Unity clocks and substep accumulation without accepting G4."""
import argparse
import collections
import json
import math
import shutil
from pathlib import Path
from audit_runtime_pilot import water_events,closure,property_value
from evidence_contract import identity

def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--runs',nargs='+',required=True,type=Path);ap.add_argument('--output',required=True,type=Path);args=ap.parse_args();out=args.output.resolve()
    if not str(out).isascii():raise ValueError('ASCII output required')
    out.mkdir(parents=True,exist_ok=False)
    for name in ['audit_clock_samples.py','audit_runtime_pilot.py','evidence_contract.py']:shutil.copyfile(Path(__file__).parent/name,out/name)
    reports=[]
    for run in args.runs:
        events=water_events(json.loads((run/'logs/events.json').read_text()));stats=json.loads((run/'observer_final.json').read_text());errors=closure(events,stats);calls=[e for e in events if e['kind']=='dispatch_enter'];dispatch={e['call_id']:e for e in calls};clocks=[e for e in events if e['kind']=='engine_clock_sample'];pairs=[]
        for c in clocks:
            d=dispatch[c['call_id']];v=c['values'];pairs.append(dict(call_id=c['call_id'],source_call_index=c['source_call_index'],source_dispatch_seq=d['seq'],clock_seq=c['seq'],source_qpc=d['qpc'],clock_begin_qpc=c['begin_qpc'],clock_end_qpc=c['qpc'],getter_bracket_ms=(int(c['qpc'])-int(c['begin_qpc']))/10000,values=v,source_dt=property_value(d,'deltaTime'),shader_time=property_value(d,'time','global_parameters'),shader_playTime=property_value(d,'playTime','global_parameters'),shader_frameCount=property_value(d,'frameCount','global_parameters'),dt_matches=v.get('get_fixedDeltaTime')==property_value(d,'deltaTime'),time_matches=v.get('get_time')==property_value(d,'time','global_parameters'),frame_matches=v.get('get_frameCount')==property_value(d,'frameCount','global_parameters'),fixed_time_matches=v.get('get_time')==v.get('get_fixedTime') if 'get_fixedTime' in v else None))
        if any(not p['dt_matches'] or not p['time_matches'] or not p['frame_matches'] for p in pairs):errors.append('CLOCK_SAMPLE_MISMATCH')
        if not pairs:errors.append('NO_NATIVE_CLOCK_SAMPLES')
        accumulation=[];current=[];total=0.0;count=0;round_total=0;substeps=set();source_steps=set();stages=[]
        for d in calls:
            n=d['kernel_name']
            if n=='UpdateFloor':current=[];stages=[]
            elif n in ['VelocityIntegration','HeightIntegration','Advection']:
                stages.append(n)
                if n=='VelocityIntegration':current.append(property_value(d,'deltaTime'))
            elif n=='UpdateAmount':
                count+=1;source_dt=property_value(d,'deltaTime');source_steps.add(source_dt);substeps.update(current)
                if stages!=['VelocityIntegration','HeightIntegration','Advection']*len(current) or not current:errors.append('SOURCE_CHAIN_NOT_CLOSED')
                total+=sum(current);round_total+=len(current)
                expected=math.floor(count*source_dt/current[0]) if len(set(current))==1 and source_dt is not None else None
                accumulation.append(dict(source_call_index=count,call_id=d['call_id'],rounds=len(current),cumulative_rounds=round_total,predicted_floor_rounds=expected,residual_seconds=total-count*source_dt,prediction_matches=round_total==expected))
        fingerprint_errors=[];manifest=json.loads((run/'manifest.json').read_text())
        for expected in manifest['artifacts']:
            actual=identity(expected['path'])
            if actual['sha256']!=expected['sha256'] or actual['size_bytes']!=expected['size_bytes']:fingerprint_errors.append(expected['path'])
        if fingerprint_errors:errors.append('ARTIFACT_IDENTITY_MISMATCH')
        report=dict(run=run.as_posix(),source=identity(run/'manifest.json'),verification_status='partial',scope='Observed native clock fields and cumulative-count correspondence; no formal G03/G4 or uninstrumented frequency acceptance',observer_stats=stats,clock_samples=pairs,public_signature_resolutions=[e for e in events if e['kind']=='clock_getter_public_resolution'],unavailable_getters=[e for e in events if e['kind']=='clock_getter_unavailable'],observed_values={k:sorted({p['values'][k] for p in pairs if k in p['values']}) for k in ['get_deltaTime','get_fixedDeltaTime','get_timeScale','get_maximumDeltaTime','get_inFixedTimeStep']},getters_max_bracket_ms=max((p['getter_bracket_ms'] for p in pairs),default=None),accumulation_summary=dict(source_calls=count,integration_dt_values=sorted(substeps),source_dt_values=sorted(source_steps),residual_min_seconds=min((x['residual_seconds'] for x in accumulation),default=None),residual_max_seconds=max((x['residual_seconds'] for x in accumulation),default=None),floor_count_mismatches=sum(not x['prediction_matches'] for x in accumulation),interpretation='Exact observed prefix count correspondence supports an accumulator model; does not recover the original scheduling implementation or prove all reset/input cases'),accumulation=accumulation,artifact_identity_errors=fingerprint_errors,errors=errors)
        reports.append(report);(out/(run.name+'.json')).write_text(json.dumps(report,indent=2),encoding='utf-8')
    (out/'manifest.json').write_text(json.dumps(dict(operation_status='complete',verification_status='partial',errors=[dict(run=r['run'],errors=r['errors']) for r in reports if r['errors']],artifacts=[identity(p) for p in out.iterdir() if p.is_file()]),indent=2),encoding='utf-8')
    print(json.dumps([dict(run=Path(r['run']).name,samples=len(r['clock_samples']),observed=r['observed_values'],accumulation=r['accumulation_summary'],errors=r['errors']) for r in reports]))

if __name__=='__main__':main()
