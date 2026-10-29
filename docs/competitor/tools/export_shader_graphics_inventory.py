"""Mechanical whole-frame graphics shader inventory, without business-code analysis.

Export each compiled VS/PS/GS/HS/DS once by SHA256; keep draw-to-shader mapping.
"""
import hashlib
import json
import os
import traceback
from pathlib import Path

ROOT = Path('D:/godot/project/sandcastle')
SOURCE = ROOT/'sandcastlegame/test1.rdc'
SCRIPT = ROOT/'docs/competitor/tools/export_shader_graphics_inventory.py'
OUT = Path(os.environ['SHADER_GRAPHICS_OUT'])
assert OUT.is_absolute() and str(OUT).isascii()
OUT.mkdir(parents=True,exist_ok=False)

def identity(p):
    return dict(path=p.as_posix(),bytes=p.stat().st_size,sha256=hashlib.sha256(p.read_bytes()).hexdigest())

def write(name,data):
    (OUT/name).write_text(json.dumps(data,indent=2),encoding='utf-8')

report = dict(source=identity(SOURCE),script=identity(SCRIPT),events=[],shaders={},exports=[],success=False)
def save(name,data,selector):
    p=OUT/name
    p.write_bytes(bytes(data))
    item=dict(identity(p),selector=selector)
    report['exports'].append(item)
    return item

cap=controller=None
try:
    import renderdoc as rd
    assert report['source']['sha256']=='761aa980c2426f75a1fa7364bf6d2655ff4dd20ea76566e630ee5b53ea0ec5b2'
    report['version']=rd.GetVersionString()
    report['tool']=identity(Path('D:/other_software/RenderDoc/qrenderdoc.exe'))
    report['command']='D:/other_software/RenderDoc/qrenderdoc.exe --python '+SCRIPT.as_posix()
    report['environment']={'SHADER_GRAPHICS_OUT':str(OUT)}
    write('progress.json',dict(phase='open'))
    cap=rd.OpenCaptureFile()
    report['open']=str(cap.OpenFile(str(SOURCE),'',None))
    status,controller=cap.OpenCapture(rd.ReplayOptions(),None)
    report['replay']=str(status)
    assert controller is not None
    actions=[]
    def walk(items):
        for a in items:
            if a.flags & rd.ActionFlags.Drawcall: actions.append(a)
            walk(a.children)
    walk(controller.GetRootActions())
    cached={}
    for i,a in enumerate(actions):
        if i%25==0:write('progress.json',dict(phase='scan',index=i,total=len(actions),event=a.eventId,shaders=len(report['shaders'])))
        controller.SetFrameEvent(a.eventId,False)
        pipe=controller.GetPipelineState()
        row=dict(event=a.eventId,indices=a.numIndices,instances=a.numInstances,
                 outputs=[str(r) for r in a.outputs],depth=str(a.depthOut),stages={})
        for label,stage in [('vs',rd.ShaderStage.Vertex),('ps',rd.ShaderStage.Pixel),('gs',rd.ShaderStage.Geometry),('hs',rd.ShaderStage.Hull),('ds',rd.ShaderStage.Domain)]:
            rid=pipe.GetShader(stage)
            if rid==rd.ResourceId.Null():continue
            if rid not in cached:
                refl=pipe.GetShaderReflection(stage)
                raw=bytes(refl.rawBytes)
                digest=hashlib.sha256(raw).hexdigest()
                cached[rid]=digest
                if digest not in report['shaders']:
                    prefix='e%d_%s'%(a.eventId,label)
                    s=dict(stage=label,first_event=a.eventId,shader_resource=str(rid),constants=[],bindings=[])
                    s['bytecode']=save(prefix+'.dxbc',raw,'E%d %s rawBytes'%(a.eventId,label))
                    s['disassembly']=save(prefix+'.asm',controller.DisassembleShader(pipe.GetGraphicsPipelineObject(),refl,'').encode('utf-8'),'E%d %s disassembly'%(a.eventId,label))
                    for n,block in enumerate(refl.constantBlocks):
                        d=pipe.GetConstantBlock(stage,n,0).descriptor
                        length=min(d.byteSize,block.byteSize)
                        if length>0:
                            s['constants'].append(dict(index=n,resource=str(d.resource),offset=d.byteOffset,
                                raw=save(prefix+'_cb%d.bin'%n,controller.GetBufferData(d.resource,d.byteOffset,length),
                                         'E%d %s cb%d %s offset=%d bytes=%d'%(a.eventId,label,n,d.resource,d.byteOffset,length))))
                    for access,bound in [('read',pipe.GetReadOnlyResources(stage)),('readwrite',pipe.GetReadWriteResources(stage))]:
                        for used in bound:
                            d=used.descriptor
                            s['bindings'].append(dict(access=access,index=used.access.index,resource=str(d.resource),
                                firstMip=d.firstMip,numMips=d.numMips,offset=d.byteOffset,bytes=d.byteSize))
                    report['shaders'][digest]=s
            row['stages'][label]=cached[rid]
        report['events'].append(row)
    report['source_after']=identity(SOURCE)
    report['success']=report['source']==report['source_after'] and len(report['events'])==len(actions)
except Exception:
    report['error']=traceback.format_exc()
finally:
    if controller:controller.Shutdown()
    if cap:cap.Shutdown()
    write('manifest.json',report)
os._exit(0 if report['success'] else 1)
