"""Audit raw input hits, equal-duration control, and operator-confirmed normal bucket edit.
Does not infer physical click count from InputSystem samples or recover tool business logic.
"""
import argparse, json, hashlib, struct, sys
from pathlib import Path
import numpy as np

def main():
    p=argparse.ArgumentParser();p.add_argument('--run',required=True);a=p.parse_args();root=Path(a.run).resolve()
    rows=[json.loads(l) for l in (root/'messages.jsonl').read_text().splitlines()]
    ps=[r['message'].get('payload',{}) for r in rows]
    op=json.loads((root/'operator_action.json').read_text(encoding='utf-8'))
    sn={x['snapshot_id']:x for x in ps if x.get('kind')=='snapshot'}
    phases={x['snapshot_id']:x for x in ps if x.get('kind')=='capture_phase'}
    raw={(r['message']['payload']['snapshot_id'],r['message']['payload']['payload_kind']):r for r in rows if r['message'].get('payload',{}).get('kind')=='raw'}
    def read(id,kind):
        r=raw[id,kind];b=Path(r['raw']['path']).read_bytes()
        assert len(b)==r['raw']['bytes'] and hashlib.sha256(b).hexdigest()==r['raw']['sha256']
        return b
    ids=[op['control_snapshot'],op['before_snapshot'],op['after_snapshot']]
    v=[np.frombuffer(read(id,'vertices'),dtype='<f4').reshape(-1,3) for id in ids]
    assert all(np.array_equal(v[0][:,[0,2]],x[:,[0,2]]) for x in v[1:])
    assert all(sn[ids[0]][k]==sn[id][k] for id in ids[1:] for k in ['chunk_identity','collider_identity','bound_mesh_identity','local_to_world','submeshes'])
    for sm in sn[ids[0]]['submeshes']:
        assert all(read(ids[0],'indices_'+str(sm['index']))==read(id,'indices_'+str(sm['index'])) for id in ids[1:])
    camera_equal=all(phases[ids[0]][k]==phases[id][k] for id in ids[1:] for k in ['camera_world_to_camera','camera_projection','pixel_width','pixel_height'])
    freq=int(sn[ids[1]]['qpc_frequency']);begin=int(sn[ids[1]]['capture_end_qpc']);end=int(sn[ids[2]]['capture_begin_qpc'])
    inputs=[x for x in ps if x.get('kind')=='input_physics' and begin<int(x['query_qpc'])<end]
    down=[x for x in inputs if x['left_button_pressed'] is True]
    target=[x for x in down if x.get('hit_collider_instance_id')==op['target_collider_instance_id']]
    assert target
    for x in down:
        b=read(x['raw_hit_snapshot_id'],'input_physics_hit');assert len(b)==44
        assert list(struct.unpack_from('<3f',b,0))==x['point_ws']
        assert list(struct.unpack_from('<3f',b,12))==x['normal_ws']
        assert struct.unpack_from('<f',b,28)[0]==x['distance']
        assert struct.unpack_from('<i',b,40)[0]==x['hit_collider_instance_id']
        assert struct.unpack_from('<I',b,24)[0]==x['face_id']
    groups=[];previous=False
    for x in inputs:
        pressed=x['left_button_pressed'] is True
        if pressed:
            if not previous:groups.append([])
            groups[-1].append(x)
        previous=pressed
    control_inputs=[x for x in ps if x.get('kind')=='input_physics' and int(sn[ids[0]]['capture_end_qpc'])<int(x['query_qpc'])<begin]
    bg=v[1][:,1]-v[0][:,1];dy=v[2][:,1]-v[1][:,1]
    ctrl_secs=(int(sn[ids[1]]['capture_begin_qpc'])-int(sn[ids[0]]['capture_begin_qpc']))/freq
    edit_secs=(int(sn[ids[2]]['capture_begin_qpc'])-int(sn[ids[1]]['capture_begin_qpc']))/freq
    pair=json.loads((root/'verification_bucket_pair.json').read_text());control=json.loads((root/'verification_bucket_control.json').read_text())
    physical=all(s['physical_correspondence_pass'] for s in pair['snapshots']+control['snapshots'])
    ray_deltas=[]
    for test in ['center','oblique','edge']:
        rr=[next(x for x in ps if x.get('kind')=='ray' and x['snapshot_id']==id and x['test']==test) for id in ids[1:]]
        ray_deltas.append({'test':test,'point_change':float(np.linalg.norm(np.array(rr[1]['point_ws'])-rr[0]['point_ws'])),'distance_change':rr[1]['distance']-rr[0]['distance']})
    observed=physical and camera_equal and bool(np.count_nonzero(dy)) and any(x['point_change']>1e-5 for x in ray_deltas)
    normal_edit=op['normal_edit_count']==1 and op['tool']=='bucket' and op['operator_clarification']=='用的桶，需要按下拖动抬起'
    control_no_sampled_press=bool(control_inputs) and not any(x['left_button_pressed'] is not False for x in control_inputs)
    report={'snapshot_ids':ids,'operator_record':str(root/'operator_action.json'),'actual_target_hit_raw_checks':len(target),'all_pressed_hit_raw_checks':len(down),'sampled_button_segments':len(groups),'segments': [{'sample_count':len(g),'first_qpc':g[0]['query_qpc'],'last_qpc':g[-1]['query_qpc'],'screen_start':g[0]['screen_position'],'screen_end':g[-1]['screen_position']} for g in groups],'physical_click_count':'unknown; InputSystem state segments are not a hardware event log','camera_endpoint_matrices_equal':camera_equal,'identity_transform_index_bytes_and_xz_equal':True,'control_seconds':ctrl_secs,'edit_pair_seconds':edit_secs,'control_sample_count':len(control_inputs),'control_no_sampled_left_press':control_no_sampled_press,'control_delta_y':[float(bg.min()),float(bg.max())],'edit_delta_y':[float(dy.min()),float(dy.max())],'changed_y_vertices':int(np.count_nonzero(dy)),'ray_deltas':ray_deltas,'physical_correspondence_pass':physical,'dynamic_edit_pair_pass':bool(observed and normal_edit and control_no_sampled_press),'confidence':{'geometry_and_physics':'C3 runtime data + independent geometry checks','normal_single_bucket_operation':'C2 operator confirmation + actual target hits + same-duration control; cursor drag is normal input','exact_input_state_transition_reason':'C0 unknown'},'limits':'background is not fully subtracted; does not prove one hardware press, bucket business logic, cooked PhysX shape, publication performance, or behavior of all chunks','command':sys.argv,'script_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
    (root/'bucket_action_verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8');print(json.dumps(report,ensure_ascii=False,indent=2))
    return 0 if report['dynamic_edit_pair_pass'] else 2
if __name__=='__main__':sys.exit(main())
