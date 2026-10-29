"""Replay only the captures listed in this task's owned context."""
import json
import os
from pathlib import Path
import time

context_path=Path("D:/godot/project/sandcastle/tools/gpu_edit_validation/renderdoc_replay_context.json")
deadline=time.monotonic()+10
context=None
while time.monotonic()<deadline:
    if context_path.exists():
        context=json.loads(context_path.read_text(encoding="utf-8-sig"));break
    time.sleep(0.05)
if context is None or context["host_pid"]!=os.getpid(): raise RuntimeError("replay helper PID mismatch")
out=Path(context["output"])
rows=[]
try:
    import renderdoc as rd
    for path in sorted(out.glob("*.rdc")):
        capture=rd.OpenCaptureFile()
        opened=capture.OpenFile(str(path),"",None)
        row={"path":str(path),"open_result":str(opened),"capture_api_fields":dir(capture),"pass":False}
        controller=None
        try:
            status,controller=capture.OpenCapture(rd.ReplayOptions(),None)
            row["replay_result"]=str(status)
            if controller is not None:
                row["driver"]=str(controller.GetAPIProperties().pipelineType)
                def flatten(actions):
                    for action in actions:
                        yield action
                        yield from flatten(action.children)
                actions=list(flatten(controller.GetRootActions()))
                dispatches=[]
                for action in actions:
                    if action.flags & rd.ActionFlags.Dispatch:
                        controller.SetFrameEvent(action.eventId,True)
                        pipeline=controller.GetPipelineState()
                        shader=pipeline.GetShader(rd.ShaderStage.Compute)
                        dispatches.append({"event":action.eventId,"shader":str(shader),"dimensions":list(action.dispatchDimension)})
                row["actions"]=len(actions);row["dispatches"]=dispatches;row["pass"]=True
        finally:
            if controller is not None: controller.Shutdown()
            capture.Shutdown()
        rows.append(row)
    result={"pass":bool(rows) and all(row["pass"] for row in rows),"rows":rows,"scope":"replay compatibility and dispatch inventory only; tick/resource mapping not yet verified"}
except Exception as error:
    result={"pass":False,"rows":rows,"error":repr(error)}
report_name="replay_probe_pid_%d.json" % os.getpid()
(out/report_name).write_text(json.dumps(result,indent=2),encoding="utf-8")
(out/"replay_probe_latest.json").write_text(json.dumps({"report":report_name}),encoding="utf-8")
os._exit(0 if result["pass"] else 1)
