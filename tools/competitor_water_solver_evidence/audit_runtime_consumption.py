"""Match a captured six-kernel chain to one unique CPU parameter snapshot chain."""
import argparse
import collections
import datetime
import json
import shutil
import struct
from pathlib import Path
from evidence_contract import identity
from audit_runtime_pilot import closure,property_value,water_events

def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--runtime',required=True,type=Path);ap.add_argument('--replay',required=True,type=Path);ap.add_argument('--output',required=True,type=Path);args=ap.parse_args();out=args.output.resolve()
    if not str(out).isascii():raise ValueError('ASCII output required')
    out.mkdir(parents=True,exist_ok=False)
    for name in ['audit_runtime_consumption.py','audit_runtime_pilot.py','evidence_contract.py']:shutil.copyfile(Path(__file__).parent/name,out/name)
    raw=json.loads((args.runtime/'logs/events.json').read_text());events=water_events(raw)
    stats=json.loads((args.runtime/'observer_final.json').read_text());errors=closure(events,stats)
    replay=json.loads((args.replay/'manifest.json').read_text());gpu=replay['events'];cpu=[e for e in events if e['kind']=='dispatch_enter']
    if replay['operation_status']!='complete' or replay['errors']:errors.append('GPU_REPLAY_INCOMPLETE')
    captures=json.loads((args.runtime/'capture_final.json').read_text())['captures']
    if not any(identity(x['path'])['sha256']==replay['source']['sha256'] for x in captures):errors.append('CAPTURE_IDENTITY_MISMATCH')
    stages={'floor':'UpdateFloor','velocity':'VelocityIntegration','water':'HeightIntegration','advection':'Advection','sources':'UpdateAmount','normal':'UpdateTangent'}
    sources=[g for g in gpu if g['logical_stage']=='sources']
    if len(sources)!=1:raise ValueError('Pilot expects exactly one captured source update, do not select arbitrarily')
    play=sources[0]['parameters']['play_time']['value'];candidates=[i for i,d in enumerate(cpu) if d['kernel_name']=='UpdateAmount' and property_value(d,'playTime','global_parameters')==play]
    if len(candidates)!=1:raise ValueError('CPU_PHASE_NOT_UNIQUE:'+str(candidates))
    i=candidates[0];begin=i
    while begin>=0 and cpu[begin]['kernel_name']!='UpdateFloor':begin-=1
    end=i
    while end<len(cpu) and cpu[end]['kernel_name']!='UpdateTangent':end+=1
    chain=cpu[begin:end+1]
    if len(chain)!=len(gpu) or [d['kernel_name'] for d in chain]!=[stages[g['logical_stage']] for g in gpu]:errors.append('CHAIN_ORDER_MISMATCH')
    mapping={'integration_dt':('parameters','deltaTime',None),'source_dt':('parameters','deltaTime',None),'gravity':('parameters','gravityForce',None),'max_velocity':('parameters','maxVelocity',None),'damping':('parameters','damping',None),'kappa':('parameters','kappa',None),'advection_factor':('parameters','advectionFactor',None),'evaporation_factor':('parameters','evaporationFactor',None),'wave_amplitude':('parameters','waveAmplitude',None),'custom_wave':('parameters','customWave',None),'level':('parameters','level',None),'play_time':('global_parameters','playTime',None),'grid_width':('global_parameters','waterResolution',0),'grid_height':('global_parameters','waterResolution',1),'air_grid_width':('global_parameters','airResolution',0),'air_grid_height':('global_parameters','airResolution',1),'cell_x':('global_parameters','waterCellSize',0),'cell_z':('global_parameters','waterCellSize',1),'inverse_cell_x':('global_parameters','waterCellSize',2),'inverse_cell_z':('global_parameters','waterCellSize',3)}
    checks=[];unmapped=[]
    for g,d in zip(gpu,chain):
        checks.append(dict(kind='groups',event_id=g['event_id'],cpu_seq=d['seq'],gpu=g['groups'],cpu=d['groups'],equal=g['groups']==d['groups']))
        for name,field in g['parameters'].items():
            if name not in mapping:unmapped.append(dict(event_id=g['event_id'],field=name,value=field['value']));continue
            scope,prop,component=mapping[name];value=property_value(d,prop,scope)
            if component is not None:value=value[component] if isinstance(value,list) and len(value)>component else None
            equal=value is not None and struct.pack('<f',value)==struct.pack('<f',field['value'])
            checks.append(dict(kind='parameter',event_id=g['event_id'],cpu_seq=d['seq'],kernel=g['logical_stage'],gpu_field=name,cpu_property=prop,cpu_component=component,gpu_value=field['value'],cpu_value=value,equal=equal,gpu_constant_artifact=field['artifact_id'],gpu_byte_offset=field['byte_offset_in_cb']))
    if any(not c['equal'] for c in checks):errors.append('CPU_GPU_PARAMETER_MISMATCH')
    source=sources[0];source_cpu=cpu[i];cb=(args.replay/source['constants'][0]['artifact_id']).read_bytes();vector=struct.unpack_from('<4f',cb,125*16)
    matches=[v['property'] for v in source_cpu['global_parameters'].values() if isinstance(v.get('value'),list) and len(v['value'])==4 and struct.pack('<4f',*v['value'])==struct.pack('<4f',*vector)]
    identity_errors=[]
    for directory in [args.runtime,args.replay]:
        manifest=json.loads((directory/'manifest.json').read_text())
        for expected in manifest.get('artifacts',[])+manifest.get('file_inventory',[]):
            actual=identity(expected['path'])
            if actual['sha256']!=expected['sha256'] or actual['size_bytes']!=expected['size_bytes']:identity_errors.append(expected['path'])
    if identity_errors:errors.append('ARTIFACT_IDENTITY_MISMATCH')
    result=dict(operation_status='complete',verification_status='passed' if not errors else 'failed',scope='Single captured frame and uniquely matched CPU chain only; not G4 clock or observer perturbation acceptance',runtime=identity(args.runtime/'manifest.json'),replay=identity(args.replay/'manifest.json'),capture=replay['source'],renderdoc_frame_number=replay['frame_number'],cpu_shader_global_frameCount=property_value(source_cpu,'frameCount','global_parameters'),cpu_source_seq=source_cpu['seq'],cpu_source_call_id=source_cpu['call_id'],playTime=play,matched_cpu_chain=[{k:d[k] for k in ['seq','call_id','qpc','kernel_name','groups','shader']} for d in chain],gpu_chain=[dict(event_id=g['event_id'],stage=g['logical_stage'],program=g['shader_sha256'],bindings=g['bindings']) for g in gpu],checks=checks,unmapped_parameters=unmapped,cb125_vector=list(vector),cpu_global_vector_exact_matches=matches,cb125_interpretation='Exact full-vector correspondence is an observed fact; sunColor-to-slot semantics remain a sample-limited inference, not a separately named lightFactor setter',artifact_identity_errors=identity_errors,errors=errors,confidence=dict(raw_cpu_and_gpu_fields='C3',unique_phase_and_order_correspondence='C2',unobserved_frames_and_pointer_to_resource_mapping='C0'))
    (out/'consumption.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    manifest=dict(operation_status='complete',verification_status=result['verification_status'],created_at=datetime.datetime.now(datetime.timezone.utc).isoformat(),errors=errors,artifacts=[identity(p) for p in out.iterdir() if p.is_file()])
    (out/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
    print(json.dumps(dict(checks=len(checks),mismatches=sum(not x['equal'] for x in checks),unmapped=unmapped,cb125_matches=matches,errors=errors)))
    raise SystemExit(1 if errors else 0)

if __name__=='__main__':main()
