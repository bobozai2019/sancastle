"""Analyze opt-in diagnostics; CPU delivery latency is NOT GPU execution time.

Usage: python tools/unified_edit_pipeline/analyze_shovel_latency.py RUN.json
Writes RUN.analysis.json and RUN.trace.json (Perfetto/Chrome CPU timeline).
"""
import bisect
from collections import Counter, defaultdict
import json
from pathlib import Path
import re
import sys


def stats(values):
    values = sorted(values)
    if not values:
        return {"n": 0}
    def quantile(p):
        x = (len(values) - 1) * p
        i = int(x)
        return values[i] + (values[min(i + 1, len(values) - 1)] - values[i]) * (x - i)
    return {"n": len(values), "p50": quantile(.5), "p95": quantile(.95),
            "max": values[-1], "sum": sum(values)}


BATCH_SPANS = {
    "build_cpu": ("batch_build", "batch_queued"),
    "main_to_render": ("batch_queued", "submit_begin"),
    "record_cpu": ("submit_begin", "submit_end"),
    "record_end_to_callback": ("submit_end", "readback_callback"),
    "callback_to_main": ("readback_callback", "receive_begin"),
    "receipt_validation_cpu": ("receive_begin", "receive_end"),
    "received_to_poll": ("receive_end", "consume_begin"),
    "settlement_cpu": ("consume_begin", "settle_end"),
    "settled_to_render_retire": ("settle_end", "retire_render"),
    "render_retire_to_free": ("retire_render", "slot_free"),
    "callback_to_slot_free": ("readback_callback", "slot_free"),
    "slot_lifetime": ("batch_build", "slot_free"),
}


def interval_overlap_query(intervals):
    """Sum interval overlaps in O(log n), retaining nested-span accounting."""
    intervals = list(intervals)
    starts = sorted(a for a, _ in intervals)
    ends = sorted(b for _, b in intervals)
    def prefix(values):
        result = [0]
        for value in values:
            result.append(result[-1] + value)
        return result
    start_sum, end_sum = prefix(starts), prefix(ends)
    def integral(at):
        a, b = bisect.bisect_right(starts, at), bisect.bisect_right(ends, at)
        return at * (a-b) - start_sum[a] + end_sum[b]
    return lambda begin, end: integral(end) - integral(begin)


def analyze(path):
    data = json.loads(path.read_text(encoding="utf-8-sig"))
    log = path.with_suffix(".log").read_text(encoding="utf-8", errors="replace") if path.with_suffix(".log").exists() else ""
    runtime_errors = [line for line in log.splitlines() if line.startswith(("ERROR:", "SCRIPT ERROR:"))]
    obs = data["observations"]
    events = sorted(obs["timeline"]["events"], key=lambda r: r["at_us"])
    frames = data["frames"]
    frame_times = [r["at_us"] for r in frames]
    def phase(at):
        index = bisect.bisect_right(frame_times, at) - 1
        return frames[index]["phase"] if index >= 0 else "warmup"

    batches, heights, commands = defaultdict(dict), defaultdict(dict), defaultdict(dict)
    trace = []
    cpu_spans = defaultdict(list)
    for event in events:
        name, key = event["event"], str(event["key"])
        if name.startswith("height_"):
            # A bounded height consumer may apply one snapshot over several
            # frames. Each slice is a CPU interval; waiting between is not CPU.
            height_key = (key + "/slice_" + str(event["detail"]["slice_id"])
                          if name in {"height_apply_begin", "height_apply_end"} and "slice_id" in event["detail"] else key)
            heights[height_key][name] = event
        elif name in {"enqueue", "result_taken"}:
            commands[key][name] = event
        elif name in {x for pair in BATCH_SPANS.values() for x in pair}:
            batches[key][name] = event
        trace.append({"name": name, "cat": "pipeline", "ph": "i", "s": "t",
                      "pid": 1, "tid": event["thread"], "ts": event["at_us"],
                      "args": {"key": key, **event["detail"]}})

    def span(name, start, end, key=""):
        if end["at_us"] < start["at_us"]:
            raise ValueError(f"non-monotonic span: {name}/{key}")
        trace.append({"name": name, "cat": "duration", "ph": "X", "pid": 1,
                      "tid": start["thread"], "ts": start["at_us"],
                      "dur": end["at_us"] - start["at_us"], "args": {"key": key}})
        if name.endswith("_cpu"):
            cpu_spans[name].append((start["at_us"], end["at_us"]))

    by_phase = defaultdict(lambda: defaultdict(list))
    batch_details = []
    for key, row in batches.items():
        if "batch_queued" not in row:
            continue
        queued = row["batch_queued"]
        tag = phase(queued["at_us"])
        detail = {"batch": key, "phase": tag, **queued["detail"], "ms": {}}
        for name, (a, b) in BATCH_SPANS.items():
            if a in row and b in row:
                ms = (row[b]["at_us"] - row[a]["at_us"]) / 1000
                by_phase[tag][name].append(ms)
                detail["ms"][name] = ms
                if name.endswith("_cpu"):
                    span(name, row[a], row[b], key)
                else:
                    # Asynchronous waits use separate logical lanes, not CPU occupancy.
                    trace.extend([
                        {"name": name, "cat": "wait", "ph": "b", "pid": 2, "tid": 0,
                         "ts": row[a]["at_us"], "id": f"{key}/{name}"},
                        {"name": name, "cat": "wait", "ph": "e", "pid": 2, "tid": 0,
                         "ts": row[b]["at_us"], "id": f"{key}/{name}"}])
        for cid in queued["detail"]["commands"]:
            command = commands[str(cid)]
            if "enqueue" not in command:
                continue
            begin = command["enqueue"]
            command_tag = phase(begin["at_us"])
            for name, end in (("command_queue", row.get("submit_begin")),
                              ("command_to_received", row.get("receive_end")),
                              ("command_to_settled", row.get("settle_end")),
                              ("command_to_taken", command.get("result_taken"))):
                if end:
                    by_phase[command_tag][name].append((end["at_us"] - begin["at_us"]) / 1000)
        batch_details.append(detail)

    # A freed slot still cannot issue pending work until a later pump.
    last_free = {}
    for event in events:
        row = batches.get(str(event["key"]), {})
        queued = row.get("batch_queued")
        if not queued:
            continue
        slot = queued["detail"]["slot"]
        if event["event"] == "slot_free":
            last_free[slot] = event["at_us"]
        elif event["event"] == "batch_build" and slot in last_free:
            by_phase[phase(event["at_us"])]["free_to_next_acquire"].append((event["at_us"]-last_free.pop(slot))/1000)

    pump_start = None
    for event in events:
        if event["event"] == "pump_begin":
            pump_start = event
        elif event["event"] == "pump_end" and pump_start:
            span("pump_cpu", pump_start, event)
            by_phase[phase(pump_start["at_us"])]["pump_cpu"].append((event["at_us"]-pump_start["at_us"])/1000)
            pump_start = None
    for key, row in heights.items():
        pairs = {"height_readback_delivery": ("height_capture_render", "height_readback_callback"),
                 "height_callback_to_main": ("height_readback_callback", "height_receive"),
                 "height_apply_cpu": ("height_apply_begin", "height_apply_end")}
        for name, (a, b) in pairs.items():
            if a in row and b in row:
                by_phase[phase(row[a]["at_us"])][name].append((row[b]["at_us"]-row[a]["at_us"])/1000)
                if name.endswith("_cpu"):
                    span(name, row[a], row[b], key)
        if "height_apply_begin" in row:
            event = row["height_apply_begin"]
            timings = event["detail"]["timings"]
            if timings:
                start, end = min(t["start_usec"] for t in timings), max(t["end_usec"] for t in timings)
                tag = phase(start)
                by_phase[tag]["height_worker_cpu"].append((end-start)/1000)
                by_phase[tag]["height_worker_done_to_apply"].append((event["at_us"]-end)/1000)
                trace.append({"name": "height_worker_cpu", "ph": "X", "pid": 1, "tid": timings[0]["thread_id"],
                              "ts": start, "dur": end-start, "args": {"snapshot": key}})

    blocked = defaultdict(Counter)
    ordered_blocked = Counter()
    for event in events:
        if event["event"] == "slot_blocked":
            blocked[phase(event["at_us"])][str(event["detail"]["states"])] += 1
        if event["event"] == "ordered_wait" and 3 in event["detail"]["states"]:
            ordered_blocked[phase(event["at_us"])] += 1
    for row in obs["sample_calls"]:
        for key in ("move_cpu_us", "pick_cpu_us", "preview_submit_cpu_us"):
            if key in row:
                by_phase[row["phase"]][key.removesuffix("_us")].append(row[key]/1000)
    phase_frames = defaultdict(list)
    top_frames = []
    overlap_queries = {name: interval_overlap_query(intervals) for name, intervals in cpu_spans.items()}
    shape_overlap = interval_overlap_query((c["start_us"], c["start_us"]+c["elapsed_us"]) for c in obs["collision_calls"])
    for row in frames:
        if row["frame_us"] <= 0:
            continue
        tag, at, duration = row["phase"], row["at_us"], row["frame_us"]
        phase_frames[tag].append(row)
        by_phase[tag]["frame"].append(duration/1000)
        contributions = {}
        for name, overlap in overlap_queries.items():
            value = overlap(at-duration, at)/1000
            contributions[name] = value
            by_phase[tag][name+"_per_frame_overlap"].append(value)
        shape_us = shape_overlap(at-duration, at)
        by_phase[tag]["shape_cpu_per_frame_overlap"].append(shape_us/1000)
        top_frames.append({"phase": tag, "frame": row["frame_id"], "ms": duration/1000,
                           "pending": row["pending"], "slots": row["active_slots"],
                           "shape_ms": shape_us/1000, "cpu_spans_ms_overlapping_interval": contributions})
        trace.append({"name": "queue", "ph": "C", "pid": 1, "tid": 0, "ts": at,
                      "args": {"pending": row["pending"], "slots": row["active_slots"], "frame_ms": duration/1000}})

    gpu_groups = defaultdict(list)
    for capture in data["gpu_samples"]:
        for sample in capture["spans"]:
            name = sample["label"]
            if name.startswith("ue_batch_"):
                key = name.removeprefix("ue_batch_")
                row = batches.get(key, {}).get("batch_queued")
                if row:
                    by_phase[phase(row["at_us"])]["gpu_batch_kind_"+str(row["detail"]["kind"])].append(sample["gpu_ns"]/1e6)
            if name.startswith("shovel_water_"):
                name = re.sub(r"shovel_water_\d+_", "shovel_water_", name)
            elif name.startswith("shovel_stage_"):
                name = re.sub(r"shovel_stage_\d+_", "shovel_stage_", name)
            elif name.startswith(("ue_batch_", "uep_cost_edit_")):
                continue
            gpu_groups[name].append(sample["gpu_ns"]/1e6)

    rates = {}
    for tag, rows in phase_frames.items():
        seconds = (rows[-1]["at_us"]-rows[0]["at_us"])/1e6
        rates[tag] = {"wall_s": seconds, "ticks_delta": rows[-1]["tick"]-rows[0]["tick"],
                      "simulation_s_delta": rows[-1]["time_s"]-rows[0]["time_s"],
                      "max_pending": max(r["pending"] for r in rows),
                      "slot_blocked_pumps": sum(blocked[tag].values()),
                      "ordered_wait_with_later_complete": ordered_blocked[tag],
                      "slot_blocked_states": dict(blocked[tag])}
    quality_errors = []
    options = obs["diagnostic_options"]
    if options.get("manual") and not any(e["event"] == "enqueue" for e in events):
        quality_errors.append("Manual capture contains no accepted edit commands; cannot attribute an editing stall.")
    if not options.get("manual") and (options.get("water_detail") or options.get("water_only")) and not gpu_groups.get("shovel_water_total"):
        quality_errors.append("Requested water-stage markers are absent; batch timers alone cannot validate water-stage attribution.")
    output = {"input": str(path), "pass": data["pass"], "measurement_valid": data["pass"] and not runtime_errors and not quality_errors,
              "quality_errors": quality_errors,
              "runtime_errors":dict(Counter(runtime_errors)), "source_integrity": obs["source_integrity"],
              "options": obs["diagnostic_options"], "event_count": len(events),
              "dropped": obs["timeline"]["dropped"], "phase_ms": {p: {n: stats(v) for n,v in values.items()} for p,values in by_phase.items()},
              "rates": rates, "gpu_ms": {k: stats(v) for k,v in gpu_groups.items()},
              "top_frames": sorted(top_frames, key=lambda r:r["ms"], reverse=True)[:20],
              "batches": batch_details,
              "input_rejections": dict(Counter(str(r["response"].get("error")) for r in obs["sample_calls"] if not r["response"].get("accepted", False))),
              "limits": ["record_end_to_callback includes queueing, GPU work, transfer, and engine callback delivery; not a GPU timer.",
                         "Callback-to-free measures observed CPU turnaround, not GPU-finish-to-free.",
                         "CPU spans can nest or run on different threads; do not sum them as frame cost.",
                         "Shape calls are intersected with actual process-frame timestamp intervals.",
                         "GPU duration markers use a separate clock; no CPU/GPU absolute alignment is claimed."]}
    path.with_suffix(".analysis.json").write_text(json.dumps(output,ensure_ascii=False,indent=2),encoding="utf-8")
    path.with_suffix(".trace.json").write_text(json.dumps({"traceEvents":trace},ensure_ascii=False),encoding="utf-8")
    print(json.dumps({"pass":data["pass"], "measurement_valid":output["measurement_valid"], "events":len(events), "changed":obs["source_integrity"]["changed"],
                      "frame_ms":{p:stats([r["frame_us"]/1000 for r in rows]) for p,rows in phase_frames.items()}},ensure_ascii=False))


if __name__ == "__main__":
    analyze(Path(sys.argv[1]))
