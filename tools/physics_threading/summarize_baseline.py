"""Summarize raw monotonic observations without calling post_draw display scanout."""
import json
import math
import sys
from pathlib import Path


def distribution(values):
    ordered = sorted(values)
    if not ordered:
        return {"n": 0}
    result = {"n": len(ordered)}
    for name, fraction in [("p50", .5), ("p95", .95), ("p99", .99), ("p999", .999)]:
        result[name] = ordered[max(0, math.ceil(len(ordered) * fraction) - 1)]
    result["max"] = ordered[-1]
    return result


def summarize(folder):
    trace = json.loads((folder / "trace.json").read_text(encoding="utf-8"))
    summaries = []
    for case in trace["cases"]:
        rows = [r for r in trace["rows"] if r["case"] == case["name"]]
        frames = [r["interval_us"] / 1000 for r in rows if r["type"] == "frame" and r["us"] < case["stop_us"]]
        collisions = [r for r in rows if r["type"] == "collision"]
        phases = [r["value"] for r in rows if r["type"] == "phase"]
        grouped = {}
        for phase in phases:
            grouped.setdefault(str(phase["command_id"]), []).append(phase)
        phase_names = sorted({p["phase"] for p in phases})
        transaction_spans = []
        for group in grouped.values():
            if group[0]["command_id"] >= 0 and len(group) > 1:
                transaction_spans.append((group[-1]["at_us"] - group[0]["at_us"]) / 1000)
        inputs = [r for r in rows if r["type"] == "input_call"]
        admitted = {str(row["command"]["command_id"]): row["input_us"]
                    for row in case["inputs"] if not row.get("admission_error")}
        collision_feedback = []
        physics_feedback = []
        transaction_feedback = []
        stage_pairs = [("dispatch", "receipt_ready"), ("receipt_ready", "publication_ready"),
                       ("publication_ready", "collision_ready"), ("collision_ready", "physics_one"),
                       ("physics_one", "physics_two")]
        waits = {a + "_to_" + b: [] for a, b in stage_pairs}
        for group in grouped.values():
            marks = {p["phase"]: p["at_us"] for p in group}
            for a, b in stage_pairs:
                if a in marks and b in marks and marks[b] >= marks[a]:
                    waits[a + "_to_" + b].append((marks[b]-marks[a])/1000)
        for command_id, admitted_us in admitted.items():
            for phase in grouped.get(command_id, []):
                if phase["phase"] == "collision_ready":
                    collision_feedback.append((phase["at_us"] - admitted_us) / 1000)
                elif phase["phase"] == "physics_two":
                    physics_feedback.append((phase["at_us"] - admitted_us) / 1000)
            for terminal in case["terminals"]:
                if str(terminal["command"]["command_id"]) == command_id:
                    transaction_feedback.append((terminal["at_us"] - admitted_us) / 1000)
        summary = {
            "name": case["name"], "window_s": (case["stop_us"] - case["start_us"]) / 1e6,
            "frame_ms": distribution(frames),
            "stalls": {str(bound): sum(x > bound for x in frames) for bound in [100, 250, 500]},
            "ticks_at_drain": case["end_tick"] - case["begin_tick"],
            "window_tick_rate": ((case["stop_tick"]-case["begin_tick"])/((case["stop_us"]-case["start_us"])/1e6)
                                 if "stop_tick" in case else None),
            "admission_to_collision_ack_ms": distribution(collision_feedback),
            "admission_to_physics_two_ms": distribution(physics_feedback),
            "admission_to_terminal_ms": distribution(transaction_feedback),
            "stage_wall_ms": {key: distribution(values) for key, values in waits.items()},
            "input_calls": len(inputs), "admitted_observation": sum(r.get("admitted", False) for r in inputs),
            "error": case["error"], "collision_apply_ms": distribution([r["apply_ms"] for r in collisions]),
            "readback_ms": distribution([r["readback_ms"] for r in collisions]),
            "segments_us": {key: distribution([r["segments"][key] for r in collisions if key in r["segments"]])
                            for key in ["decode_us", "finite_us", "slice_us", "submit_us", "apply_us", "callback_to_apply_us"]},
            "prepare_cpu_us": distribution([sum(r["segments"].get(k, 0) for k in
                                                ["decode_us", "finite_us", "slice_us"]) for r in collisions
                                            if all(k in r["segments"] for k in ["decode_us", "finite_us", "slice_us"])]),
            "observed_phase_span_ms": distribution(transaction_spans), "phase_names": phase_names,
        }
        summaries.append(summary)
    result = {"configuration": trace["configuration"], "released": trace["released"], "cases": summaries,
              "limits": ["post_draw observes submission, not scanout", "ticks_at_drain includes drain; not window throughput",
                         "phase span starts at first recorded phase, not necessarily admission",
                         "one collision record per observed process frame may coalesce callbacks"]}
    (folder / "summary.json").write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding="utf-8")
    for item in summaries:
        print(item["name"], "frame", item["frame_ms"], "apply", item["collision_apply_ms"], "segments", item["segments_us"])


if __name__ == "__main__":
    for name in sys.argv[1:]:
        summarize(Path(name))
