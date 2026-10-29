"""Narrow read-only pixel debug and sampler/state probe; run in qrenderdoc embedded Python."""
import hashlib, json, os, traceback
from pathlib import Path
ROOT=Path('D:/godot/project/sandcastle')
OUT=ROOT/'test_output/competitor_water_material_20261011/pixel_v2'
OUT.mkdir(parents=True,exist_ok=True)
source=ROOT/'sandcastlegame/test1.rdc'
report={'pass':False,'capture':{'path':str(source),'bytes':source.stat().st_size,'sha256':hashlib.sha256(source.read_bytes()).hexdigest()},'events':[]}
capture=controller=None

def plain(obj):
    row={}
    for k in dir(obj):
        if k.startswith('_') or k in ('this','thisown'):continue
        try:
            v=getattr(obj,k)
            if callable(v):continue
            row[k]=v if isinstance(v,(str,int,float,bool)) else str(v)
        except Exception as e:row[k]=repr(e)
    return row

def variable(v):
    return {'name':v.name,'rows':v.rows,'columns':v.columns,'f32':list(v.value.f32v),'u32':list(v.value.u32v)}

try:
    import renderdoc as rd
    if report['capture']['sha256']!='761aa980c2426f75a1fa7364bf6d2655ff4dd20ea76566e630ee5b53ea0ec5b2':raise RuntimeError('capture identity mismatch')
    script=ROOT/'docs/competitor/tools/probe_water_pixel.py'
    report['tool']={'version':rd.GetVersionString(),'script_sha256':hashlib.sha256(script.read_bytes()).hexdigest(),'command':'D:/other_software/RenderDoc/qrenderdoc.exe --python '+str(script)}
    capture=rd.OpenCaptureFile();capture.OpenFile(str(source),'',None)
    status,controller=capture.OpenCapture(rd.ReplayOptions(),None)
    report['replay']=str(status)
    if controller is None:raise RuntimeError(str(status))
    report['continue_doc']=controller.ContinueDebug.__doc__
    for event in (5006,6083):
        controller.SetFrameEvent(event,True);pipe=controller.GetPipelineState()
        d3d=controller.GetD3D12PipelineState()
        row={'event':event,'samplers':[],'output_merger':plain(d3d.outputMerger)}
        report['events'].append(row)
        om=d3d.outputMerger
        row['blend']=plain(om.blendState)
        row['blend_targets']=[dict(plain(t),color_equation=plain(t.colorBlend),alpha_equation=plain(t.alphaBlend)) for t in om.blendState.blends]
        row['depth_stencil']=plain(om.depthStencilState)
        row['depth_stencil']['depthFunction_name']=str(om.depthStencilState.depthFunction)
        for used in pipe.GetSamplers(rd.ShaderStage.Pixel):
            sampler=used.sampler
            row['samplers'].append({'index':used.access.index,'sampler':plain(sampler),
                                    'filter':plain(sampler.filter),'address_names':[str(sampler.addressU),str(sampler.addressV),str(sampler.addressW)],
                                    'filter_names': [str(sampler.filter.minify),str(sampler.filter.magnify),str(sampler.filter.mip)]})
        if event!=6083:continue
        row['pixels']=[]
        import struct
        mesh=controller.GetPostVSData(0,0,rd.MeshDataStage.VSOut)
        row['mesh']=plain(mesh)
        meshdata=bytes(controller.GetBufferData(mesh.vertexResourceId,mesh.vertexByteOffset,mesh.vertexByteStride*2145))
        row['projected_candidates']=[]
        for vertex in (536,1072,1608):
            px,py,pz,pw=struct.unpack_from('<4f',meshdata,vertex*mesh.vertexByteStride)
            if pw>0:
                row['projected_candidates'].append((int((px/pw*.5+.5)*1280),int((.5-py/pw*.5)*720)))
        for x,y in row['projected_candidates']:
            if not (0<=x<1280 and 0<=y<720):continue
            entry={'x':x,'y':y};row['pixels'].append(entry)
            trace=controller.DebugPixel(x,y,rd.DebugPixelInputs())
            if trace is None:
                entry['missing']='No trace';continue
            try:
                entry['trace_metadata']=plain(trace)
                entry['inputs']=[variable(v) for v in trace.inputs]
                if not trace.inputs:
                    entry['missing']='Empty debug trace; no per-pixel value validation'
                    continue
                states=[]
                for batch in range(20):
                    steps=list(controller.ContinueDebug(trace.debugger))
                    if not steps:break
                    for step in steps:
                        states.append({'step':step.stepIndex,'next_instruction':step.nextInstruction,
                                       'changes':[{'before':variable(c.before),'after':variable(c.after)} for c in step.changes]})
                entry['states']=states
            finally:controller.FreeTrace(trace)
    report['pass']=True
except Exception as error:
    report['error']=repr(error);report['traceback']=traceback.format_exc()
finally:
    if controller is not None:controller.Shutdown()
    if capture is not None:capture.Shutdown()
    (OUT/'manifest.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
os._exit(0 if report['pass'] else 1)
