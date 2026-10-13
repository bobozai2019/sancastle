"""Launch and control only this probe's Godot target from RenderDoc Python."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

tools = Path("D:/godot/project/sandcastle/task/sandcastle_gpu_edit_validation/tools")
context_path = tools / "renderdoc_capture_context.json"
deadline = time.monotonic() + 10
context = None
while time.monotonic() < deadline:
    if context_path.exists():
        context = json.loads(context_path.read_text(encoding="utf-8-sig"))
        break
    time.sleep(0.05)
if context is None or context["host_pid"] != os.getpid():
    raise RuntimeError("owned RenderDoc host PID mismatch")

out = Path(context["output"])
result = {"host_pid": os.getpid(), "scope": "own Godot D3D12 tick17 continuation capture; not competitor replay", "pass": False}
target = None
try:
    import renderdoc as rd
    result["renderdoc"] = rd.GetVersionString()
    opts = rd.CaptureOptions()
    opts.allowVSync = False
    opts.allowFullscreen = False
    args = ["--path", context["project"], "--rendering-driver", "d3d12", "--resolution", "1920x1080", "--log-file", str(out / "godot.log"), "--script", "res://tests/edit_validation/beach_capture_entry_probe.gd", "--", "--output=" + str(out), "--checkpoint-mode=write", "--beach-no-parameter-trace", "--beach-late-shader-identity", "--beach-push-trace"]
    mode=context.get("mode","write")
    if mode not in ("write","read"): raise RuntimeError("invalid checkpoint mode")
    args[args.index("--checkpoint-mode=write")]="--checkpoint-mode="+mode
    if mode=="read":
        source=Path(context["source"])
        if not (source/"full_beach_edit.scp").is_file(): raise RuntimeError("reader checkpoint absent")
        args.append("--checkpoint-source="+str(source))
    result["checkpoint_mode"]=mode
    result["arguments"]=args
    launched = rd.ExecuteAndInject(context["godot"], context["project"], subprocess.list2cmdline(args), [], str(out / "godot_capture"), opts, False)
    result["launch_result_fields"] = dir(launched)
    result["launch_status"] = str(getattr(launched, "result", getattr(launched, "status", None)))
    result["ident"] = launched.ident
    if launched.ident == 0:
        raise RuntimeError("injection failed: " + result["launch_status"])
    target = rd.CreateTargetControl("", launched.ident, "sandcastle-owned-probe", False)
    if target is None:
        raise RuntimeError("target connection failed")
    result["target_pid"] = target.GetPID()
    ready = out / "capture_ready.json"
    deadline = time.monotonic() + 90
    while not ready.exists() and target.Connected() and time.monotonic() < deadline:
        target.ReceiveMessage(None)
    if not ready.exists():
        raise RuntimeError("tick17 coordination marker missing")
    marker = json.loads(ready.read_text(encoding="utf-8"))
    if marker["pid"] != target.GetPID() or marker["tick"] != 17:
        raise RuntimeError("target PID/tick mismatch")
    result["ready"] = marker
    target.TriggerCapture(8)
    (out / "capture_go.json").write_text(json.dumps({"target_pid": target.GetPID(), "requested_frames": 8}), encoding="utf-8")
    deadline = time.monotonic() + 120
    while target.Connected() and time.monotonic() < deadline:
        target.ReceiveMessage(None)
    captures = []
    for path in sorted(out.glob("*.rdc")):
        captures.append({"path": str(path), "size": path.stat().st_size, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
    result["captures"] = captures
    result["target_disconnected"] = not target.Connected()
    result["pass"] = bool(captures) and result["target_disconnected"] and (out / "beach_edit_process_probe.json").exists()
except Exception as error:
    result["error"] = repr(error)
finally:
    if target is not None:
        target.Shutdown()
    (out / "capture_host.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
os._exit(0 if result["pass"] else 1)
