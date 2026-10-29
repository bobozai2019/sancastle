"""Capture only the owned original-prefix replay target at two explicit gates."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

context_path = Path("D:/godot/project/sandcastle/tools/gpu_edit_validation/renderdoc_replay_capture_context.json")
deadline = time.monotonic() + 10
context = None
while time.monotonic() < deadline:
    if context_path.exists():
        context = json.loads(context_path.read_text(encoding="utf-8-sig"))
        break
    time.sleep(0.05)
if context is None or context["host_pid"] != os.getpid():
    raise RuntimeError("owned capture host mismatch")
out = Path(context["output"])
result = {"host_pid": os.getpid(), "pass": False, "scope": "owned Godot original-prefix replay; not competitor"}
target = None
try:
    import renderdoc as rd
    options = rd.CaptureOptions()
    options.allowVSync = False
    options.allowFullscreen = False
    args = ["--path", context["project"], "--rendering-driver", "d3d12", "--resolution", "1920x1080",
            "--log-file", str(out / "godot.log"), "--script", "res://tests/edit_validation/beach_replay_original_probe.gd",
            "--", "--output="+str(out), "--beach-replay-capture", "--beach-replay-capture-tick="+str(context.get("tick",5))]
    result["arguments"] = args
    launched = rd.ExecuteAndInject(context["godot"], context["project"], subprocess.list2cmdline(args), [],
                                   str(out / "original_replay"), options, False)
    result["launch_status"] = str(launched.result)
    if launched.ident == 0:
        raise RuntimeError("injection failed")
    target = rd.CreateTargetControl("", launched.ident, "sandcastle-owned-original-replay", False)
    if target is None:
        raise RuntimeError("target connection failed")
    result["target_pid"] = target.GetPID()
    (out / "target_owner.json").write_text(json.dumps({"pid": target.GetPID(), "arguments": args,
        "executable": context["godot"], "output": str(out)}, indent=2), encoding="utf-8")
    result["gates"] = []
    for label in ("active", "worker"):
        ready = out / f"capture_ready_{label}.json"
        deadline = time.monotonic() + 90
        while not ready.exists() and target.Connected() and time.monotonic() < deadline:
            target.ReceiveMessage(None)
        if not ready.exists():
            raise RuntimeError(f"missing {label} gate")
        marker = json.loads(ready.read_text(encoding="utf-8"))
        if marker["pid"] != target.GetPID() or marker["tick"] != context.get("tick",5) or marker["branch"] != label:
            raise RuntimeError("gate identity mismatch")
        result["gates"].append(marker)
        target.TriggerCapture(context.get("frames",8))
        (out / f"capture_go_{label}.json").write_text(json.dumps({"target_pid": target.GetPID(), "frames": context.get("frames",8)}), encoding="utf-8")
    deadline = time.monotonic() + 120
    while target.Connected() and time.monotonic() < deadline:
        target.ReceiveMessage(None)
    result["captures"] = [{"path": path.name, "size": path.stat().st_size,
                           "sha256": hashlib.sha256(path.read_bytes()).hexdigest()} for path in sorted(out.glob("*.rdc"))]
    result["target_disconnected"] = not target.Connected()
    report = out / "beach_replay_original_probe.json"
    result["strict_replay_pass"] = json.loads(report.read_text(encoding="utf-8"))["pass"] if report.exists() else None
    result["expected_captures"] = 2*context.get("frames",8)
    result["pass"] = len(result["captures"]) == result["expected_captures"] and result["target_disconnected"] and report.exists()
except Exception as error:
    result["error"] = repr(error)
finally:
    if target is not None:
        target.Shutdown()
    (out / "capture_host.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
os._exit(0 if result["pass"] else 1)
