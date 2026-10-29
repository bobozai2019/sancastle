"""Read-only test1 water dispatch/bytecode/constant evidence. qrenderdoc --python."""
import hashlib
import json
import os
import traceback
from pathlib import Path

ROOT = Path("D:/godot/project/sandcastle")
SOURCE = ROOT / "rdc/test1.rdc"
OUT = ROOT / "docs/competitor/evidence/water_schedule_20261024_v2"
SCRIPT = ROOT / "docs/competitor/tools/export_water_schedule.py"
EXPECTED = "761aa980c2426f75a1fa7364bf6d2655ff4dd20ea76566e630ee5b53ea0ec5b2"
NAMES = {1484: "UpdateFloor", 1490: "VelocityIntegration", 1495: "HeightIntegration",
         1500: "Advection", 1505: "VelocityIntegration", 1510: "HeightIntegration",
         1515: "Advection", 1520: "VelocityIntegration", 1525: "HeightIntegration",
         1530: "Advection", 1537: "UpdateAmount", 1543: "UpdateTangent"}
KNOWN = {"VelocityIntegration": "9e5c7da8738200d374076a6cc3b48be52fdbad70e8c8dc2bd27eb75431d30523",
         "HeightIntegration": "549114c23f1921610bacaf1d9ae375814fda1fb1de492cc2a4acfc53a502c64f",
         "Advection": "b2794ecb18de815ff607fffd734ff4cde859bab1efd7fa3dfe9a24eb5a9f7a3c",
         "UpdateAmount": "a61d34e411e8eee5c795bf233908a9b2a5b85ee272f5d0fbcb1481da27a62b80"}


def identity(path):
    return {"path": path.as_posix(), "bytes": path.stat().st_size,
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}


def flatten(actions):
    for action in actions:
        yield action
        yield from flatten(action.children)


def save(name, data, selector):
    path = OUT / name
    path.write_bytes(bytes(data))
    return dict(identity(path), selector=selector)


OUT.mkdir(parents=True, exist_ok=False)
report = {"scope": "Only test1 E1484..E1543 water compute chain, raw bytecode and bound constants. No GPU timing or original wall-clock/substep policy claim.",
          "source": identity(SOURCE), "script": identity(SCRIPT), "events": []}
cap = None
controller = None
try:
    import renderdoc as rd
    assert report["source"]["sha256"] == EXPECTED
    report["tool"] = {"version": rd.GetVersionString(), "command": "D:/other_software/RenderDoc/qrenderdoc.exe --python " + SCRIPT.as_posix()}
    cap = rd.OpenCaptureFile()
    report["open_file"] = str(cap.OpenFile(str(SOURCE), "", None))
    status, controller = cap.OpenCapture(rd.ReplayOptions(), None)
    report["open_capture"] = str(status)
    if controller is None:
        raise RuntimeError(str(status))
    actions = [a for a in flatten(controller.GetRootActions()) if 1484 <= a.eventId <= 1543 and a.flags & rd.ActionFlags.Dispatch]
    for action in actions:
        event = action.eventId
        controller.SetFrameEvent(event, True)
        pipe = controller.GetPipelineState()
        reflection = pipe.GetShaderReflection(rd.ShaderStage.Compute)
        row = {"event": event, "historical_name": NAMES.get(event, "unknown"),
               "groups": list(action.dispatchDimension), "constants": [],
               "shader_resource": str(pipe.GetShader(rd.ShaderStage.Compute)),
               "shader": save(f"e{event}.dxbc", reflection.rawBytes, f"E{event} CS rawBytes"),
               "disassembly": save(f"e{event}.asm", controller.DisassembleShader(pipe.GetComputePipelineObject(), reflection, "").encode("utf-8"), f"E{event} CS disassembly"),
               "readonly_names": [r.name for r in reflection.readOnlyResources],
               "readwrite_names": [r.name for r in reflection.readWriteResources]}
        row["matches_known_shader"] = row["shader"]["sha256"] == KNOWN[row["historical_name"]] if row["historical_name"] in KNOWN else None
        for index, block in enumerate(reflection.constantBlocks):
            desc = pipe.GetConstantBlock(rd.ShaderStage.Compute, index, 0).descriptor
            length = min(desc.byteSize, block.byteSize)
            row["constants"].append(save(f"e{event}_cb{index}.bin", controller.GetBufferData(desc.resource, desc.byteOffset, length),
                                         f"E{event} CS cb{index} {desc.resource} offset={desc.byteOffset} bytes={length}"))
        report["events"].append(row)
    report["source_after"] = identity(SOURCE)
    report["pass"] = (report["source"] == report["source_after"] and [a.eventId for a in actions] == list(NAMES)
                      and all(e["matches_known_shader"] is not False for e in report["events"]))
except Exception:
    report["error"] = traceback.format_exc()
finally:
    if controller is not None:
        controller.Shutdown()
    if cap is not None:
        cap.Shutdown()
    (OUT / "manifest.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
os._exit(0 if report.get("pass") else 1)
