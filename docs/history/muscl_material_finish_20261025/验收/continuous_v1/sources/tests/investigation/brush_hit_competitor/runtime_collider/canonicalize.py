"""Combine sealed native messages with source/owner manifests; retain originals."""
import argparse,json,sys
from pathlib import Path
from baseline import identity,save
def main():
    p=argparse.ArgumentParser();p.add_argument('--attempt',required=True);p.add_argument('--spawn-owner',required=True);a=p.parse_args();d=Path(a.attempt).resolve();run=d.parent;owner=json.loads(Path(a.spawn_owner).read_text());rows=[json.loads(l) for l in (d/'messages.jsonl').read_text().splitlines()];payloads=[r['message'].get('payload',{}) for r in rows];module=next(x for x in payloads if x.get('kind')=='module');assert owner['pid']==module['pid'];dest=d/'snapshots';dest.mkdir(exist_ok=True);raws=[]
    for s in (x for x in payloads if x.get('kind')=='snapshot'):
        id=s['snapshot_id'];binding=next(x for x in payloads if x.get('kind')=='binding_observation' and x['snapshot_id']==id);actual=binding['observedBinding'];assert actual['collider']==s['collider_identity'] and actual['mesh']==s['bound_mesh_identity'];assert binding['global_binding_seq_before']==binding['global_binding_seq_after'];assert binding['final_shared_mesh']==s['bound_mesh_identity']
        record=dict(s,run_id=run.name,snapshot_namespace=d.name,pid=owner['pid'],process_start_identity={'original_spawn_owner':str(Path(a.spawn_owner).resolve()),'spawn_return_utc':owner['created_utc'],'os_creation_date':'not recorded; identity scoped to uninterrupted owned spawn/session'},exe=identity(owner['argv'][0]),module=dict(module,file_identity=identity(module['path'])),metadata=identity(Path(owner['argv'][0]).parent/'Sandcastle_Data/il2cpp_data/Metadata/global-metadata.dat'),binding_seq=actual['seq'],binding_record=binding,tool_manifest=str(d/'tool_manifest.json'),source_manifest=str(run/'source_manifest.json'),frame_count=None,frame_count_reason='not sampled',physx_cooked_payload='unavailable; input mesh only')
        if owner.get('process_identity'):
            record['process_start_identity']['os_creation_date']=owner['process_identity']['created_utc']
            record['process_start_identity']['os_identity_record']=owner['process_identity']
            record['process_start_identity']['os_identity_note']='CIM at spawn; suspended executable path may be null; resumed path separately recorded when available'
            resumed=Path(a.spawn_owner).parent/'resumed_process_identity.json'
            if resumed.exists():record['process_start_identity']['resumed_identity']=json.loads(resumed.read_text(encoding='utf-8'));record['process_start_identity']['resumed_identity_record']=str(resumed.resolve())
        record['local_binding_seq_legacy']=s['binding_seq'];record['raw_payloads']=[]
        record['config']=dict(s['config'])
        if record['config'].get('is_trigger') in [0,1]:record['config']['is_trigger']=bool(record['config']['is_trigger'])
        for r in rows:
            x=r['message'].get('payload',{})
            if x.get('kind')=='raw' and x['snapshot_id']==id:
                entry={'run_id':run.name,'snapshot_namespace':d.name,'snapshot_id':id,'pid':owner['pid'],'chunk_identity':s['chunk_identity'],'collider_identity':s['collider_identity'],'mesh_identity':s['bound_mesh_identity'],'raw':r['raw'],'selector':x['selector'],'address':x['address'],'bytes':x['bytes'],'capture_thread':x['thread'],'payload_kind':x['payload_kind'],'endianness':'little','provenance':str(d/'messages.jsonl'),'retrieval_class':'API copy' if x['payload_kind']=='vertices' or x['payload_kind'].startswith('indices_') or x['payload_kind'].startswith('ray_') else 'NativeArray raw memory snapshot'};raws.append(entry);record['raw_payloads'].append(entry)
        save(dest/(id+'.json'),record)
    save(d/'canonical_raw_index.json',raws);save(d/'owner_resolution.json',{'original_spawn_owner':str(Path(a.spawn_owner).resolve()),'actual_owner':owner,'note':'historical attach owner.json creation/argv fields described attach attempt, not new spawn; canonical record resolves to original owner','command':sys.argv});print('canonical snapshots and raw entries='+str(len(raws)))
if __name__=='__main__':main()
