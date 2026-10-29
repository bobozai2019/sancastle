"""Read-only, narrow test1 water shader recheck; run with qrenderdoc --python."""
import hashlib
import json
import os
import struct
import traceback
from pathlib import Path

ROOT = Path("D:/godot/project/sandcastle")
OUT = ROOT / "test_output/wave_solution_20261020/competitor_recheck"
SOURCE = ROOT / "sandcastlegame/test1.rdc"
SCRIPT = ROOT / "tools/wave_propagation/recheck_competitor.py"
EXPECTED = "761aa980c2426f75a1fa7364bf6d2655ff4dd20ea76566e630ee5b53ea0ec5b2"
KERNELS = {
    1490: ("VelocityIntegration", "9e5c7da8738200d374076a6cc3b48be52fdbad70e8c8dc2bd27eb75431d30523"),
    1495: ("HeightIntegration", "549114c23f1921610bacaf1d9ae375814fda1fb1de492cc2a4acfc53a502c64f"),
    1500: ("Advection", "b2794ecb18de815ff607fffd734ff4cde859bab1efd7fa3dfe9a24eb5a9f7a3c"),
    1537: ("UpdateAmount", "a61d34e411e8eee5c795bf233908a9b2a5b85ee272f5d0fbcb1481da27a62b80"),
}


def identity(path):
    return {"path": path.as_posix(), "bytes": path.stat().st_size,
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}


OUT.mkdir(parents=True, exist_ok=False)
report = {
    "scope": "Compiled shader bytes, disassembly and bound constants only. "
             "No water-state export, dynamic propagation measurement or original HLSL claim.",
    "source": identity(SOURCE), "script": identity(SCRIPT), "events": [],
}


def export(name, data, selector):
    path = OUT / name
    path.write_bytes(bytes(data))
    return dict(identity(path), selector=selector)


try:
    import renderdoc as rd
    assert report["source"]["sha256"] == EXPECTED
    report["tool"] = {
        "version": rd.GetVersionString(),
        "command": "D:/other_software/RenderDoc/qrenderdoc.exe --python " + SCRIPT.as_posix(),
    }
    for event, (name, expected) in KERNELS.items():
        cap = rd.OpenCaptureFile()
        controller = None
        try:
            opened = cap.OpenFile(str(SOURCE), "", None)
            status, controller = cap.OpenCapture(rd.ReplayOptions(), None)
            if controller is None:
                raise RuntimeError(str(status))
            controller.SetFrameEvent(event, True)
            pipe = controller.GetPipelineState()
            stage = rd.ShaderStage.Compute
            reflection = pipe.GetShaderReflection(stage)
            row = {
                "event": event, "historical_kernel_name": name,
                "selection": "Independent OpenCapture; SetFrameEvent(event, True)",
                "shader": export(f"e{event}.dxbc", reflection.rawBytes, f"E{event} CS rawBytes"),
                "constants": [],
            }
            report["events"].append(row)
            row["matches_historical_shader_sha256"] = row["shader"]["sha256"] == expected
            instructions = controller.DisassembleShader(pipe.GetComputePipelineObject(), reflection, "")
            row["disassembly"] = export(f"e{event}.asm", instructions.encode("utf-8"), f"E{event} CS disassembly")
            for index, block in enumerate(reflection.constantBlocks):
                descriptor = pipe.GetConstantBlock(stage, index, 0).descriptor
                size = min(descriptor.byteSize, block.byteSize)
                data = bytes(controller.GetBufferData(descriptor.resource, descriptor.byteOffset, size))
                row["constants"].append({
                    "index": index, "resource": str(descriptor.resource),
                    "offset": descriptor.byteOffset, "bytes": size,
                    "raw": export(f"e{event}_cb{index}.bin", data,
                                  f"E{event} CS cb{index} {descriptor.resource} offset{descriptor.byteOffset} bytes{size}"),
                    "float4": [list(struct.unpack_from("<4f", data, start))
                               for start in range(0, size - 15, 16)],
                })
            (OUT / "progress.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
        finally:
            if controller is not None:
                controller.Shutdown()
            cap.Shutdown()
    report["source_after"] = identity(SOURCE)
    report["pass"] = (report["source"] == report["source_after"]
                      and all(row["matches_historical_shader_sha256"] for row in report["events"]))
except Exception:
    report["error"] = traceback.format_exc()
finally:
    (OUT / "manifest.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
os._exit(0 if report.get("pass") else 1)
