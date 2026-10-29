"""Compare common Present timing across pilot modes; no automatic perturbation acceptance."""
import argparse
import collections
import datetime
import json
import math
import shutil
import statistics
from pathlib import Path
from evidence_contract import identity
from audit_runtime_pilot import closure,water_events

def quantile(values,q):
    v=sorted(values)
    if not v:return None
    x=(len(v)-1)*q;lo=int(x);hi=math.ceil(x);return v[lo]+(v[hi]-v[lo])*(x-lo)

def metrics(values):return dict(count=len(values),median=statistics.median(values) if values else None,p95=quantile(values,.95),p99=quantile(values,.99),maximum=max(values) if values else None)

def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--runs',nargs='+',required=True,type=Path);ap.add_argument('--output',required=True,type=Path);args=ap.parse_args();out=args.output.resolve()
    if not str(out).isascii():raise ValueError('ASCII output required')
    out.mkdir(parents=True,exist_ok=False);shutil.copyfile(__file__,out/'audit_runtime_modes.py');reports=[]
    for run in args.runs:
        mode=json.loads((run/'mode.json').read_text());manifest=json.loads((run/'manifest.json').read_text());raw=json.loads((run/'logs/events.json').read_text());events=[e for x in raw if x.get('payload',{}).get('kind')=='presentation_trace' for e in x['payload']['events']];stats=json.loads((run/'presentation_final.json').read_text());errors=[]
        if [e['seq'] for e in events]!=list(range(1,stats['last_seq']+1)):errors.append('PRESENT_SEQUENCE_NOT_CLOSED')
        entries=[e for e in events if e['kind']=='present_enter'];returns=[e for e in events if e['kind']=='present_return'];end={e['call_id']:e for e in returns}
        if len(entries)!=stats['presents'] or len(returns)!=stats['returns'] or stats['inflight'] or collections.Counter(e['call_id'] for e in entries)!=collections.Counter(e['call_id'] for e in returns):errors.append('PRESENT_CALLS_NOT_CLOSED')
        if stats['dropped'] or stats['errors']:errors.append('PRESENT_OBSERVER_ERROR_OR_DROP')
        freq=int(next(e['qpc_frequency'] for e in events if e['kind']=='loaded'));first=int(entries[0]['qpc']);last=int(entries[-1]['qpc'])
        intervals=[];durations=[]
        for previous,current in zip(entries,entries[1:]):
            relative=(int(current['qpc'])-first)/freq;duration=(int(current['qpc'])-int(previous['qpc']))/freq*1000
            intervals.append(dict(call_id=current['call_id'],seconds_after_first_present=relative,interval_ms=duration))
        for e in entries:
            if e['call_id'] in end:durations.append((int(end[e['call_id']]['qpc'])-int(e['qpc']))/freq*1000)
        selected=[d['interval_ms'] for d in intervals if 8<=d['seconds_after_first_present']<=12]
        water=water_events(raw);water_errors=closure(water,json.loads((run/'observer_final.json').read_text())) if mode['water_observer'] else None
        identities=[]
        for expected in manifest['artifacts']:
            actual=identity(expected['path'])
            if actual['sha256']!=expected['sha256'] or actual['size_bytes']!=expected['size_bytes']:identities.append(expected['path'])
        if identities:errors.append('ARTIFACT_IDENTITY_MISMATCH')
        seeds=json.loads((run/'seed_manifest.json').read_text())['files'];seed_identity=[{k:v for k,v in s['source'].items() if k in ['path','size_bytes','sha256']} for s in seeds]
        report=dict(run=run.as_posix(),manifest=identity(run/'manifest.json'),mode=mode,operation_status=manifest['operation_status'],source_and_watched_user_unchanged=manifest['watched_source_and_user_data_unchanged'],stats=stats,presentation_errors=errors,water_trace_errors=water_errors,qpc_frequency=freq,present_elapsed_seconds=(last-first)/freq,swapchains=[e for e in events if e['kind']=='swapchain'],sync_flags=dict(collections.Counter(str((e['sync_interval'],e['flags'])) for e in entries)),hresults=dict(collections.Counter(str(e['hresult']) for e in returns)),pilot_window=dict(reference='8..12 seconds after first observed Present entry; retrospective pilot only',interval_ms=metrics(selected)),all_intervals_ms=metrics([d['interval_ms'] for d in intervals]),cpu_present_duration_ms=metrics(durations),largest_intervals=sorted(intervals,key=lambda d:d['interval_ms'],reverse=True)[:10],seed_identity=seed_identity,common_sources={name:identity(run/'sources'/name)['sha256'] for name in ['isolation_guard.js','presentation_observer.js','runtime_startup.py']},water_observer_sha256=identity(run/'sources/water_observer.js')['sha256'] if mode['water_observer'] else None,unknowns=['Visibility/minimization/foreground not sampled in these pilots','No pre-frozen D07 criteria','Single run per mode, uncontrolled OS/background GPU activity','Present API timing is not GPU completion or original observer-free simulation cadence'])
        reports.append(report);(out/(run.name+'.json')).write_text(json.dumps(report,indent=2),encoding='utf-8')
    comparability=[]
    if any(r['seed_identity']!=reports[0]['seed_identity'] for r in reports):comparability.append('SEED_IDENTITY_DIFFERS')
    if any(r['common_sources']!=reports[0]['common_sources'] for r in reports):comparability.append('COMMON_INSTRUMENTATION_DIFFERS')
    observers={r['water_observer_sha256'] for r in reports if r['mode']['water_observer']}
    if len(observers)!=1:comparability.append('WATER_OBSERVER_VERSION_DIFFERS')
    summary=dict(operation_status='complete',verification_status='partial',scope='Pilot perturbation diagnosis only; D07 and G02 not accepted',created_at=datetime.datetime.now(datetime.timezone.utc).isoformat(),comparability_errors=comparability,runs=[dict(run=r['run'],mode=r['mode'],stats=r['stats'],presentation_errors=r['presentation_errors'],water_trace_errors=r['water_trace_errors'],pilot_window=r['pilot_window'],all_intervals_ms=r['all_intervals_ms'],largest_intervals=r['largest_intervals'][:2]) for r in reports])
    (out/'comparison.json').write_text(json.dumps(summary,indent=2),encoding='utf-8')
    (out/'manifest.json').write_text(json.dumps(dict(operation_status='complete',verification_status='partial',artifacts=[identity(p) for p in out.iterdir() if p.is_file()]),indent=2),encoding='utf-8')
    print(json.dumps(summary))

if __name__=='__main__':main()
