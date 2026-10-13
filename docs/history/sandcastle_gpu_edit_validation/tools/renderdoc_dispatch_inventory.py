"""Inventory real dispatch signatures in owned RDCs; no pass coverage inference from gates."""
import hashlib
import json
import os
from pathlib import Path
import re
import time

context_path=Path("D:/godot/project/sandcastle/task/sandcastle_gpu_edit_validation/tools/renderdoc_dispatch_inventory_context.json")
deadline=time.monotonic()+10
context=None
while time.monotonic()<deadline:
    if context_path.exists():
        context=json.loads(context_path.read_text(encoding="utf-8-sig"));break
    time.sleep(0.05)
if context is None or context["host_pid"]!=os.getpid(): raise RuntimeError("owned inventory helper mismatch")
out=Path(context["output"])
rows=[]
capture=None
controller=None
try:
    import renderdoc as rd
    def flatten(actions):
        for action in actions:
            yield action
            yield from flatten(action.children)
    for path in sorted(out.glob("*.rdc"),key=lambda p:int(re.search(r"frame(\d+)",p.name).group(1))):
        capture=rd.OpenCaptureFile()
        opened=capture.OpenFile(str(path),"",None)
        status,controller=capture.OpenCapture(rd.ReplayOptions(),None)
        if controller is None: raise RuntimeError(str(status))
        dispatches=[]
        for action in flatten(controller.GetRootActions()):
            if not action.flags & rd.ActionFlags.Dispatch: continue
            controller.SetFrameEvent(action.eventId,True)
            pipeline=controller.GetPipelineState()
            reflection=pipeline.GetShaderReflection(rd.ShaderStage.Compute)
            if reflection is None: raise RuntimeError("missing compute reflection")
            dispatches.append({"event":action.eventId,"dimensions":list(action.dispatchDimension),
                "shader":str(pipeline.GetShader(rd.ShaderStage.Compute)),"native_sha256":hashlib.sha256(bytes(reflection.rawBytes)).hexdigest(),
                "native_size":len(reflection.rawBytes),"encoding":str(reflection.encoding),
                "readonly":[r.name for r in reflection.readOnlyResources],"readwrite":[r.name for r in reflection.readWriteResources]})
        entry={"capture":path.name,"sha256":hashlib.sha256(path.read_bytes()).hexdigest(),"dispatches":dispatches,"replay_status":str(status)}
        rows.append(entry)
        (out/("inventory_frame_"+re.search(r"frame(\d+)",path.name).group(1)+".json")).write_text(json.dumps(entry,indent=2),encoding="utf-8")
        controller.Shutdown();controller=None;capture.Shutdown();capture=None
    result={"pass":bool(rows),"rows":rows,"pid":os.getpid(),"tool_sha256":hashlib.sha256(context_path.with_name("renderdoc_dispatch_inventory.py").read_bytes()).hexdigest(),"scope":"Owned frame replay and real dispatch/native reflection inventory; no numerical or complete-input proof."}
except Exception as error:
    result={"pass":False,"rows":rows,"pid":os.getpid(),"error":repr(error)}
finally:
    if controller is not None: controller.Shutdown()
    if capture is not None: capture.Shutdown()
(out/("dispatch_inventory_pid_%d.json"%os.getpid())).write_text(json.dumps(result,indent=2),encoding="utf-8")
os._exit(0 if result["pass"] else 1)
