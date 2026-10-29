"""Audit recorded input samples and camera endpoints, without inventing silence."""
import argparse,json,hashlib,sys
from pathlib import Path
import numpy as np
def main():
    p=argparse.ArgumentParser();p.add_argument('--run',required=True);a=p.parse_args();root=Path(a.run).resolve();rows=[json.loads(l) for l in (root/'messages.jsonl').read_text().splitlines()];ps=[r['message'].get('payload',{}) for r in rows]
    phases={x['phase']:x for x in ps if x.get('kind')=='capture_phase'};first=phases['no_input_a'];last=phases['no_input_b'];begin=int(first['qpc']);end=int(last['qpc']);assert end>begin
    inputs=[x for x in ps if x.get('kind')=='input_physics' and begin<=int(x['query_qpc'])<=end];assert inputs;freq=int(inputs[0]['qpc_frequency']);assert all(int(x['qpc_frequency'])==freq for x in inputs)
    same=all(first[k]==last[k] for k in ['camera_world_to_camera','camera_projection','pixel_width','pixel_height']);errors=[]
    for r in inputs:
        if not r['hit_bool']:continue
        clip=np.array(first['camera_projection']).reshape(4,4,order='F')@np.array(first['camera_world_to_camera']).reshape(4,4,order='F')@np.array(r['point_ws']+[1]);screen=(clip[:2]/clip[3]+1)/2*np.array([first['pixel_width'],first['pixel_height']]);errors.append(float(np.linalg.norm(screen-r['screen_position'])))
    raw={(r['message']['payload']['snapshot_id'],r['message']['payload']['payload_kind']):r['raw']['path'] for r in rows if r['message'].get('payload',{}).get('kind')=='raw'}
    v=[np.fromfile(raw[x['snapshot_id'],'vertices'],dtype='<f4').reshape(-1,3) for x in [first,last]];assert v[0].shape==v[1].shape;dy=v[1][:,1]-v[0][:,1]
    times=[begin]+[int(x['query_qpc']) for x in inputs]+[end]
    report={'before_snapshot':first['snapshot_id'],'after_snapshot':last['snapshot_id'],'qpc_begin':str(begin),'qpc_end':str(end),'qpc_frequency':str(freq),'seconds':(end-begin)/freq,'camera_endpoint_matrices_equal':same,'sample_count':len(inputs),'sampled_left_pressed_count':sum(r['left_button_pressed'] is True for r in inputs),'sampled_left_unknown_count':sum(r['left_button_pressed'] is None for r in inputs),'maximum_sample_gap_seconds':max(np.diff(times))/freq,'reprojection_error_max_pixels':max(errors) if errors else None,'xz_unchanged':bool(np.array_equal(v[0][:,[0,2]],v[1][:,[0,2]])),'changed_y_vertices':int(np.count_nonzero(dy)),'delta_y_min':float(dy.min()),'delta_y_max':float(dy.max()),'operator_confirmed_no_input':False,'all_input_channels_silent_proven':False,'controlled_edit_pass':False,'interpretation':'observed camera endpoints and sampled mouse state only; unsampled brief input/other channels not excluded; temporal geometry change is not a brush-causality proof','command':sys.argv,'script_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
    (root/'control_interval_verification.json').write_text(json.dumps(report,indent=2),encoding='utf8');print(json.dumps(report,indent=2))
if __name__=='__main__':main()
