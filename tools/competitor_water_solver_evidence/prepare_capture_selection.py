"""Rehash 14 RDCs and prepare staged small parameter scans, never all resources."""
import argparse
import json
import shutil
from pathlib import Path
from evidence_contract import identity

ROOT=Path('D:/godot/project/sandcastle')


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',required=True,type=Path)
    args=p.parse_args();out=args.output
    if not out.is_absolute() or not str(out).isascii():raise ValueError('Absolute ASCII output required')
    out.mkdir(parents=True,exist_ok=False)
    for name in ['sources','raw','derived','logs','requests']:(out/name).mkdir()
    old=json.loads((ROOT/'docs/competitor/evidence/water_gap_recovery_20261025_v1/inventory.json').read_text())
    checks=[]
    for capture in old['captures']:
        actual=identity(capture['path']);matches=actual['size_bytes']==capture['bytes'] and actual['sha256']==capture['sha256']
        checks.append(dict(actual=actual,previous=capture,matches=matches))
    chosen=['test1.rdc','test35-frame20528.rdc','test35-frame20641.rdc','test2.rdc']
    base=json.loads((ROOT/'task/competitor_water_solver_evidence/requests/pilot_request.json').read_text())
    requests=[]
    for index,name in enumerate(chosen):
        match=next(c for c in checks if Path(c['actual']['path']).name==name)
        if not match['matches']:raise ValueError('CAPTURE_IDENTITY_MISMATCH:'+name)
        source=match['actual'];req=dict(base);run_id='t04_'+name[:-4].replace('-','_')+'_20261025_v1'
        req.update(run_id=run_id,operation='audit',source=dict(source_id='rdc:'+source['sha256'],source_path=source['path'],source_size=source['size_bytes'],source_sha256=source['sha256']),
            selector=dict(capture_sha256=source['sha256'],event_id=None,stage='compute',boundary='post-event',discovery='Match original-program hash independently'),
            repeat_index=0,replay_instance_id=run_id+'_open0',variation=None,
            output_root=(out.parent/run_id).as_posix(),tool=dict(name='multicapture_replay.py',script=identity(Path(__file__).with_name('multicapture_replay.py'))))
        request_path=out/'requests'/('capture%d.json'%index);request_path.write_text(json.dumps(req,indent=2),encoding='utf-8')
        requests.append(dict(request=identity(request_path),capture=name,phase=1 if index<2 else 2))
    for name in ['prepare_capture_selection.py','evidence_contract.py','multicapture_replay.py','run_replay.py']:
        shutil.copyfile(Path(__file__).with_name(name),out/'sources'/name)
    selection=dict(schema_version='1.0',run_id=out.name,checks=checks,requests=requests,
        reasons=['Phase1: test1 checks known baseline and test35 first filename candidate tests another capture identity',
                 'Only after phase1 export/layout review: later-numbered test35 candidate and test2 provide parameter/scene contrast',
                 'Filename numbers do not prove chronology, same scene, elapsed time or capture continuity'],
        excluded=[dict(capture=Path(c['actual']['path']).name,reason='Keep initial sample small; not required before identifying useful parameter changes') for c in checks if Path(c['actual']['path']).name not in chosen])
    (out/'capture_selection.json').write_text(json.dumps(selection,indent=2),encoding='utf-8')
    (out/'manifest.json').write_text(json.dumps(dict(operation_status='complete',verification_status='passed' if all(c['matches'] for c in checks) else 'failed',errors=[],
        artifacts=[identity(p) for p in out.rglob('*') if p.is_file()],scope='Identity and staged selection only; no replay or temporal inference'),indent=2),encoding='utf-8')
    print(json.dumps(dict(captures=len(checks),matches=all(c['matches'] for c in checks),phase1=[r['request']['path'] for r in requests if r['phase']==1])),flush=True)


if __name__=='__main__':main()
