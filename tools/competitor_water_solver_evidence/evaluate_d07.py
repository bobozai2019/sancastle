"""Evaluate predeclared D07 calibration bounds; diagnostic data never becomes a trajectory."""
import argparse
import collections
import json
import shutil
from pathlib import Path
from audit_runtime_modes import metrics
from audit_runtime_pilot import water_events,closure
from evidence_contract import identity

def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--run',required=True,type=Path);ap.add_argument('--criteria',required=True,type=Path);ap.add_argument('--output',required=True,type=Path);args=ap.parse_args();out=args.output.resolve()
    if not str(out).isascii():raise ValueError('ASCII output required')
    out.mkdir(parents=True,exist_ok=False)
    for name in ['evaluate_d07.py','audit_runtime_modes.py','audit_runtime_pilot.py','evidence_contract.py']:shutil.copyfile(Path(__file__).parent/name,out/name)
    shutil.copyfile(args.criteria,out/'criteria.json');criteria=json.loads(args.criteria.read_text());cfg=criteria['calibration'];raw=json.loads((args.run/'logs/events.json').read_text());manifest=json.loads((args.run/'manifest.json').read_text());mode=json.loads((args.run/'mode.json').read_text());events=[e for row in raw if row.get('payload',{}).get('kind')=='presentation_trace' for e in row['payload']['events']];water=water_events(raw);ws=json.loads((args.run/'observer_final.json').read_text());ps=json.loads((args.run/'presentation_final.json').read_text());errors=[]
    water_errors=closure(water,ws)
    if water_errors!=['DIAGNOSTIC_TRACE_GAP']:errors.append('DIAGNOSTIC_LOG_CLOSURE:'+str(water_errors))
    if mode.get('formal_eligible') is not False:errors.append('DIAGNOSTIC_TRAJECTORY_NOT_MARKED_UNUSABLE')
    if mode.get('clock_sample_every')!=criteria['recording']['clock_sample_every']:errors.append('CLOCK_SAMPLING_CONFIG_MISMATCH')
    if mode.get('native_scalars',False)!=criteria['recording'].get('native_scalars',False):errors.append('SCALAR_BACKEND_MISMATCH')
    if criteria['recording'].get('native_scalars') and (not ws.get('native_scalar') or ws['native_scalar']['overflow']):errors.append('NATIVE_SCALAR_CACHE_NOT_CLOSED')
    if mode.get('shadow_every')!=0:errors.append('SHADOW_NOT_DISABLED')
    if [e['seq'] for e in events]!=list(range(1,ps['last_seq']+1)) or ps['dropped'] or ps['errors'] or ps['inflight']:errors.append('PRESENT_LOG_NOT_CLOSED')
    present=[e for e in events if e['kind']=='present_enter'];returns=[e for e in events if e['kind']=='present_return']
    if collections.Counter(e['call_id'] for e in present)!=collections.Counter(e['call_id'] for e in returns):errors.append('PRESENT_CALLS_NOT_PAIRED')
    if any(e['hresult']!=0 for e in returns):errors.append('PRESENT_NOT_SUCCESS')
    freq=int(next(e['qpc_frequency'] for e in events if e['kind']=='loaded'));epoch=int(next(e['marker_qpc'] for e in events if e['kind']=='host_marker' and e['label']=='before_resume'))
    states=[e for e in events if e['kind']=='window_state'];dimensions=[e for e in events if e['kind'] in ['swapchain','swapchain_resize'] and e.get('description_result')==0];windows=[];all_on=[];all_off=[]
    for index,window in enumerate(cfg['windows_from_before_resume_qpc_seconds']):
        lo=epoch+int(window['begin']*freq);hi=epoch+int(window['end']*freq);samples=[e for e in states if lo<=int(e['qpc'])<=hi];before=[e for e in states if int(e['qpc'])<lo];after=[e for e in states if int(e['qpc'])>hi];coverage=([before[-1]] if before else [])+samples+([after[0]] if after else []);issues=[]
        gap=max(((int(b['qpc'])-int(a['qpc']))/freq for a,b in zip(coverage,coverage[1:])),default=float('inf'))
        if not before or not after or len(samples)<cfg['minimum_window_state_samples_per_window'] or gap>cfg['maximum_window_state_gap_seconds']:issues.append('WINDOW_STATE_COVERAGE_INSUFFICIENT')
        if any(not e['visible'] or e['minimized'] or not e['foreground_owned'] or e['client_width']!=cfg['actual_render_width'] or e['client_height']!=cfg['actual_render_height'] or any(e.get('input',{}).get(k) for k in ['left','right','middle']) for e in coverage):issues.append('WINDOW_OR_SAMPLED_INPUT_NOT_MATCHED')
        size=[e for e in dimensions if int(e['qpc'])<=lo]
        if not size or (size[-1]['width'],size[-1]['height'])!=(cfg['actual_render_width'],cfg['actual_render_height']):issues.append('ACTUAL_SWAPCHAIN_SIZE_NOT_MATCHED')
        selected=[e for e in present if lo<=int(e['qpc'])<=hi]
        if any(e['sync_interval']!=cfg['expected_present_sync_interval'] or e['flags']!=cfg['expected_present_flags'] for e in selected):issues.append('PRESENT_OPTIONS_NOT_MATCHED')
        values=[(int(b['qpc'])-int(a['qpc']))/freq*1000 for a,b in zip(present,present[1:]) if lo<=int(b['qpc'])<=hi]
        if len(values)<cfg['minimum_present_intervals_per_window']:issues.append('TOO_FEW_PRESENT_INTERVALS')
        (all_on if window['mode']=='on' else all_off).extend(values)
        windows.append(dict(index=index,definition=window,interval_ms=metrics(values),state_samples=len(samples),max_state_gap_seconds=gap,issues=issues))
        errors.extend('WINDOW_'+str(index)+':'+x for x in issues)
    on=metrics(all_on);off=metrics(all_off);delta_median=on['median']-off['median'];delta_p95=on['p95']-off['p95'];median_limit=criteria['native_source_dt_seconds']/8*1000;p95_limit=criteria['native_source_dt_seconds']/2*1000
    if delta_median>median_limit:errors.append('MEDIAN_OBSERVER_COST_EXCEEDED')
    if delta_p95>p95_limit:errors.append('P95_OBSERVER_COST_EXCEEDED')
    clock=[e for e in water if e['kind']=='engine_clock_sample']
    if cfg.get('clock_validation_scope')=='calibration_windows':
        clock=[e for e in clock if any(epoch+int(w['begin']*freq)<=int(e['qpc'])<=epoch+int(w['end']*freq) for w in cfg['windows_from_before_resume_qpc_seconds'])]
    observed={n:sorted({e['values'].get(n) for e in clock if n in e['values']}) for n in ['get_fixedDeltaTime','get_deltaTime','get_timeScale','get_inFixedTimeStep','get_maximumDeltaTime']}
    if observed['get_fixedDeltaTime']!=[criteria['native_source_dt_seconds']] or observed['get_deltaTime']!=[criteria['native_source_dt_seconds']] or observed['get_timeScale']!=[cfg.get('expected_time_scale',1)] or observed['get_inFixedTimeStep']!=[1]:errors.append('NATIVE_CLOCK_CONFIG_NOT_MATCHED')
    fingerprint=[]
    for expected in manifest['artifacts']:
        actual=identity(expected['path'])
        if actual['sha256']!=expected['sha256'] or actual['size_bytes']!=expected['size_bytes']:fingerprint.append(expected['path'])
    if fingerprint or manifest['operation_status']!='complete' or not manifest['watched_source_and_user_data_unchanged']:errors.append('SOURCE_OR_RUN_NOT_CLOSED')
    report=dict(operation_status='complete',verification_status='passed' if not errors else 'failed',criteria=identity(args.criteria),runtime=identity(args.run/'manifest.json'),windows=windows,on_interval_ms=on,off_interval_ms=off,median_extra_ms=delta_median,median_limit_ms=median_limit,p95_extra_ms=delta_p95,p95_limit_ms=p95_limit,native_clock_observed=observed,native_clock_samples=len(clock),water_trace_errors=water_errors,diagnostic_trajectory_usable=False,artifact_identity_errors=fingerprint,errors=errors,scope='D07 observer calibration only, not a formal G03 trajectory or G4 acceptance; input observations sampled at 500 ms')
    (out/'evaluation.json').write_text(json.dumps(report,indent=2),encoding='utf-8');(out/'manifest.json').write_text(json.dumps(dict(operation_status='complete',verification_status=report['verification_status'],errors=errors,artifacts=[identity(p) for p in out.iterdir() if p.is_file()]),indent=2),encoding='utf-8')
    print(json.dumps(dict(result=report['verification_status'],on=on,off=off,median_extra_ms=delta_median,p95_extra_ms=delta_p95,errors=errors)))
    raise SystemExit(1 if errors else 0)

if __name__=='__main__':main()
