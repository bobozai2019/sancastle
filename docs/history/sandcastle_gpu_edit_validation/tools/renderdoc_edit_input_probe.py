"""Read one owned sand prepare's actual bound command and post-prepare source."""
import hashlib
import json
import os
from pathlib import Path
import time

context_path=Path("D:/godot/project/sandcastle/task/sandcastle_gpu_edit_validation/tools/renderdoc_edit_input_context.json")
deadline=time.monotonic()+10
context=None
while time.monotonic()<deadline:
    if context_path.exists(): context=json.loads(context_path.read_text(encoding="utf-8-sig"));break
    time.sleep(0.05)
if context is None or context["host_pid"]!=os.getpid(): raise RuntimeError("edit input helper ownership mismatch")
out=Path(context["output"])
capture=None
controller=None
try:
    import renderdoc as rd
    capture=rd.OpenCaptureFile();capture.OpenFile(context["capture"],"",None)
    status,controller=capture.OpenCapture(rd.ReplayOptions(),None)
    if controller is None: raise RuntimeError(str(status))
    controller.SetFrameEvent(context["event"],True)
    pipeline=controller.GetPipelineState()
    reflection=pipeline.GetShaderReflection(rd.ShaderStage.Compute)
    if reflection is None: raise RuntimeError("missing shader reflection")
    assert [r.name for r in reflection.readOnlyResources]==["ByteAddressBuffer0"]
    assert "sand_in" in [r.name for r in reflection.readWriteResources]
    rows=[]
    for used in pipeline.GetReadOnlyResources(rd.ShaderStage.Compute):
        descriptor=used.descriptor
        data=bytes(controller.GetBufferData(descriptor.resource,descriptor.byteOffset,descriptor.byteSize))
        assert len(data)==128
        filename="command_pid_%d.bin"%os.getpid();(out/filename).write_bytes(data)
        rows.append({"name":reflection.readOnlyResources[used.access.index].name,"resource":str(descriptor.resource),"byte_offset":descriptor.byteOffset,"byte_size":descriptor.byteSize,"path":filename,"sha256":hashlib.sha256(data).hexdigest()})
    for used in pipeline.GetReadWriteResources(rd.ShaderStage.Compute):
        descriptor=used.descriptor
        name=reflection.readWriteResources[used.access.index].name
        if name!="sand_in": continue
        data=bytes(controller.GetTextureData(descriptor.resource,rd.Subresource()))
        assert len(data)==256*256*4
        filename="prepare_sand_pid_%d.bin"%os.getpid();(out/filename).write_bytes(data)
        rows.append({"name":name,"resource":str(descriptor.resource),"path":filename,"sha256":hashlib.sha256(data).hexdigest(),"size":len(data),"format":descriptor.format.Name()})
        sand_resource=descriptor.resource
    assert len(rows)==2
    if context.get("initial_sand",False):
        controller.SetFrameEvent(0,True)
        data=bytes(controller.GetTextureData(sand_resource,rd.Subresource()))
        assert len(data)==256*256*4
        filename="initial_sand_pid_%d.bin"%os.getpid();(out/filename).write_bytes(data)
        rows.append({"name":"initial_sand","resource":str(sand_resource),"path":filename,"sha256":hashlib.sha256(data).hexdigest(),"size":len(data),"selection":"SetFrameEvent(0, True), same source resource before frame dispatches"})
    result={"pass":True,"pid":os.getpid(),"capture":context["capture"],"capture_sha256":hashlib.sha256(Path(context["capture"]).read_bytes()).hexdigest(),"event":context["event"],"rows":rows,"scope":"Command buffer bound at sand prepare; source sand is post-event replay-derived and unchanged by this readonly prepare pass, not an original live input snapshot."}
except Exception as error: result={"pass":False,"pid":os.getpid(),"error":repr(error)}
finally:
    if controller is not None: controller.Shutdown()
    if capture is not None: capture.Shutdown()
(out/("edit_input_pid_%d.json"%os.getpid())).write_text(json.dumps(result,indent=2),encoding="utf-8")
os._exit(0 if result["pass"] else 1)
