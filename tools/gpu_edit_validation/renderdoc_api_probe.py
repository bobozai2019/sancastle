"""Read local RenderDoc API documentation in a verified owned helper process."""
import json
import os
from pathlib import Path
import time

root = Path("D:/godot/project/sandcastle/tools/gpu_edit_validation")
owner = root / "renderdoc_api_probe_owner.json"
out = root / "renderdoc_api_probe.json"
deadline = time.monotonic() + 10.0
expected = None
while time.monotonic() < deadline:
    if owner.exists():
        expected = json.loads(owner.read_text(encoding="utf-8-sig")).get("pid")
        break
    time.sleep(0.05)

if expected == os.getpid():
    result = {"pid": os.getpid(), "scope": "documentation only; no target launch, injection or replay"}
    try:
        import renderdoc as rd
        result["version"] = rd.GetVersionString()
        result["apis"] = {}
        for name in ("ExecuteAndInject", "CreateTargetControl", "EnumerateRemoteTargets", "GetDefaultCaptureOptions"):
            value = getattr(rd, name, None)
            result["apis"][name] = getattr(value, "__doc__", None)
        result["target_types"] = [name for name in dir(rd) if "TargetControl" in name]
        result["target_methods"] = {}
        for name in ("TriggerCapture", "QueueCapture", "ReceiveMessage", "GetPID", "Connected", "Shutdown"):
            result["target_methods"][name] = getattr(getattr(rd.TargetControl, name, None), "__doc__", None)
        result["capture_options"] = getattr(rd.CaptureOptions, "__doc__", None)
        result["pass"] = True
    except Exception as error:
        result["pass"] = False
        result["error"] = repr(error)
    out.write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding="utf-8")
    os._exit(0 if result["pass"] else 1)
else:
    # Never terminate a pre-existing instance that received a forwarded script.
    out.write_text(json.dumps({"pass": False, "error": "process ownership mismatch", "actual": os.getpid(), "expected": expected}), encoding="utf-8")
