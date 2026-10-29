"""Summarize sequential visible scene measurements without merging probe scopes."""
import json
import math
import statistics
import sys
from pathlib import Path


def read(path):
    return json.loads(path.read_text(encoding="utf-8"))


def stats(values):
    ordered = sorted(values)
    return {"n": len(ordered), "mean": statistics.mean(ordered),
            "p95": ordered[math.ceil(len(ordered) * .95) - 1],
            "p99": ordered[math.ceil(len(ordered) * .99) - 1], "max": ordered[-1]}


directory = Path(sys.argv[1])
names = ["baseline", "step1_cost", "step2_cost", "step3_cost",
         "reverse_baseline", "controlled_candidate"]
result = {"scope": "Visible scene2, sequential processes; CPU ABBA is a separate instrumented run.",
          "scenes": {}, "sequential_source_changes": {}}
previous_sources = None
for name in names:
    capture = read(directory / name / "capture.json")
    meta = capture["metadata"]
    assert not meta["source_drift"] and not meta["last_error"], name
    phases = {}
    for interval in meta["intervals"]:
        phase = interval["phase"]
        rows = [row for row in capture["frames"] if row["phase"] == phase]
        frame = stats([row["frame_ms"] for row in rows])
        phases[phase] = {"frame_ms": frame, "fps": 1000 / frame["mean"],
                         "viewport_gpu_ms": stats([row["render_gpu_ms"] for row in rows]),
                         "focused_fraction": sum(row["focused"] for row in rows) / len(rows),
                         "simulation_ratio": (interval["end_sim_s"] - interval["start_sim_s"]) /
                         ((interval["end_us"] - interval["start_us"]) / 1e6),
                         "completed_ticks": interval["end_tick"] - interval["start_tick"]}
    result["scenes"][name] = {"phases": phases, "window": meta["window"], "vsync": meta["vsync"],
                              "configuration_hash": meta["configuration"]["configuration_hash"],
                              "runtime_override": meta.get("runtime_override")}
    if name in names[:4]:
        sources = meta["configuration"]["sources"]
        if previous_sources is not None:
            result["sequential_source_changes"][name] = sorted(
                key for key in set(sources) | set(previous_sources)
                if sources.get(key) != previous_sources.get(key))
        previous_sources = sources

result["exact"] = {}
for name in ["step1_exact_v2", "step2_exact", "step3_exact", "final_exact"]:
    data = read(directory / name / "exact.json")
    assert data["pass"] and all(row["pass"] for row in data["checks"]), name
    result["exact"][name] = {"checks": len(data["checks"]), "states": len(data["observations"])}

abba = read(directory / "step3_cpu_abba/summary.json")
assert not read(directory / "step3_cpu_abba/capture.json")["metadata"]["source_drift"]
before = abba["pooled"]["before"]["cpu_submit_ms"]["mean"]
after = abba["pooled"]["after"]["cpu_submit_ms"]["mean"]
result["cpu_abba"] = {"before_ms": before, "after_ms": after, "reduction_fraction": 1 - after / before,
                      "scope": "Entire CPU submit batch, not isolated MUSCL self time; evolving scene."}
restart = read(directory / "final_restart/comparison.json")
assert restart["outcome"] == "pass"
result["cold_restart"] = {"outcome": restart["outcome"], "checks": len(restart["checks"])}
(directory / "summary.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"fps": {name: value["phases"]["live"]["fps"] for name, value in result["scenes"].items()},
                  "cpu_abba": result["cpu_abba"], "cold_restart": result["cold_restart"]}, indent=2))
