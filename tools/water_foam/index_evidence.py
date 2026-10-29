"""Index executed evidence without promoting probe success to a Gate pass."""
import datetime
import hashlib
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
EVIDENCE=ROOT/'task/water_foam_visual/验收'

def main():
    entries=[]
    for result in sorted((EVIDENCE/'G0').rglob('result.json')):
        directory=result.parent
        raw=json.loads(result.read_text(encoding='utf-8-sig'))
        artifacts=[]
        for file in sorted(directory.rglob('*')):
            if not file.is_file() or file.name=='run.json':continue
            with file.open('rb') as stream:digest=hashlib.file_digest(stream,'sha256').hexdigest()
            artifacts.append(dict(path=file.relative_to(directory).as_posix(),sha256=digest,bytes=file.stat().st_size))
        probe_path=directory/'probe.json'
        capture_path=directory/'capture.json'
        probe=json.loads(probe_path.read_text(encoding='utf-8-sig')) if probe_path.is_file() else {}
        capture=json.loads(capture_path.read_text(encoding='utf-8-sig')) if capture_path.is_file() else {}
        obs=probe.get('observations',{})
        meta=capture.get('metadata',{})
        config=obs.get('configuration',meta.get('configuration',{}))
        before=directory/'sources_before.json'
        source_hashes=json.loads(before.read_text(encoding='utf-8')) if before.is_file() else config.get('sources',{})
        assertions=[dict(id=x['name'],status='pass' if x['pass'] else 'fail',scope='probe assertion only') for x in probe.get('checks',[])]
        assertions.append(dict(id='process_exit',status='pass' if raw.get('exit_code')==0 else 'fail',actual=raw))
        assertions.append(dict(id='source_stability',status=('fail' if raw['source_drift'] else 'pass') if 'source_drift' in raw else 'not_measured'))
        assertions.append(dict(id='G0',status='not_measured',reason='Contract freeze, stable source, continuous evidence and complete A/A acceptance still required'))
        frames=obs.get('frames',[])
        render=obs.get('render',{})
        run=dict(schema='foam_visual_run_v1',run_id=directory.relative_to(EVIDENCE).as_posix(),variant='baseline',case_id='V11' if capture else 'V01',scene=meta.get('scene',config.get('domain_id')),source_hashes=source_hashes,resource_hashes={k:v for k,v in source_hashes.items() if k.startswith(('assets/','res://assets/'))},configuration_hash=config.get('configuration_hash'),effective_uniforms={k:v.get('uniforms',{}) for k,v in obs.get('layers',{}).items()},engine=meta.get('engine',render.get('engine')),adapter=meta.get('adapter',render.get('adapter')),renderer='Forward+',driver=meta.get('driver',render.get('driver')),viewport=meta.get('viewport',render.get('size')),camera=obs.get('camera',meta.get('camera')),seed_hash=None,generation=1001 if probe else None,state_seq=[f.get('state_seq') for f in frames],tick=[f.get('tick') for f in frames],time_s=[f.get('time_s') for f in frames],timing=dict(api='RenderingServer viewport timing' if capture else None,vsync=meta.get('vsync'),intervals=meta.get('intervals',[]),sample_count=len(capture.get('frames',[])),simulation_compute_coverage='not established'),optimization_time=dict(budget_s=1800,used_s=0,remaining_s=1800,segments=[]),metrics=None,assertions=assertions,artifacts=artifacts)
        (directory/'run.json').write_text(json.dumps(run,ensure_ascii=False,indent=2),encoding='utf-8')
        entries.append(dict(run_id=run['run_id'],manifest=(directory/'run.json').relative_to(EVIDENCE).as_posix(),process_result=raw,gate_status='not_passed'))
    index=dict(schema='foam_visual_evidence_index_v1',updated_at=datetime.datetime.now(datetime.timezone.utc).isoformat(),gates={'G0':'in_progress','G1':'not_started','G2':'not_started','G3':'not_started','G4':'not_started','G5':'not_started'},runs=entries)
    (EVIDENCE/'index.json').write_text(json.dumps(index,ensure_ascii=False,indent=2),encoding='utf-8')
    print(f'Indexed {len(entries)} actual runs; no Gate passed.')

if __name__=='__main__':main()
