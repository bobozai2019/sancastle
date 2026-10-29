"""Locate known original water programs independently in one RDC; export parameters.

Run through run_replay.py; no inherited event IDs or resource IDs are used.
"""
import hashlib
import json
import math
import os
import shutil
import struct
import traceback
from pathlib import Path

REQUEST=Path(os.environ['WATER_EVIDENCE_REQUEST']);SCRIPT=Path(os.environ['WATER_EVIDENCE_SCRIPT'])
req=json.loads(REQUEST.read_text(encoding='utf-8'));OUT=Path(req['output_root'])
if not OUT.is_absolute() or not str(OUT).isascii():raise ValueError('Absolute ASCII output required')
OUT.mkdir(parents=True,exist_ok=False)
for name in ['raw','derived','sources','logs']:(OUT/name).mkdir()
KNOWN={'f6f8c17d743aa60c2fa01cf4cd0a9a03ab1bddad297da2a8f729aef6356d6bc3':'floor',
 '9e5c7da8738200d374076a6cc3b48be52fdbad70e8c8dc2bd27eb75431d30523':'velocity',
 '549114c23f1921610bacaf1d9ae375814fda1fb1de492cc2a4acfc53a502c64f':'water',
 'b2794ecb18de815ff607fffd734ff4cde859bab1efd7fa3dfe9a24eb5a9f7a3c':'advection',
 'a61d34e411e8eee5c795bf233908a9b2a5b85ee272f5d0fbcb1481da27a62b80':'sources',
 '38a7f089261c54713b583b0f9a6bdd876d09cdb7859e64a804c06e08d64fa2a6':'normal'}


def identity(path):
    digest=hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda:f.read(8*1024*1024),b''):digest.update(chunk)
    return dict(path=path.as_posix(),size_bytes=path.stat().st_size,sha256=digest.hexdigest())


def write(name,data):(OUT/name).write_text(json.dumps(data,indent=2,ensure_ascii=True),encoding='utf-8')


report=dict(schema_version='1.0',run_id=req['run_id'],operation_status='failed',verification_status='not_evaluated',
    artifacts=[],errors=[],events=[],dispatch_inventory=[],clocks=[],unknowns=[],pairing_kind='unproven',
    scope='Independent program-hash relocation and post-event constants/binding/state. No elapsed-time or continuous-sequence inference.')


def save(name,data,kind,selector):
    path=OUT/name;payload=bytes(data)
    if not path.exists():path.write_bytes(payload)
    elif path.read_bytes()!=payload:raise ValueError('ARTIFACT_NAME_COLLISION')
    actual=dict(identity(path),artifact_id=name,kind=kind,source_ids=[req['source']['source_id']],parent_artifact_ids=[],selector=selector,completeness='complete')
    if not any(a['artifact_id']==name for a in report['artifacts']):report['artifacts'].append(actual)
    return actual


cap=controller=None
try:
    import renderdoc as rd
    source=Path(req['source']['source_path']);report['source']=identity(source)
    if report['source']['sha256']!=req['source']['source_sha256'] or report['source']['size_bytes']!=req['source']['source_size']:raise ValueError('SOURCE_IDENTITY_MISMATCH')
    for path in [SCRIPT,REQUEST]:shutil.copyfile(path,OUT/'sources'/path.name)
    report['tool']=dict(version=rd.GetVersionString(),script=identity(SCRIPT),request=identity(REQUEST),executable=identity(Path('D:/other_software/RenderDoc/qrenderdoc.exe')))
    cap=rd.OpenCaptureFile();report['open_file']=str(cap.OpenFile(str(source),'',None));status,controller=cap.OpenCapture(rd.ReplayOptions(),None)
    report['open_capture']=str(status)
    if controller is None:raise RuntimeError(str(status))
    report['backend']=str(controller.GetAPIProperties().pipelineType)
    report['replay_vendor']=str(controller.GetAPIProperties().vendor)
    if hasattr(controller,'GetFrameInfo'):
        info=controller.GetFrameInfo();report['frame_number']=getattr(info,'frameNumber',None)
    sf=controller.GetStructuredFile()
    def flatten(items):
        for a in items:
            yield a
            for child in flatten(a.children):yield child
    actions=[a for a in flatten(controller.GetRootActions()) if a.flags&rd.ActionFlags.Dispatch]
    textures={t.resourceId:t for t in controller.GetTextures()}
    for ordinal,action in enumerate(actions):
        write('logs/progress.json',dict(phase='scan_dispatch',ordinal=ordinal,total=len(actions),event_id=action.eventId))
        controller.SetFrameEvent(action.eventId,True);pipe=controller.GetPipelineState();stage=rd.ShaderStage.Compute
        refl=pipe.GetShaderReflection(stage)
        if refl is None:
            report['errors'].append(dict(code='MISSING_COMPUTE_REFLECTION',event_id=action.eventId));continue
        program_hash=hashlib.sha256(bytes(refl.rawBytes)).hexdigest();logical=KNOWN.get(program_hash)
        report['dispatch_inventory'].append(dict(event_id=action.eventId,ordinal=ordinal,shader_sha256=program_hash,logical_stage=logical,
             groups=list(action.dispatchDimension),threads=list(refl.dispatchThreadsDimension),shader_resource=str(pipe.GetShader(stage))))
        if logical is None:continue
        selector=dict(capture_sha256=report['source']['sha256'],event_id=action.eventId,stage='compute',boundary='post-dispatch',shader_sha256=program_hash)
        row=dict(selector,logical_stage=logical,ordinal=ordinal,groups=list(action.dispatchDimension),threads=list(refl.dispatchThreadsDimension),
                 shader_resource=str(pipe.GetShader(stage)),constants=[],bindings=[],parameters={})
        row['program']=save('raw/program_'+program_hash+'.dxbc',refl.rawBytes,'program',selector)
        for index,block in enumerate(refl.constantBlocks):
            d=pipe.GetConstantBlock(stage,index,0).descriptor;size=min(d.byteSize,block.byteSize)
            raw=bytes(controller.GetBufferData(d.resource,d.byteOffset,size))
            if len(raw)!=size or size<=0:raise ValueError('DEPENDENCY_MISSING:constant_extent')
            artifact=save('raw/e%d_cb%d.bin'%(action.eventId,index),raw,'raw_snapshot',dict(selector,binding='b%d'%index,resource=str(d.resource),byte_offset=d.byteOffset,byte_length=size,stride=1,element_count=size,format='bytes'))
            row['constants'].append(artifact)
            if index==0:
                def parameter(name,register,component,fmt='f',interpretation='matched executable constant slot'):
                    offset=register*16+component*4
                    if offset+4>len(raw):raise ValueError('CONSTANT_SLOT_MISSING:'+name)
                    value=struct.unpack_from('<'+fmt,raw,offset)[0]
                    if fmt=='f' and not math.isfinite(value):raise ValueError('NONFINITE_PARAMETER:'+name)
                    row['parameters'][name]=dict(value=value,cb=0,register=register,component=component,byte_offset_in_cb=offset,
                        actual_buffer_offset=d.byteOffset+offset,artifact_id=artifact['artifact_id'],interpretation=interpretation)
                parameter('grid_width',155,0,'I');parameter('grid_height',155,1,'I')
                if logical in ['velocity','water','advection']:
                    parameter('integration_dt',157,2)
                if logical in ['velocity','water']:
                    parameter('gravity',157,3)
                    for component,label in enumerate(['cell_x','cell_z','inverse_cell_x','inverse_cell_z']):parameter(label,154,component)
                if logical=='velocity':
                    parameter('max_velocity',158,0);parameter('damping',159,1);parameter('kappa',159,3)
                if logical=='advection':parameter('advection_factor',158,2)
                if logical=='sources':
                    parameter('source_dt',157,2);parameter('play_time',113,2,interpretation='Consumed by sin/play-phase instructions; mapping to wall time unknown')
                    parameter('air_grid_width',157,0,'I');parameter('air_grid_height',157,1,'I')
                    for name,r,c in [('evaporation_factor',158,1),('wave_amplitude',158,3),('custom_wave',159,0),('level',159,2),('light_factor',125,0)]:parameter(name,r,c)
        for access,resources in [('srv',pipe.GetReadOnlyResources(stage)),('uav',pipe.GetReadWriteResources(stage))]:
            for used in resources:
                d=used.descriptor;b=dict(access=access,index=used.access.index,resource=str(d.resource),byte_offset=d.byteOffset,byte_length=d.byteSize,
                    stride=d.elementByteSize,format=d.format.Name(),descriptor_type=str(d.type),first_mip=d.firstMip,first_slice=d.firstSlice,num_mips=d.numMips,num_slices=d.numSlices)
                if d.resource in textures:
                    t=textures[d.resource];b['texture']=dict(width=t.width,height=t.height,depth=t.depth,mips=t.mips,array_size=t.arraysize,format=t.format.Name())
                row['bindings'].append(b)
                if logical=='floor' and access=='uav' and used.access.index==0:
                    width=row['parameters']['grid_width']['value'];height=row['parameters']['grid_height']['value']
                    if d.elementByteSize!=16 or d.byteSize!=width*height*16:raise ValueError('SELECTOR_MISMATCH:water_layout')
                    water=bytes(controller.GetBufferData(d.resource,d.byteOffset,d.byteSize))
                    if len(water)!=d.byteSize:raise ValueError('DEPENDENCY_MISSING:water_extent')
                    row['water_snapshot']=save('raw/e%d_water.bin'%action.eventId,water,'raw_snapshot',dict(selector,resource=str(d.resource),byte_offset=d.byteOffset,byte_length=d.byteSize,stride=16,element_count=width*height,format='uint4'))
                    bed=bytearray(width*height*4);minimum=16777215;maximum=0
                    for i,(_,_,u2,u3) in enumerate(struct.iter_unpack('<4I',water)):
                        value=(u2>>24)|((u3&65535)<<8);struct.pack_into('<I',bed,i*4,value);minimum=min(minimum,value);maximum=max(maximum,value)
                    row['bed_codes']=save('derived/e%d_bed.u32'%action.eventId,bed,'decoded',dict(selector,byte_offset=0,byte_length=len(bed),stride=4,element_count=width*height,format='u24 code in u32',parent_artifact_id=row['water_snapshot']['artifact_id']))
                    row['bed_range_codes']=[minimum,maximum]
        report['events'].append(row);write('manifest_partial.json',report)
    report['source_after']=identity(source)
    if report['source_after']!=report['source']:raise ValueError('SOURCE_CHANGED')
    report['unknowns']=['Capture names and frame numbers do not establish a continuous execution or elapsed time',
        'Post-event state is replay-derived; no single-dispatch I/O pairing or original wall-clock rate claim']
    if not report['events']:report['unknowns'].append('No known water program matched; cannot locate a changed program by inherited event IDs')
    report['operation_status']='partial' if report['errors'] else 'complete'
except Exception:
    report['errors'].append(dict(code='MULTICAPTURE_EXCEPTION',message=traceback.format_exc()))
finally:
    if controller is not None:controller.Shutdown()
    if cap is not None:cap.Shutdown()
    report['file_inventory']=[identity(p) for p in OUT.rglob('*') if p.is_file() and p.name!='manifest.json']
    write('manifest.json',report)
os._exit(0 if report['operation_status']=='complete' else 1)
