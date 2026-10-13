"""Read-only test41 compute verification; run with qrenderdoc --python."""
import hashlib
import json
import os
import traceback
from pathlib import Path

ROOT=Path('D:/godot/project/sandcastle')
OUT=ROOT/'test_output/competitor_edit_compute_20261012_v2'
SOURCE=ROOT/'sandcastlegame/test41.rdc'
EXPECTED='f1794a7235a79f7a73bd6f4085bef7ecbb3a7dc39ce8a8a7aac955ee5beb3c0d'
OUT.mkdir(parents=True,exist_ok=True)
def identity(p):
    return {'path':str(p),'size':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
report={'pass':False,'source':identity(SOURCE),'script':identity(ROOT/'docs/competitor/tools/reverify_edit_compute.py'),'exports':[],'events':[],
        'scope':'Captured compute stages only. No business code, no CPU scheduling or performance claim.'}
def export(name,data,selector,kind):
    p=OUT/name;p.write_bytes(bytes(data))
    row=dict(identity(p),selector=selector,kind=kind);report['exports'].append(row);return row
def flatten(actions):
    for a in actions:
        yield a
        yield from flatten(a.children)
capture=controller=None
try:
    import renderdoc as rd
    if report['source']['sha256']!=EXPECTED:raise RuntimeError('capture identity mismatch')
    report['version']=rd.GetVersionString()
    capture=rd.OpenCaptureFile();report['open']=str(capture.OpenFile(str(SOURCE),'',None))
    status,controller=capture.OpenCapture(rd.ReplayOptions(),None);report['replay']=str(status)
    if controller is None:raise RuntimeError(str(status))
    actions={a.eventId:a for a in flatten(controller.GetRootActions())}
    for event in [863,878,1210]:
        controller.SetFrameEvent(event,True)
        pipe=controller.GetPipelineState();stage=rd.ShaderStage.Compute
        refl=pipe.GetShaderReflection(stage)
        if refl is None:raise RuntimeError('missing compute reflection at '+str(event))
        row={'event':event,'selection':'SetFrameEvent(event, True), post-event',
             'groups':list(actions[event].dispatchDimension),'threads_per_group':list(refl.dispatchThreadsDimension),
             'shader':str(pipe.GetShader(stage)),'encoding':str(refl.encoding),'constants':[],
             'readonly':[r.name for r in refl.readOnlyResources],
             'readwrite':[r.name for r in refl.readWriteResources],'bindings':[]}
        report['events'].append(row)
        row['bytecode']=export('e%d_cs.bin'%event,refl.rawBytes,'test41 E%d compute rawBytes'%event,'compiled_shader')
        dis=controller.DisassembleShader(pipe.GetComputePipelineObject(),refl,'')
        row['instructions']=export('e%d_cs_disassembly.txt'%event,dis.encode('utf-8'),'test41 E%d compute automatic disassembly'%event,'derived_disassembly')
        for i,block in enumerate(refl.constantBlocks):
            bound=pipe.GetConstantBlock(stage,i,0).descriptor
            size=min(bound.byteSize,block.byteSize)
            raw=controller.GetBufferData(bound.resource,bound.byteOffset,size)
            row['constants'].append({'index':i,'name':block.name,'resource':str(bound.resource),'offset':bound.byteOffset,'size':size,
                                     'raw':export('e%d_cb%d.bin'%(event,i),raw,'test41 E%d CS constant block %d offset %d size %d'%(event,i,bound.byteOffset,size),'constant_bytes')})
        for label,resources in [('readonly',pipe.GetReadOnlyResources(stage)),('readwrite',pipe.GetReadWriteResources(stage))]:
            for used in resources:
                d=used.descriptor
                row['bindings'].append({'access':label,'index':used.access.index,'resource':str(d.resource),'offset':d.byteOffset,'size':d.byteSize,'type':str(d.type)})
    report['source_after']=identity(SOURCE)
    report['pass']=report['source_after']==report['source'] and report['events'][0]['bytecode']['sha256']=='d37af2736147fd90f62ecbf8230bb0162a961ba2b16bce44a29d02fb2cdb30aa'
except Exception:
    report['error']=traceback.format_exc()
finally:
    if controller is not None:controller.Shutdown()
    if capture is not None:capture.Shutdown()
    (OUT/'manifest.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
os._exit(0 if report['pass'] else 1)
