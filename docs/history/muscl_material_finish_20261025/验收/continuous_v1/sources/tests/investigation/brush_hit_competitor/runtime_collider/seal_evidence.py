"""Seal all attempts including partial failures, source-after hashes and provenance."""
import argparse,json,hashlib,sys,datetime
from pathlib import Path
from baseline import identity,save
def main():
    p=argparse.ArgumentParser();p.add_argument('--run',required=True);p.add_argument('--completion-audit');a=p.parse_args();root=Path(a.run).resolve();sources=json.loads((root/'source_manifest.json').read_text());after=[]
    for source in sources['sources']:
        for old in source['files']:
            now=identity(old['path']);after.append({'before':old,'after':now,'unchanged':old==now})
    save(root/'source_after.json',after);assert all(x['unchanged'] for x in after)
    inventory=[];attempts=[]
    for d in sorted(root.glob('attempt_*')):
        owner=json.loads((d/'owner.json').read_text()) if (d/'owner.json').exists() else None
        rows=[json.loads(l) for l in (d/'messages.jsonl').read_text().splitlines()] if (d/'messages.jsonl').exists() else []
        raws=[];errors=[];snapshots=[]
        for row in rows:
            msg=row['message'];data=msg.get('payload',{})
            if msg['type']=='error' or data.get('kind') in ['error','unavailable','locator_error']:errors.append(row)
            if data.get('kind')=='snapshot':snapshots.append(data)
            if 'raw' in row:
                actual=identity(row['raw']['path']);assert actual==row['raw'];raws.append({'attempt_id':d.name,'pid':owner['pid'],'snapshot_id':data.get('snapshot_id'),'source_manifest':str(root/'source_manifest.json'),'selector':data.get('selector'),'source_address':data.get('address'),'thread':data.get('thread'),'format':'float32 xyz little endian' if data.get('payload_kind') in ['vertices','verticesOS'] else 'see runtime payload_kind and ABI record','completeness':'snapshot_submitted' if any(x.get('snapshot_id')==data.get('snapshot_id') for x in [r['message'].get('payload',{}) for r in rows] if x.get('kind')=='snapshot') else 'partial','raw':actual})
        driver_failure=json.loads((d/'failure.json').read_text(encoding='utf-8')) if (d/'failure.json').exists() else None
        if driver_failure:errors.append({'origin':'driver failure.json','failure':driver_failure})
        save(d/'sealed_raw_index.json',raws);save(d/'sealed_errors.json',errors)
        attempts.append({'attempt':d.name,'owner':owner,'snapshots':len(snapshots),'raws':len(raws),'errors':len(errors),'driver_failure':driver_failure,'terminal_record':(d/'observation_end.json').exists() or (d/'failure.json').exists()})
    for f in root.rglob('*'):
        if f.is_file() and 'owned_game' not in f.parts and f.name not in ['evidence_inventory.json','seal.json']:inventory.append(identity(f))
    scope='stage evidence sealed; unfinished G4 requirements remain; not A-grade success';audit_record=None
    if a.completion_audit:
        audit=json.loads(Path(a.completion_audit).read_text(encoding='utf-8'));assert audit['remaining_required_work']==[] and len(audit['gates'])==6 and all(x['terminal_record'] for x in attempts)
        audit_record=identity(a.completion_audit);scope='final A-grade input-mesh and normal bucket-edit task evidence; C2 edit attribution and input-state unknowns retained; not cooked PhysX shape'
    save(root/'evidence_inventory.json',inventory);save(root/'seal.json',{'utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'attempts':attempts,'source_files_unchanged':True,'inventory_count':len(inventory),'command':sys.argv,'seal_script':identity(__file__),'completion_audit':audit_record,'scope':scope})
    print(json.dumps({'attempts':len(attempts),'files':len(inventory),'source_unchanged':True}))
if __name__=='__main__':main()
