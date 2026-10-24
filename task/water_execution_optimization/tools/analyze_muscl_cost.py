"""Summarize ABBA captures without adding nested CPU/GPU intervals."""
import json
import math
import statistics
import sys
from collections import defaultdict
from pathlib import Path


def stats(values):
    ordered = sorted(values)
    if not ordered:
        return {}
    return {"n": len(ordered), "mean": statistics.mean(ordered),
            "p50": ordered[math.ceil(len(ordered) * .5) - 1],
            "p95": ordered[math.ceil(len(ordered) * .95) - 1],
            "p99": ordered[math.ceil(len(ordered) * .99) - 1], "max": ordered[-1]}


directory = Path(sys.argv[1])
data = json.loads((directory / "capture.json").read_text(encoding="utf-8"))
cpu = defaultdict(list)
starts = {}
for event in data["timeline"]["events"]:
    if event["event"] == "submit_begin":
        starts[event["key"]] = event["at_us"]
    elif event["event"] == "submit_end" and event["key"] in starts:
        begin = starts.pop(event["key"])
        for interval in data["metadata"]["intervals"]:
            if interval["start_us"] <= begin <= event["at_us"] <= interval["end_us"]:
                cpu[interval["phase"]].append((event["at_us"] - begin) / 1000)
gpu = defaultdict(list)
for frame in data["gpu"]:
    begin = None
    for mark in frame["marks"]:
        if mark["name"] == "sandcastle_async_water_tick_start":
            begin = mark["gpu_ns"]
        elif mark["name"] == "sandcastle_async_water_tick_end" and begin is not None:
            gpu[frame["phase"]].append((mark["gpu_ns"] - begin) / 1e6)
phases = {}
for interval in data["metadata"]["intervals"]:
    name = interval["phase"]
    rows = [r for r in data["frames"] if r["phase"] == name]
    phases[name] = {"frame_ms": stats([r["frame_ms"] for r in rows]),
                    "cpu_submit_ms": stats(cpu[name]), "gpu_tick_ms": stats(gpu[name]),
                    "viewport_gpu_ms": stats([r["render_gpu_ms"] for r in rows]),
                    "simulation_ratio": (rows[-1]["sim_s"] - rows[0]["sim_s"]) / ((rows[-1]["us"] - rows[0]["us"]) / 1e6)}
    phases[name]["fps"] = 1000 / phases[name]["frame_ms"]["mean"]
pooled = {}
for variant in ("before", "after"):
    pooled[variant] = {"cpu_submit_ms": stats([v for k, values in cpu.items() if k.startswith(variant) for v in values]),
                       "gpu_tick_ms": stats([v for k, values in gpu.items() if k.startswith(variant) for v in values]),
                       "frame_ms": stats([r["frame_ms"] for r in data["frames"] if r["phase"].startswith(variant)])}
result = {"phases": phases, "pooled": pooled, "timeline_dropped": data["timeline"]["dropped"],
          "last_error": data["metadata"]["last_error"]}
(directory / "summary.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
print(json.dumps(result, indent=2))
