"""Pair device timestamps within one completed frame; keep nested spans separate."""
import argparse
from collections import defaultdict, deque, Counter
import hashlib
import json
import math
from pathlib import Path
import statistics


def stats(values):
    values = sorted(values)
    if not values:
        return {"n": 0}
    return {"n": len(values), "mean_ms": statistics.mean(values),
            "median_ms": statistics.median(values),
            "p95_ms": values[math.ceil(len(values) * .95) - 1],
            "p99_ms": values[math.ceil(len(values) * .99) - 1],
            "max_ms": values[-1], "sum_ms": sum(values)}


def analyze(folder):
    source = folder / "result.json"
    raw = json.loads(source.read_text(encoding="utf-8"))
    result = {"raw_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
              "functional_pass": raw["pass"], "cases": [], "timestamp_errors": [],
              "limits": ["CPU frame callback spacing is not Present/scanout latency.",
                         "GPU timestamps are ns for the recorded Godot D3D12 driver; CPU timestamps are us.",
                         "Batch, command and per-pass spans are nested; never sum them together.",
                         "Async callback delay contains GPU execution, queueing and frame recycle latency.",
                         "Viewport GPU time covers drawing, not the external compute batch.",
                         "Godot TIME_PROCESS/TIME_PHYSICS_PROCESS are cached one-second maxima in this engine, not per-frame CPU durations; excluded from CPU averages.",
                         "Synthetic event handler calls bypass OS event delivery and GUI routing.",
                         "Detailed run adds timestamp/observer overhead; compare with the undetailed run."]}
    for case in raw["cases"]:
        name = case["name"]
        rows = [r for r in raw["rows"] if r["case"] == name]
        active = [r for r in rows if r["type"] == "frame" and case["start_us"] < r["us"] <= case["stop_us"]]
        frames = [r["interval_us"] / 1000 for r in active]
        steady_frames = [r["interval_us"] / 1000 for r in active if r["us"] - r["interval_us"] >= case["start_us"] + 1000000]
        drain_frames = [r["interval_us"] / 1000 for r in rows if r["type"] == "frame" and case["stop_us"] < r["us"] <= case["drained_us"]]
        pairs = []
        ordered_gpu_frames = []
        for row in rows:
            if row["type"] != "gpu":
                continue
            starts = defaultdict(deque)
            fp_start = [m for m in row["marks"] if m["name"].startswith("fp_") and m["name"].endswith("_batch_start")]
            fp_end = [m for m in row["marks"] if m["name"].startswith("fp_") and m["name"].endswith("_batch_end")]
            vp_start = [m for m in row["marks"] if m["name"].startswith("vp_begin_")]
            vp_end = [m for m in row["marks"] if m["name"].startswith("vp_end_")]
            if len(fp_start) == len(fp_end) == len(vp_start) == len(vp_end) == 1:
                if fp_end[0]["gpu_ns"] <= vp_start[0]["gpu_ns"]:
                    ordered_gpu_frames.append({"frame": row["frame"], "batch": int(fp_start[0]["name"].split("_")[1]),
                                               "batch_ms": (fp_end[0]["gpu_ns"] - fp_start[0]["gpu_ns"]) / 1e6,
                                               "gap_ms": (vp_start[0]["gpu_ns"] - fp_end[0]["gpu_ns"]) / 1e6,
                                               "viewport_ms": (vp_end[0]["gpu_ns"] - vp_start[0]["gpu_ns"]) / 1e6,
                                               "batch_to_viewport_end_ms": (vp_end[0]["gpu_ns"] - fp_start[0]["gpu_ns"]) / 1e6})
            for mark in row["marks"]:
                label = mark["name"]
                if label.endswith("_start"):
                    starts[label[:-6]].append(mark)
                elif label.endswith("_end") and starts[label[:-4]]:
                    begin = starts[label[:-4]].popleft()
                    pair = {"name": label[:-4], "frame": row["frame"],
                            "gpu_ms": (mark["gpu_ns"] - begin["gpu_ns"]) / 1e6,
                            "cpu_record_ms": (mark["cpu_us"] - begin["cpu_us"]) / 1000}
                    if pair["gpu_ms"] < 0:
                        result["timestamp_errors"].append([name, pair])
                    pairs.append(pair)
        by_stage = defaultdict(list)
        by_batch = defaultdict(list)
        captured_marks = Counter()
        for pair in pairs:
            key = pair["name"]
            if key.startswith("fp_"):
                parts = key.split("_", 3)
                key = parts[3]
                if key.startswith("command_"):
                    key = "command"
                by_batch[int(parts[1])].append(pair)
                captured_marks[pair["name"]] += 1
            elif key.startswith("edit_"):
                parts = key.split("_")
                key = "_".join(parts[:2] + parts[3:])
            by_stage[key].append(pair["gpu_ms"])
        admitted = [r for r in case["input_events"] if not r["admission_error"]]
        inputs = {r["command"]["command_id"]: r for r in admitted}
        spans = defaultdict(list)
        commands = []
        batches = []
        cursor = 0
        expected_marks = []
        for batch in case["batches"]:
            ids = batch.get("command_ids", [r["command"]["command_id"] for r in admitted[cursor:cursor + batch["count"]]])
            cursor += batch["count"]
            bt = {"submit_to_receipt": (batch["receipt_us"] - batch["submitted_us"]) / 1000,
                  "receipt_to_publish": (batch["published_us"] - batch["receipt_us"]) / 1000,
                  "publish_to_collision_applied": (batch["collision_applied_us"] - batch["published_us"]) / 1000,
                  "collision_applied_to_done": (batch["done_us"] - batch["collision_applied_us"]) / 1000,
                  "submit_to_done": (batch["done_us"] - batch["submitted_us"]) / 1000}
            if "callback_us" in batch:
                bt["submit_to_callback"] = (batch["callback_us"] - batch["submitted_us"]) / 1000
                bt["callback_to_receipt"] = (batch["receipt_us"] - batch["callback_us"]) / 1000
            metrics = batch["metrics"]
            if "record_begin_us" in metrics:
                bt["record_cpu"] = (metrics["record_end_us"] - metrics["record_begin_us"]) / 1000
                bt["submit_to_record_begin"] = (metrics["record_begin_us"] - batch["submitted_us"]) / 1000
            for key in ["encode_cpu_us", "settle_cpu_us"]:
                if key in batch:
                    bt[key[:-3]] = batch[key] / 1000
            fp = batch.get("finish_profile", {})
            if fp:
                bt["publish_record_cpu"] = (fp["publish_end_us"] - fp["publish_begin_us"]) / 1000
                bt["cleanup_cpu"] = (fp["cleanup_end_us"] - fp["publish_end_us"]) / 1000
            for span in metrics.get("cpu_spans", []):
                expected_marks.append(span["mark"])
                stage = span["mark"].split("_", 3)[3]
                if stage in ["backup", "setup"]:
                    bt[stage + "_cpu"] = (span["end_us"] - span["start_us"]) / 1000
            gpu = by_batch[batch["batch"]]
            for pair in gpu:
                stage = pair["name"].split("_", 3)[3]
                if stage == "batch": bt["gpu_batch"] = pair["gpu_ms"]
            for key, value in bt.items():
                spans["batch_" + key].append(value)
            batches.append({"batch": batch["batch"], "count": batch["count"], "spans_ms": bt})
            for cid in ids:
                first = inputs[cid]["input_us"]
                ct = {"input_to_submit": (batch["submitted_us"] - first) / 1000,
                      "input_to_publish": (batch["published_us"] - first) / 1000,
                      "input_to_collision_applied": (batch["collision_applied_us"] - first) / 1000,
                      "input_to_done": (batch["done_us"] - first) / 1000}
                for key, value in ct.items(): spans[key].append(value)
                commands.append({"id": cid, "batch": batch["batch"], "spans_ms": ct})
        missing = [key for key in expected_marks if captured_marks[key] != 1]
        if missing: result["timestamp_errors"].append({"case": name, "missing_or_duplicate": missing})
        input_rows = [r for r in rows if r["type"] == "input"]
        elapsed_s = (case["stop_us"] - case["start_us"]) / 1e6
        cs = {"name": name, "config": case["config"], "active_s": elapsed_s,
              "drain_ms": (case["drained_us"] - case["stop_us"]) / 1000,
              "active_ticks": case["stop_tick"] - case["begin_tick"],
              "input_events": len(case["input_events"]), "admitted": len(admitted), "terminal": len(case["terminals"]),
              "max_pending": max([r["pending"] for r in active], default=0), "pending_at_stop": case["pending_at_stop"],
              "active_frames": stats(frames), "drain_frames": stats(drain_frames),
              "after_first_second_frames": stats(steady_frames),
              "active_fps": len(frames) / elapsed_s,
              "over_33ms": sum(v > 33.333 for v in frames), "over_50ms": sum(v > 50 for v in frames), "over_100ms": sum(v > 100 for v in frames),
              "input_handler_cpu": stats([(r["end_us"] - r["begin_us"]) / 1000 for r in input_rows]),
              "synthetic_delivery_lateness": stats([(r["begin_us"] - r["scheduled_us"]) / 1000 for r in input_rows]),
              "spans": {k: stats(v) for k, v in spans.items()},
              "gpu_stages": {k: stats(v) for k, v in by_stage.items()}, "batches": batches, "commands": commands,
              "gpu_pairs": pairs, "gpu_coverage": {"expected": len(expected_marks), "paired_once": len(expected_marks) - len(missing)},
              "ordered_gpu_frames": ordered_gpu_frames,
              "batch_then_draw_gpu": stats([r["batch_to_viewport_end_ms"] for r in ordered_gpu_frames]),
              "cpu_monitors": {k: stats([r[k] for r in active]) for k in ["render_cpu_ms", "render_setup_cpu_ms", "render_gpu_ms"]},
              "cached_one_second_monitor_max_ms": {k: max([r[k] for r in active], default=None) for k in ["process_ms", "physics_ms"]},
              "collision_cpu": stats([r["apply_ms"] for r in case["collision"]]),
              "collision_readback": stats([r["readback_ms"] for r in case["collision"]]),
              "collision_chunks": dict(Counter(r["chunks"] for r in case["collision"])),
              "longest_frames": sorted(active, key=lambda r: r["interval_us"], reverse=True)[:10]}
        result["cases"].append(cs)
    telemetry_path = folder / "telemetry.jsonl"
    if telemetry_path.exists():
        telemetry = [json.loads(line) for line in telemetry_path.read_text().splitlines()]
        for summary, case in zip(result["cases"], raw["cases"]):
            start = case["config"]["start_unix_s"]
            stop = start + (case["stop_us"] - case["start_us"]) / 1e6
            samples = [t for t in telemetry if start <= t["utc_ns"] / 1e9 <= stop]
            summary["telemetry"] = {
                "gpu_busy_percent_device_wide": [t["gpu_percent"] for t in samples if "gpu_percent" in t],
                "gpu_clock_mhz": [t["graphics_clock_mhz"] for t in samples if "graphics_clock_mhz" in t],
                "other_godot_pids": sorted({p["pid"] for t in samples for p in t["processes"] if p["pid"] != case["config"]["pid"]}),
                "process_cpu_percent_one_core": [100 * (b["process_cpu_us"] - a["process_cpu_us"]) / ((b["monotonic_ns"] - a["monotonic_ns"]) / 1000)
                                                 for a, b in zip(samples, samples[1:])]}
    (folder / "analysis.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    for case in result["cases"]:
        print(json.dumps({key: case[key] for key in ["name", "active_fps", "active_frames", "active_ticks", "admitted", "pending_at_stop", "drain_ms", "gpu_coverage"]}))
        print("GPU_TOP", json.dumps(sorted(((key, value) for key, value in case["gpu_stages"].items() if key.startswith("water_") or key.startswith("sand_") or key in ["batch", "command", "backup", "setup"]), key=lambda item: item[1]["sum_ms"], reverse=True)[:12]))
        print("CPU_AND_LATENCY", json.dumps({"spans": case["spans"], "input_cpu": case["input_handler_cpu"], "collision_cpu": case["collision_cpu"], "monitors": case["cpu_monitors"]}))
    print("TIMESTAMP_ERRORS", json.dumps(result["timestamp_errors"]))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("folder", type=Path)
    analyze(parser.parse_args().folder)
