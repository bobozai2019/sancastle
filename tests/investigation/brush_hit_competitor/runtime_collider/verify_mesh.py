"""Independent raw/hash, geometry, bounds and Moller-Trumbore verification."""
import argparse,json,hashlib,sys,struct
from pathlib import Path
import numpy as np
def intersect(v,tri,o,d,face=None):
    a,b,c=(v[tri[:,j]] for j in range(3));e1=b-a;e2=c-a
    h=np.cross(np.broadcast_to(d,e2.shape),e2);det=np.einsum('ij,ij->i',e1,h)
    inv=np.zeros_like(det);valid=np.abs(det)>1e-10;inv[valid]=1/det[valid]
    s=o-a;u=inv*np.einsum('ij,ij->i',s,h);q=np.cross(s,e1)
    w=inv*np.einsum('j,ij->i',d,q);t=inv*np.einsum('ij,ij->i',e2,q)
    good=valid&(u>=-1e-7)&(w>=-1e-7)&(u+w<=1+1e-7)&(t>=0)&(t<=100)
    if not good.any():return None
    ids=np.flatnonzero(good);i=ids[np.argmin(t[ids])]
    if face is not None:
        assert 0<=face<len(tri) and good[face], 'reported physics face must intersect'
        assert abs(t[face]-t[i])<1e-5, 'reported face must be co-nearest'
        i=face
    normal=np.cross(e1[i],e2[i]);normal/=np.linalg.norm(normal)
    return {'point':o+t[i]*d,'distance':t[i],'normal':normal,'triangle':int(i)}
def main():
    p=argparse.ArgumentParser();p.add_argument('--run',required=True);p.add_argument('--snapshot-ids',nargs='+');p.add_argument('--report-name',default='verification.json');a=p.parse_args();root=Path(a.run).resolve()
    assert Path(a.report_name).name==a.report_name and a.report_name.endswith('.json')
    rows=[json.loads(l) for l in (root/'messages.jsonl').read_text().splitlines()]
    data=[(r,r['message'].get('payload',{})) for r in rows];snaps=[x for _,x in data if x.get('kind')=='snapshot']
    if a.snapshot_ids:
        available={s['snapshot_id']:s for s in snaps};assert all(id in available for id in a.snapshot_ids);snaps=[available[id] for id in a.snapshot_ids]
    raw=[dict(x,raw=r['raw']) for r,x in data if x.get('kind')=='raw'];errors=[x for _,x in data if x.get('kind') in ['error','unavailable']]
    for entry in raw:
        b=Path(entry['raw']['path']).read_bytes();assert len(b)==entry['bytes']==entry['raw']['bytes'];assert hashlib.sha256(b).hexdigest()==entry['raw']['sha256']
    (root/'raw_index.jsonl').write_text(''.join(json.dumps(x)+'\n' for x in raw),encoding='utf8')
    (root/'errors.jsonl').write_text(''.join(json.dumps(x)+'\n' for x in errors),encoding='utf8')
    derived=root/'derived';derived.mkdir(exist_ok=True);results=[]
    for s in snaps:
        id=s['snapshot_id'];items={x['payload_kind']:x for x in raw if x['snapshot_id']==id}
        read=lambda n,d:np.fromfile(items[n]['raw']['path'],dtype=d)
        v=read('vertices','<f4').reshape(-1,3).astype('float64');assert len(v)==s['vertex_count'] and np.isfinite(v).all()
        tris=[]
        for sm in s['submeshes']:
            idx=read('indices_'+str(sm['index']),'<i4').astype('int64')+sm['base_vertex']
            assert len(idx)==sm['index_count']==sm['reported_index_count'];assert idx.min()>=0 and idx.max()<len(v)
            assert sm['topology']==0 and len(idx)%3==0;tris.append(idx.reshape(-1,3))
        tri=np.concatenate(tris);matrix=np.array(s['local_to_world']).reshape(4,4,order='F');world=(np.column_stack([v,np.ones(len(v))])@matrix.T)[:,:3]
        bounds=np.array(s['bounds_local']);tol=max(1e-5,1e-5*max(1,np.linalg.norm(world.max(0)-world.min(0))))
        assert np.max(np.abs((v.max(0)+v.min(0))/2-bounds[:3]))<tol;assert np.max(np.abs((v.max(0)-v.min(0))/2-bounds[3:]))<tol
        assert s['bound_mesh_identity']==s['meshC_identity'];assert s['consistency_status']=='binding_stable_update_return_same_thread'
        assert np.array_equal(v,read('verticesOS','<f4').reshape(-1,3))
        checks=[];candidate_audit=[]
        for _,r in data:
            if r.get('kind')!='ray_candidate' or r['snapshot_id']!=id:continue
            b=Path(items['ray_'+r['test']]['raw']['path']).read_bytes()
            assert len(b)>=44
            if r['hit_bool']:assert struct.unpack_from('<i',b,40)[0]==r['hit_collider_instance_id']
            candidate_audit.append({'candidate':r['test'],'origin_ws':r['origin_ws'],'hit_bool':r['hit_bool'],'hit_collider_instance_id':r.get('hit_collider_instance_id'),'target_hit':r['hit_bool'] and r.get('hit_collider_instance_id')==r['target_collider_instance_id']})
        selection=next((x for _,x in data if x.get('kind')=='edge_selection' and x['snapshot_id']==id),None)
        if selection:
            edge=next(x for _,x in data if x.get('kind')=='ray' and x['snapshot_id']==id and x['test']=='edge')
            assert edge['origin_ws'][::2]==selection['xz']
            if selection['selected_snapshot']==id and selection['candidate'] is not None:
                n=selection['candidate'];assert len(candidate_audit)==n+1 and candidate_audit[n]['target_hit'] and not any(x['target_hit'] for x in candidate_audit[:n])
        for _,r in data:
            if r.get('kind')!='ray' or r['snapshot_id']!=id:continue
            o=np.array(r['origin_ws']);d=np.array(r['direction_ws']);face=None
            if r['hit_bool'] and r.get('hit_collider_instance_id')==r['target_collider_instance_id']:
                face=struct.unpack_from('<I',Path(items['ray_'+r['test']]['raw']['path']).read_bytes(),24)[0]
            hit=intersect(world,tri,o,d,face)
            check={'test':r['test'],'physical_hit':r['hit_bool'],'offline_target_hit':hit is not None,'physical_face_id':face}
            if r['test'] in ['center','oblique','edge']:
                check['same_collider']=r.get('hit_collider_instance_id')==r['target_collider_instance_id']
                if hit and r['hit_bool']:
                    pe=float(np.linalg.norm(hit['point']-r['point_ws']));de=float(abs(hit['distance']-r['distance']));angle=float(np.degrees(np.arccos(np.clip(np.dot(hit['normal'],r['normal_ws']),-1,1))))
                    check.update(position_error=pe,distance_error=de,normal_degrees=angle,tolerance=tol,pass_result=check['same_collider'] and pe<=tol and de<=tol and angle<=1)
                else:check['pass_result']=False
            elif r['test']=='outside':check['pass_result']=not r['hit_bool'] and hit is None
            else:check['pass_result']=r['hit_bool'] and r.get('hit_collider_instance_id')!=r['target_collider_instance_id'] and hit is None
            checks.append(check)
        with (derived/(id+'.obj')).open('w') as f:
            f.write('# DERIVED from actual sharedMesh API-copy raw; local space\n');f.writelines('v %.9g %.9g %.9g\n'%tuple(row) for row in v);f.writelines('f %d %d %d\n'%tuple(row+1) for row in tri)
        (root/(id+'.json')).write_text(json.dumps(s,indent=2),encoding='utf8')
        aux=None
        if 'ReadbackCells' in items:
            cells=read('ReadbackCells','<f4').reshape(-1,8);ri=read('readbackIndices','<i4').reshape(-1,4);assert ri.min()>=0 and ri.max()<len(cells) and len(ri)==len(v)
            assert np.isfinite(cells[:,:7]).all()
            predicted=cells[ri,5].mean(axis=1,dtype=np.float32);error=float(np.max(np.abs(predicted-v[:,1])));assert error<=tol
            cache=next(x for _,x in data if x.get('kind')=='readback_snapshot' and x['snapshot_id']==id);assert cache['count']==len(cells) and cache['stride']==32 and cache['copy_seq_before']==cache['copy_seq_after'] and cache['active_copy_depth']==0
            aux={'cell_count':len(cells),'stride':32,'float_fields_finite':bool(np.isfinite(cells[:,:7]).all()),'crest_spawn_encoding':'int32 raw, not checked as float','vertex_sand_average_max_error':error,'cache_writer_guard_pass':True}
        filters=[]
        for _,x in data:
            if x.get('kind')=='non_plane_filter' and x['snapshot_id']==id:
                blobdata=Path(items['negative_non_plane_hit']['raw']['path']).read_bytes();physical_id=struct.unpack_from('<i',blobdata,40)[0]
                passed=x['hit_instance_id']==physical_id and x['plane_chunk']=='0x0' and x['accepted'] is False and x['filter_pass'] is True
                filters.append({'physical_collider_instance_id':physical_id,'runtime_component_null':x['plane_chunk']=='0x0','pass_result':passed})
        results.append({'snapshot_id':id,'vertex_count':len(v),'triangle_count':len(tri),'geometry_pass':True,'world_bounds':[world.min(0).tolist(),world.max(0).tolist()],'ray_checks':checks,'edge_candidate_audit':candidate_audit,'edge_selection':selection,'physical_correspondence_pass':len(checks)==5 and all(c['pass_result'] for c in checks),'auxiliary_cache':aux,'non_plane_filter_checks':filters})
    pair=None
    if len(snaps)==2:
        ids=[s['snapshot_id'] for s in snaps];v=[np.fromfile(next(x['raw']['path'] for x in raw if x['snapshot_id']==id and x['payload_kind']=='vertices'),dtype='<f4').reshape(-1,3) for id in ids]
        same=all(snaps[0][k]==snaps[1][k] for k in ['chunk_identity','collider_identity','meshC_identity','bound_mesh_identity','local_to_world','submeshes','vertex_count'])
        for sm in snaps[0]['submeshes']:
            payload='indices_'+str(sm['index']);indexbytes=[Path(next(x['raw']['path'] for x in raw if x['snapshot_id']==id and x['payload_kind']==payload)).read_bytes() for id in ids];same=same and indexbytes[0]==indexbytes[1]
        selections=[s['edge_selection'] for s in results]
        if all(selections):assert selections[0]['xz']==selections[1]['xz'] and selections[0]['selected_snapshot']==selections[1]['selected_snapshot']
        if same:
            dy=v[1][:,1]-v[0][:,1];action_record=(root/'arm_edit.json').exists();pair={'same_identity_transform_topology':True,'xz_unchanged':bool(np.array_equal(v[0][:,[0,2]],v[1][:,[0,2]])),'changed_y_vertices':int(np.count_nonzero(dy)),'delta_y_min':float(dy.min()),'delta_y_max':float(dy.max()),'delta_y_mean':float(dy.mean()),'after_human_action_record':action_record,'causal_isolation':'not proven; inspect recorded action and control conditions' if action_record else 'not proven; no human action record for this pair'}
    report={'raw_hashes_verified':len(raw),'snapshots':results,'scope':'geometry, actual-face ray correspondence, temporal pair; single-edit causality not asserted','dynamic_temporal_pair':pair,'dynamic_edit_pair_pass':False,'script_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'command':sys.argv}
    report_path=root/a.report_name
    if report_path.exists():
        oldbytes=report_path.read_bytes();archive=root/('verification_archive_'+hashlib.sha256(oldbytes).hexdigest()[:12]+'.json')
        if not archive.exists():archive.write_bytes(oldbytes)
        previous=root/'verification_before_face_selection.json'
        if a.report_name=='verification.json' and not previous.exists():previous.write_bytes(report_path.read_bytes())
    report_path.write_text(json.dumps(report,indent=2),encoding='utf8');print(json.dumps(report,indent=2))
    return 0 if results and all(s['geometry_pass'] for s in results) else 3
if __name__=='__main__':sys.exit(main())
