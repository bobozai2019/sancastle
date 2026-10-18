"""Compare time bins in a long shovel trace; GPU and CPU clocks stay separate."""
import bisect
from collections import Counter, defaultdict
import hashlib
import json
from pathlib import Path
import re
import sys

from analyze_shovel_latency import stats


def analyze(path):
    data = json.loads(path.read_text(encoding="utf-8-sig"))
    base = json.loads(path.with_suffix(".analysis.json").read_text(encoding="utf-8"))
    frames = data["frames"]
    times = [row["at_us"] for row in frames]

    def phase(at):
        index = bisect.bisect_right(times, at) - 1
        return frames[index]["phase"] if index >= 0 else "warmup"

    calls = {int(row["serial"]): row for row in data["observations"].get("water_calls", [])}
    batches = {str(row["key"]): row for row in data["observations"]["timeline"]["events"]
               if row["event"] == "batch_queued"}
    gpu = defaultdict(lambda: defaultdict(list))
    slow = []
    for capture in data["gpu_samples"]:
        for span in capture["spans"]:
            label = span["label"]
            match = re.fullmatch(r"shovel_water_(\d+)_(.+)", label)
            ms = span["gpu_ns"] / 1e6
            if match and int(match[1]) in calls:
                call = calls[int(match[1])]
                tag = phase(call["at_us"])
                gpu[tag][match[2]].append(ms)
                if match[2] == "displace" and ms > 5:
                    slow.append({**call, "phase": tag, "ms": ms})
            elif label.startswith("ue_batch_"):
                batch = batches.get(label.removeprefix("ue_batch_"))
                if batch:
                    gpu[phase(batch["at_us"])]["batch_kind_" + str(batch["detail"]["kind"])].append(ms)
    phases = {}
    for tag in dict.fromkeys(row["phase"] for row in frames):
        rows = [row for row in frames if row["phase"] == tag and row["frame_us"] > 0]
        if not rows:
            continue
        selected = [row for row in batches.values() if phase(row["at_us"]) == tag and row["detail"]["kind"] == 0]
        phases[tag] = {
            "frame_ms": stats([row["frame_us"] / 1000 for row in rows]),
            "pending": stats([row["pending"] for row in rows]),
            "waiting_results": stats([row["waiting_results"] for row in rows]),
            "commands_per_edit_batch": stats([len(row["detail"]["commands"]) for row in selected]),
            "gpu_ms": {name: stats(values) for name, values in gpu[tag].items()},
            "cpu_ms": {name: value for name, value in base["phase_ms"].get(tag, {}).items()
                       if "cpu" in name and "overlap" not in name},
            "tick_first": rows[0]["tick"], "tick_last": rows[-1]["tick"],
            "memory_static_first": rows[0].get("memory_static"),
            "memory_static_last": rows[-1].get("memory_static"),
            "render_primitives": stats([row["render_primitives"] for row in rows]),
            "focused_frames": sum(row["window_focused"] for row in rows),
        }
    result = {"input": str(path), "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
              "measurement_valid": base["measurement_valid"], "phases": phases,
              "slow_displace_samples": slow,
              "admission_errors": base["input_rejections"],
              "result_outcomes_last_128": dict(Counter(str((row.get("outcome"), row.get("error_code"))) for row in data["observations"]["results"])),
              "automated_input_uninterrupted": not any(row["response"].get("error") == "no_active_stroke" for row in data["observations"]["sample_calls"]) if not base["options"].get("manual") else None,
              "limits": ["Water samples mapped by render-thread CPU recording time, not absolute GPU time.",
                         "Sparse first-water-response-per-frame sampling can miss slower later commands.",
                         "Wall-time bins contain different input counts and simulation progress."]}
    output = path.with_suffix(".progression.json")
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"valid": result["measurement_valid"], "slow_displace": len(slow),
                      "phases": {tag: {"frame_p95": row["frame_ms"]["p95"],
                                       "pending_max": row["pending"]["max"],
                                       "gpu_p50": {name: values["p50"] for name, values in row["gpu_ms"].items()}}
                                 for tag, row in phases.items()}}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    analyze(Path(sys.argv[1]))
