import hashlib,json,os,traceback,struct
from pathlib import Path
ROOT=Path("D:/godot/project/sandcastle")
OUT=ROOT/"docs/competitor/evidence/vegetation_depth_20261023"
OUT.mkdir(parents=True,exist_ok=False)
SOURCE=ROOT/"rdc/test1.rdc"
def ident(p):return dict(path=str(p),bytes=p.stat().st_size,sha256=hashlib.sha256(p.read_bytes()).hexdigest())
def flat(actions):
 for a in actions:
  yield a
  yield from flat(a.children)
def fields(obj):
 d={}
 for k in dir(obj):
  if k.startswith("_") or k in ("this","thisown"):continue
  try:
   v=getattr(obj,k)
   if not callable(v):d[k]=v if isinstance(v,(int,float,str,bool)) else str(v)
  except:pass
 return d
def save(name,raw,selector):
 p=OUT/name;p.write_bytes(bytes(raw));row=dict(**ident(p),selector=selector);report["exports"].append(row);return row
report=dict(source=ident(SOURCE),tool=ident(ROOT/"docs/competitor/tools/export_vegetation_depth.py"),command="D:/other_software/RenderDoc/qrenderdoc.exe --python D:/godot/project/sandcastle/docs/competitor/tools/export_vegetation_depth.py",events=[],exports=[],success=False)
cap=ctl=None
try:
 import renderdoc as rd
 report["version"]=rd.GetVersionString()
 assert report["source"]["sha256"]=="761aa980c2426f75a1fa7364bf6d2655ff4dd20ea76566e630ee5b53ea0ec5b2"
 cap=rd.OpenCaptureFile();report["open"]=str(cap.OpenFile(str(SOURCE),"",None));status,ctl=cap.OpenCapture(rd.ReplayOptions(),None);report["replay"]=str(status)
 seen=set()
 for a in flat(ctl.GetRootActions()):
  if not (a.flags&rd.ActionFlags.Drawcall) or not 5000<=a.eventId<=6090:continue
  ctl.SetFrameEvent(a.eventId,True);pipe=ctl.GetPipelineState();ps=pipe.GetShaderReflection(rd.ShaderStage.Pixel)
  if ps is None:continue
  digest=hashlib.sha256(bytes(ps.rawBytes)).hexdigest()
  row=dict(event=a.eventId,action=fields(a),ps=str(pipe.GetShader(rd.ShaderStage.Pixel)),ps_sha256=digest,vs=str(pipe.GetShader(rd.ShaderStage.Vertex)))
  report["events"].append(row)
  if digest in seen:continue
  seen.add(digest);prefix="e"+str(a.eventId)
  row["raw"]=save(prefix+".dxbc",ps.rawBytes,prefix+" PS rawBytes")
  row["asm"]=save(prefix+".asm",ctl.DisassembleShader(pipe.GetGraphicsPipelineObject(),ps,"").encode(),prefix+" PS")
  row["inputs"]=[dict(index=u.access.index,descriptor=fields(u.descriptor)) for u in pipe.GetReadOnlyResources(rd.ShaderStage.Pixel)]
  row["depth_target"]=fields(pipe.GetDepthTarget());row["depth_state"]=fields(ctl.GetD3D12PipelineState().depthStencil)
  row["constants"]=[]
  for i,b in enumerate(ps.constantBlocks):
   d=pipe.GetConstantBlock(rd.ShaderStage.Pixel,i,0).descriptor
   raw=ctl.GetBufferData(d.resource,d.byteOffset,min(d.byteSize,b.byteSize))
   row["constants"].append(dict(index=i,descriptor=fields(d),data=save(prefix+"_cb"+str(i)+".bin",raw,prefix+" PS cb"+str(i))))
 report["source_after"]=ident(SOURCE);report["success"]=report["source_after"]==report["source"]
except:report["error"]=traceback.format_exc()
finally:
 if ctl:ctl.Shutdown()
 if cap:cap.Shutdown()
 (OUT/"manifest.json").write_text(json.dumps(report,indent=2),encoding="utf-8")
os._exit(0 if report["success"] else 1)
