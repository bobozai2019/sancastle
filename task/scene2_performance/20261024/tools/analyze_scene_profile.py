"""Analyze visible scene captures. Nested CPU/GPU spans are never added together."""
import collections
import json
import math
import statistics
import sys
from pathlib import Path


def stats(values):
    ordered = sorted(values)
    if not ordered:
        return {}
    return {"n": len(ordered), "mean": statistics.mean(ordered),
            "p50": ordered[math.ceil(len(ordered) * .5) - 1],
            "p95": ordered[math.ceil(len(ordered) * .95) - 1],
            "p99": ordered[math.ceil(len(ordered) * .99) - 1], "max": ordered[-1],
            "sum": sum(ordered)}


def analyze(directory):
    data = json.loads((directory / "capture.json").read_text(encoding="utf-8"))
    cpu = collections.defaultdict(lambda: collections.defaultdict(list))
    gpu = collections.defaultdict(lambda: collections.defaultdict(list))
    detail = collections.defaultdict(list)
    starts = {}
    pairs = {"submit_end": "submit_begin", "pump_end": "pump_begin",
             "receive_end": "receive_begin", "settle_end": "consume_begin",
             "height_apply_end": "height_apply_begin"}
    for event in data["timeline"]["events"]:
        name = event["event"]
        key = (event["thread"], event["key"])
        if name in pairs.values():
            starts[(name, *key)] = event["at_us"]
        elif name in pairs:
            begin = starts.pop((pairs[name], *key), None)
            if begin is None:
                continue
            for interval in data["metadata"]["intervals"]:
                if interval["start_us"] <= begin <= event["at_us"] <= interval["end_us"]:
                    cpu[interval["phase"]][name.removesuffix("_end")].append((event["at_us"] - begin) / 1000)
    for frame in data["gpu"]:
        starts = {}
        tick = None
        for mark in frame["marks"]:
            name, at = mark["name"], mark["gpu_ns"]
            if name == "sandcastle_async_water_tick_start":
                tick = {"coupled_ms": 0.0, "coupled_calls": 0, "visuals_ms": 0.0, "boundary_ms": 0.0}
            if name.endswith("_start"):
                starts[name[:-6]] = at
            elif name.endswith("_end") and name[:-4] in starts:
                base = name[:-4]
                ms = (at - starts.pop(base)) / 1e6
                gpu[frame["phase"]]["ue_batch" if base.startswith("ue_batch_") else base].append(ms)
                if tick is not None:
                    if base == "scene_profile_coupled":
                        tick["coupled_ms"] += ms
                        tick["coupled_calls"] += 1
                    elif base == "scene_profile_visuals":
                        tick["visuals_ms"] = ms
                    elif base == "sandcastle_boundary":
                        tick["boundary_ms"] = ms
                    elif base == "sandcastle_async_water_tick":
                        if tick["coupled_calls"]:
                            tick["total_ms"] = ms
                            tick["remaining_ms"] = ms - tick["coupled_ms"] - tick["visuals_ms"] - tick["boundary_ms"]
                            detail[frame["phase"]].append(tick)
                        tick = None
    phases = {}
    for interval in data["metadata"]["intervals"]:
        name = interval["phase"]
        rows = [r for r in data["frames"] if r["phase"] == name]
        duration = (interval["end_us"] - interval["start_us"]) / 1e6
        metrics = {key: stats([r[key] for r in rows]) for key in
                   ("frame_ms", "render_cpu_ms", "render_gpu_ms", "setup_cpu_ms", "pending", "active", "draw_calls", "primitives")}
        phases[name] = {"wall_s": duration, "fps": 1000 / metrics["frame_ms"]["mean"],
                        "ticks_per_s": (interval["end_tick"] - interval["start_tick"]) / duration,
                        "simulation_ratio": (interval["end_sim_s"] - interval["start_sim_s"]) / duration,
                        "focused_fraction": sum(r["focused"] for r in rows) / len(rows),
                        "frames_over_50_ms": sum(r["frame_ms"] > 50 for r in rows),
                        "frames_over_100_ms": sum(r["frame_ms"] > 100 for r in rows),
                        "frame_metrics": metrics, "cpu_ms": {k: stats(v) for k, v in cpu[name].items()},
                        "gpu_ms": {k: stats(v) for k, v in gpu[name].items()},
                        "detail_samples": detail[name],
                        "detail_ms": {k: stats([r[k] for r in detail[name]]) for k in
                                      ("total_ms", "coupled_ms", "visuals_ms", "boundary_ms", "remaining_ms")},
                        "viewports": {path: {k: stats([r["viewports"][path][k] for r in rows]) for k in ("cpu_ms", "gpu_ms")}
                                      for path in rows[0]["viewports"]}}
    result = {"phases": phases, "timeline_dropped": data["timeline"]["dropped"],
              "source_drift": data["metadata"]["source_drift"], "last_error": data["metadata"]["last_error"]}
    (directory / "summary.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    for name, phase in phases.items():
        print(name, json.dumps({k: phase[k] for k in ("fps", "simulation_ratio", "cpu_ms", "detail_ms")}))


if __name__ == "__main__":
    analyze(Path(sys.argv[1]))
