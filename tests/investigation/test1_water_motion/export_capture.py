"""Read-only test1 water compute/state export. Run with qrenderdoc --python."""
import hashlib
import json
import os
import struct
import traceback
from pathlib import Path

ROOT = Path('D:/godot/project/sandcastle')
OUT = Path(os.environ.get('TEST1_WATER_MOTION_OUTPUT', str(ROOT / 'test_output/test1_water_motion/capture_v1')))
SOURCE = ROOT / 'sandcastlegame/test1.rdc'
SCRIPT = ROOT / 'tests/investigation/test1_water_motion/export_capture.py'
EXPECTED = '761aa980c2426f75a1fa7364bf6d2655ff4dd20ea76566e630ee5b53ea0ec5b2'
EVENTS = [1484,1490,1495,1500,1505,1510,1515,1520,1525,1530,1537,1543,6083,1490]
OUT.mkdir(parents=True, exist_ok=False)
(OUT / 'raw').mkdir()

def identity(p):
    return {'path': str(p), 'bytes': p.stat().st_size, 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()}

report = {'source':identity(SOURCE), 'script':identity(SCRIPT), 'events':[], 'exports':[],
          'scope':'Independent replay for each selector; captured water/bed/visual data only. No elapsed wall-clock claim.'}

def export(data, selector, kind):
    raw = bytes(data)
    digest = hashlib.sha256(raw).hexdigest()
    suffix = '.txt' if kind == 'disassembly' else '.bin'
    p = OUT / 'raw' / (digest + suffix)
    if not p.exists():
        p.write_bytes(raw)
    row = dict(identity(p),selector=selector,kind=kind)
    report['exports'].append(row)
    return row

def flatten(actions):
    for action in actions:
        yield action
        yield from flatten(action.children)

try:
    import renderdoc as rd
    assert report['source']['sha256'] == EXPECTED
    report['tool'] = {'version':rd.GetVersionString(), 'command':'D:/other_software/RenderDoc/qrenderdoc.exe --python '+str(SCRIPT)}
    for sample,event in enumerate(EVENTS):
        cap = rd.OpenCaptureFile()
        controller = None
        try:
            status = cap.OpenFile(str(SOURCE),'',None)
            status,controller = cap.OpenCapture(rd.ReplayOptions(),None)
            if controller is None:
                raise RuntimeError(str(status))
            actions = {a.eventId:a for a in flatten(controller.GetRootActions())}
            controller.SetFrameEvent(event,True)
            pipe = controller.GetPipelineState()
            stage = rd.ShaderStage.Vertex if event == 6083 else rd.ShaderStage.Compute
            refl = pipe.GetShaderReflection(stage)
            row = {'sample':sample,'event':event,'selection':'Fresh OpenCapture; SetFrameEvent(event, True), post-event',
                   'stage':str(stage),'constants':[], 'bindings':[]}
            report['events'].append(row)
            if event != 6083:
                row['groups'] = list(actions[event].dispatchDimension)
                row['threads'] = list(refl.dispatchThreadsDimension)
            row['bytecode'] = export(refl.rawBytes,'E%d %s shader'%(event,stage),'compiled_shader')
            pobj = pipe.GetGraphicsPipelineObject() if event == 6083 else pipe.GetComputePipelineObject()
            row['instructions'] = export(controller.DisassembleShader(pobj,refl,'').encode('utf-8'), 'E%d %s disassembly'%(event,stage),'disassembly')
            for i,block in enumerate(refl.constantBlocks):
                d = pipe.GetConstantBlock(stage,i,0).descriptor
                size = min(d.byteSize,block.byteSize)
                raw = controller.GetBufferData(d.resource,d.byteOffset,size)
                row['constants'].append({'index':i,'name':block.name,'resource':str(d.resource),'offset':d.byteOffset,'bytes':size,
                    'float4':[list(struct.unpack_from('<4f',bytes(raw),n)) for n in range(0,size-15,16)],
                    'raw':export(raw,'E%d %s cb%d offset%d bytes%d'%(event,stage,i,d.byteOffset,size),'constant_bytes')})
            textures = {t.resourceId:t for t in controller.GetTextures()}
            for label,resources in [('readonly',pipe.GetReadOnlyResources(stage)),('readwrite',pipe.GetReadWriteResources(stage))]:
                definitions = refl.readOnlyResources if label == 'readonly' else refl.readWriteResources
                for used in resources:
                    d = used.descriptor
                    br = {'access':label,'index':used.access.index,'name':definitions[used.access.index].name,
                          'resource':str(d.resource),'offset':d.byteOffset,'bytes':d.byteSize,'type':str(d.type)}
                    row['bindings'].append(br)
                    if d.resource in textures:
                        t = textures[d.resource]
                        br['texture'] = {'width':t.width,'height':t.height,'depth':t.depth,'mips':t.mips,'format':t.format.Name()}
                        if t.width*t.height*t.depth <= 1024*1024:
                            br['raw'] = export(controller.GetTextureData(d.resource,rd.Subresource()),'E%d %s %s mip0 slice0 sample0'%(event,stage,d.resource),'raw_texels')
                    elif 0 < d.byteSize <= 16*1024*1024:
                        br['raw'] = export(controller.GetBufferData(d.resource,d.byteOffset,d.byteSize),'E%d %s %s %s offset%d bytes%d'%(event,stage,label,d.resource,d.byteOffset,d.byteSize),'runtime_buffer')
            (OUT/'progress.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
        finally:
            if controller is not None: controller.Shutdown()
            cap.Shutdown()
    report['source_after'] = identity(SOURCE)
    report['pass'] = report['source'] == report['source_after']
except Exception:
    report['error'] = traceback.format_exc()
finally:
    (OUT/'manifest.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
os._exit(0 if report.get('pass') else 1)
