"""Verify relocated constants and compare capture-local water parameters only."""
import argparse
import collections
import itertools
import json
import shutil
import struct
from pathlib import Path
import numpy as np
from evidence_contract import identity


def write(path,data):path.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--selection',required=True,type=Path);p.add_argument('--output',required=True,type=Path)
    args=p.parse_args();out=args.output
    if not out.is_absolute() or not str(out).isascii():raise ValueError('Absolute ASCII output required')
    out.mkdir(parents=True,exist_ok=False)
    for name in ['sources','raw','derived','logs']:(out/name).mkdir()
    selection=json.loads(args.selection.read_text());errors=[];matrix=[];mapping=[];checks=[];beds=[]
    for spec in selection['requests']:
        request_path=Path(spec['request']['path']);request=json.loads(request_path.read_text());root=Path(request['output_root'])
        manifest=json.loads((root/'manifest.json').read_text())
        if manifest['operation_status']!='complete' or manifest['errors']:errors.append(dict(code='CAPTURE_EXPORT_INCOMPLETE',capture=spec['capture']))
        if manifest['source']['sha256']!=request['source']['source_sha256'] or manifest['source']!=manifest.get('source_after'):errors.append(dict(code='SOURCE_CHANGED',capture=spec['capture']))
        for artifact in manifest['file_inventory']:
            actual=identity(artifact['path']);passed=actual['sha256']==artifact['sha256'] and actual['size_bytes']==artifact['size_bytes']
            checks.append(dict(path=artifact['path'],passed=passed))
            if not passed:errors.append(dict(code='ARTIFACT_CHANGED',path=artifact['path']))
        events=manifest['events'];counts=collections.Counter(e['logical_stage'] for e in events)
        for event in events:
            if event['capture_sha256']!=manifest['source']['sha256']:errors.append(dict(code='CROSS_CAPTURE_SELECTOR'))
            for name,parameter in event['parameters'].items():
                cb=event['constants'][parameter['cb']];data=Path(cb['path']).read_bytes()
                fmt='<I' if name.endswith('_width') or name.endswith('_height') else '<f'
                value=struct.unpack_from(fmt,data,parameter['register']*16+parameter['component']*4)[0]
                if value!=parameter['value']:errors.append(dict(code='PARAMETER_DECODE_MISMATCH',capture=spec['capture'],event=event['event_id'],parameter=name))
                if parameter['actual_buffer_offset']!=cb['selector']['byte_offset']+parameter['byte_offset_in_cb']:errors.append(dict(code='PARAMETER_SELECTOR_MISMATCH'))
            grid=[event['parameters']['grid_width']['value'],event['parameters']['grid_height']['value']]
            water=[b for b in event['bindings'] if b['access']=='uav' and b['index']==0]
            if len(water)!=1 or water[0]['stride']!=16 or water[0]['byte_length']!=grid[0]*grid[1]*16:errors.append(dict(code='WATER_LAYOUT_MISMATCH',capture=spec['capture'],event=event['event_id']))
            mapping.append(dict(capture=spec['capture'],capture_sha256=manifest['source']['sha256'],event=event,
                                program=event['program'],bindings=event['bindings'],parent_manifest=identity(root/'manifest.json')))
            if 'bed_codes' in event:
                bed=np.fromfile(event['bed_codes']['path'],dtype='<u4')
                if bed.size!=grid[0]*grid[1]:errors.append(dict(code='BED_EXTENT_MISMATCH'))
                beds.append(dict(capture=spec['capture'],event_id=event['event_id'],grid=grid,artifact=event['bed_codes'],range_codes=[int(bed.min()),int(bed.max())]))
        rounds=counts.get('water',0)
        sequence=[e['logical_stage'] for e in events]
        single_chain=sequence==['floor']+['velocity','water','advection']*rounds+['sources','normal']
        chains=[]
        starts=[i for i,e in enumerate(events) if e['logical_stage']=='floor']
        for chain_index,start in enumerate(starts):
            segment=events[start:starts[chain_index+1] if chain_index+1<len(starts) else len(events)]
            chain_rounds=sum(e['logical_stage']=='water' for e in segment)
            expected=['floor']+['velocity','water','advection']*chain_rounds+['sources','normal']
            layout_keys=set()
            for e in segment:
                u=next(b for b in e['bindings'] if b['access']=='uav' and b['index']==0)
                layout_keys.add((u['resource'],u['byte_offset'],u['byte_length'],u['stride']))
            chains.append(dict(chain_index=chain_index,event_ids=[e['event_id'] for e in segment],rounds=chain_rounds,
                sequence_matches=[e['logical_stage'] for e in segment]==expected,single_water_view=len(layout_keys)==1,
                water_views=[dict(resource=k[0],byte_offset=k[1],byte_length=k[2],stride=k[3]) for k in sorted(layout_keys)],
                integration_dt_sum=sum(e['parameters']['integration_dt']['value'] for e in segment if e['logical_stage']=='water'),
                sources=[dict(event_id=e['event_id'],parameters=e['parameters']) for e in segment if e['logical_stage']=='sources']))
        source_rows=[dict(event_id=e['event_id'],parameters=e['parameters'],constants=e['constants']) for e in events if e['logical_stage']=='sources']
        water_rows=[e for e in events if e['logical_stage']=='water']
        matrix.append(dict(capture=spec['capture'],capture_sha256=manifest['source']['sha256'],captured_frame_number=manifest.get('frame_number'),
            parent_manifest=identity(root/'manifest.json'),backend=manifest['backend'],replay_vendor=manifest['replay_vendor'],
            all_compute_dispatches=len(manifest['dispatch_inventory']),water_kernel_counts=dict(counts),single_chain=single_chain,
            propagation_rounds=rounds if single_chain else None,
            chains=chains,complete_chain_count=len(chains) if all(c['sequence_matches'] and c['single_water_view'] for c in chains) else None,
            integration_dt_values=sorted(set(e['parameters']['integration_dt']['value'] for e in water_rows)),
            summed_amount_integration_dt=sum(e['parameters']['integration_dt']['value'] for e in water_rows),
            source_invocations=source_rows,clock_mapping='unknown',scene_identity='not established',
            all_programs_relocated_from_hash=True,pairing_kind='unproven'))
    bed_comparisons=[]
    for left,right in itertools.combinations(beds,2):
        if left['grid']!=right['grid']:
            bed_comparisons.append(dict(left=left['capture'],right=right['capture'],comparable=False,reason='Grid differs'));continue
        a=np.fromfile(left['artifact']['path'],dtype='<u4').astype(np.int64);b=np.fromfile(right['artifact']['path'],dtype='<u4').astype(np.int64)
        delta=np.abs(a-b);i=int(np.argmax(delta))
        bed_comparisons.append(dict(left=left['capture'],right=right['capture'],comparable=True,changed_cells=int(np.count_nonzero(delta)),
            max_code_difference=int(delta[i]),max_coordinate=[i%left['grid'][0],i//left['grid'][0]],
            interpretation='Replay-derived visible bed difference only; does not prove scene identity, erosion causality or elapsed time'))
    questions=[dict(id='T04-Q01',question='What chooses three versus four propagation rounds while source_dt can remain .025?',
        hypotheses=['Residual/accumulator or catch-up policy','Different runtime configuration or simulation condition'],
        distinguishing_observation='Continuous ordered water Dispatch/QPC/parameter log, source invocation boundaries, consumed integration_dt/source_dt and GPU constant spot checks'),
        dict(id='T04-Q02',question='How do play_time and integration/source clocks map to QPC, pause or reset?',
             distinguishing_observation='Monotonic time log with segmentation on reset; do not use frame filenames as seconds'),
        dict(id='T04-Q03',question='What is custom_wave lifetime and effective setting precedence?',
             distinguishing_observation='Targeted ComputeShader/CommandBuffer/global parameter settings paired to actual water dispatch and GPU constants; no business-call tracing'),
        dict(id='T04-Q04',question='Is wave_amplitude time-dependent, configuration-dependent or both?',
             distinguishing_observation='Controlled repeatable runtime windows and actual consumed values, independent of changed bed or camera'),
        dict(id='T04-Q05',question='Which visible-bed changes are persistent inputs versus replay variation?',
             distinguishing_observation='Timestamped dependency identity with fixed initialization and rare GPU snapshots; capture-local bed hash alone is insufficient')]
    questions.append(dict(id='T04-Q06',question='Why can a single captured frame contain two full cycles on the same water buffer, with identical play_time?',
        hypotheses=['Catch-up/accumulator scheduling','Additional scheduling under particular input or simulation conditions','Frame-cached global phase distinct from simulation advances'],
        distinguishing_observation='Continuous engine/graphics-boundary trace pairing water-buffer binding, cycle boundaries, QPC and effective parameters; do not infer or investigate business call chains'))
    write(out/'derived/parameter_matrix.json',matrix);write(out/'derived/capture_stage_map.json',mapping)
    write(out/'derived/bed_comparisons.json',dict(beds=beds,comparisons=bed_comparisons));write(out/'derived/runtime_questions.json',questions)
    write(out/'derived/file_checks.json',checks)
    for name in ['analyze_capture_parameters.py','evidence_contract.py']:
        shutil.copyfile(Path(__file__).with_name(name),out/'sources'/name)
    write(out/'manifest.json',dict(schema_version='1.0',run_id=out.name,operation_status='complete',verification_status='failed' if errors else 'passed',
        selection=identity(args.selection),errors=errors,artifacts=[identity(p) for p in out.rglob('*') if p.is_file()],
        scope='T04 capture-local relocation/parameter comparison and T05 questions; no wall-clock rate or continuous trajectory claim'))
    print(json.dumps(dict(errors=errors,captures=len(matrix),summary=[dict(capture=r['capture'],rounds=r['propagation_rounds'],integration_sum=r['summed_amount_integration_dt']) for r in matrix])),flush=True)
    raise SystemExit(1 if errors else 0)


if __name__=='__main__':main()
