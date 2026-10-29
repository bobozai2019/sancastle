"""Read-only captured sand wet-color inputs and water amount update."""
import hashlib,json,os,traceback
from pathlib import Path
ROOT=Path('D:/godot/project/sandcastle')
SOURCE=ROOT/'rdc/test1.rdc'
OUT=ROOT/'docs/competitor/evidence/wet_sand_20261024/rdc'
SCRIPT=ROOT/'docs/competitor/tools/export_wet_sand_capture.py'
def ident(p):return dict(path=p.as_posix(),bytes=p.stat().st_size,sha256=hashlib.sha256(p.read_bytes()).hexdigest())
def fields(obj):
 result={}
 for k in dir(obj):
  if k.startswith('_') or k in ['this','thisown']:continue
  try:
   v=getattr(obj,k)
   if not callable(v):result[k]=v if isinstance(v,(int,float,str,bool)) else str(v)
  except:pass
 return result
OUT.mkdir(parents=True,exist_ok=False)
report=dict(source=ident(SOURCE),script=ident(SCRIPT),exports=[],events=[],pass_=False,scope='Fresh replay per selected event. Full selected buffers, selected cbuffer ranges, VS/PS/CS compiled instructions; no original source or elapsed-time claim.')
def save(name,data,selector):
 p=OUT/name;p.write_bytes(bytes(data));row=dict(**ident(p),selector=selector);report['exports'].append(row);return row
cap=ctl=None
try:
 import renderdoc as rd
 assert report['source']['sha256']=='761aa980c2426f75a1fa7364bf6d2655ff4dd20ea76566e630ee5b53ea0ec5b2'
 report['tool']=dict(version=rd.GetVersionString(),command='D:/other_software/RenderDoc/qrenderdoc.exe --python '+SCRIPT.as_posix())
 for event in [1537,5006,6083]:
  cap=rd.OpenCaptureFile();report['open']=str(cap.OpenFile(str(SOURCE),'',None));status,ctl=cap.OpenCapture(rd.ReplayOptions(),None)
  if ctl is None:raise RuntimeError(str(status))
  ctl.SetFrameEvent(event,True);pipe=ctl.GetPipelineState();textures={t.resourceId:t for t in ctl.GetTextures()};buffers={b.resourceId:b for b in ctl.GetBuffers()}
  row=dict(event=event,selector='Fresh OpenCapture; SetFrameEvent(event,True), post-event',stages={})
  report['events'].append(row);done=set()
  stages=[('cs',rd.ShaderStage.Compute)] if event==1537 else [('vs',rd.ShaderStage.Vertex),('ps',rd.ShaderStage.Pixel)]
  for label,stage in stages:
   refl=pipe.GetShaderReflection(stage);prefix=f'e{event}_{label}'
   sr=dict(shader=str(pipe.GetShader(stage)),constants=[],bindings=[]);row['stages'][label]=sr
   sr['bytecode']=save(prefix+'.dxbc',refl.rawBytes,f'E{event} {label} rawBytes')
   pipeline=pipe.GetComputePipelineObject() if event==1537 else pipe.GetGraphicsPipelineObject()
   sr['assembly']=save(prefix+'.asm',ctl.DisassembleShader(pipeline,refl,'').encode(),f'E{event} {label} derived disassembly')
   for i,block in enumerate(refl.constantBlocks):
    d=pipe.GetConstantBlock(stage,i,0).descriptor;size=min(d.byteSize,block.byteSize)
    sr['constants'].append(dict(index=i,resource=str(d.resource),offset=d.byteOffset,bytes=size,raw=save(f'{prefix}_cb{i}.bin',ctl.GetBufferData(d.resource,d.byteOffset,size),f'E{event} {label} cb{i}, {d.resource} offset={d.byteOffset} length={size}')))
   for access,used_resources,definitions in [('ro',pipe.GetReadOnlyResources(stage),refl.readOnlyResources),('rw',pipe.GetReadWriteResources(stage),refl.readWriteResources)]:
    for used in used_resources:
     d=used.descriptor;binding=dict(access=access,index=used.access.index,name=definitions[used.access.index].name,resource=str(d.resource),descriptor=fields(d));sr['bindings'].append(binding)
     if d.resource in buffers:
      b=buffers[d.resource];binding['buffer_bytes']=b.length
      if d.resource not in done and b.length<=16*1024*1024:
       binding['raw']=save(f'e{event}_buffer_{str(d.resource).split("::")[-1]}.bin',ctl.GetBufferData(d.resource,0,b.length),f'E{event} {d.resource}, complete buffer offset=0 bytes={b.length}')
       done.add(d.resource)
     elif d.resource in textures:
      t=textures[d.resource];binding['texture']=dict(width=t.width,height=t.height,depth=t.depth,mips=t.mips,format=t.format.Name())
  ctl.Shutdown();ctl=None;cap.Shutdown();cap=None
  (OUT/'progress.json').write_text(json.dumps(report,indent=2),encoding='utf8')
 report['source_after']=ident(SOURCE);report['pass_']=report['source']==report['source_after']
except Exception:report['error']=traceback.format_exc()
finally:
 if ctl is not None:ctl.Shutdown()
 if cap is not None:cap.Shutdown()
 (OUT/'manifest.json').write_text(json.dumps(report,indent=2),encoding='utf8')
os._exit(0 if report['pass_'] else 1)
