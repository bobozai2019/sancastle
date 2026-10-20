"""Compare current-main deferred-reference and owner-thread-ACK captures.

Pool raw observations, never averages of percentiles. Retain per-run variation,
source identity, foreground status and Godot process snapshots.
"""
import argparse
import bisect
from collections import Counter, defaultdict
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/unified_edit_pipeline"))
from analyze_shovel_latency import stats


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def collect(path):
    raw = read(path)
    analysis = read(path.with_suffix(".analysis.json"))
    manifest = read(path.with_suffix(".manifest.json"))
    events = sorted(raw["observations"]["timeline"]["events"], key=lambda e: e["at_us"])
    times = [f["at_us"] for f in raw["frames"]]

    def phase(at):
        index = bisect.bisect_right(times, at) - 1
        return raw["frames"][index]["phase"] if index >= 0 else "warmup"

    values = defaultdict(list)
    live_frames = [f for f in raw["frames"] if f["phase"] == "playing_drag" and f["frame_us"] > 0]
    values["frame"] = [f["frame_us"] / 1000 for f in live_frames]
    enqueue = {e["key"]: e for e in events if e["event"] == "enqueue"}
    batches = defaultdict(dict)
    for e in events:
        if e["event"] in {"batch_queued", "submit_begin", "settle_end"}:
            batches[e["key"]][e["event"]] = e
    for batch in batches.values():
        if "batch_queued" not in batch:
            continue
        for cid in batch["batch_queued"]["detail"]["commands"]:
            begin = enqueue.get(cid)
            if not begin or phase(begin["at_us"]) != "playing_drag":
                continue
            for name, end in [("command_queue", "submit_begin"), ("command_to_settled", "settle_end")]:
                if end in batch:
                    values[name].append((batch[end]["at_us"] - begin["at_us"]) / 1000)
    for batch in analysis["batches"]:
        if batch["phase"] != "playing_drag":
            continue
        for name in ["render_retire_to_free", "callback_to_slot_free"]:
            if name in batch["ms"]:
                values[name].append(batch["ms"][name])
        values["record_cpu_kind_" + str(batch["kind"])].append(batch["ms"]["record_cpu"])
    blocked = [e for e in events if e["event"] == "slot_blocked" and phase(e["at_us"]) == "playing_drag"]
    counts = {
        "frames": len(live_frames),
        "frames_gt_33_333_ms": sum(f["frame_us"] > 33333 for f in live_frames),
        "frames_gt_50_ms": sum(f["frame_us"] > 50000 for f in live_frames),
        "unfocused_frames": sum(not f["window_focused"] for f in live_frames),
        "slot_blocked_pumps": len(blocked),
        "blocked_with_cpu_reclaim": sum(4 in e["detail"]["states"] for e in blocked),
    }
    runtime = raw["runtime"]
    sources = dict(runtime["configuration"]["sources"])
    sources.update(raw["observations"]["source_integrity"]["probe_sources"])
    record = {
        "file": str(path.resolve()), "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        "valid": analysis["measurement_valid"] and analysis["dropped"] == 0,
        "source_integrity": analysis["source_integrity"],
        "configuration": raw["observations"]["current_probe"],
        "runtime": {k: runtime[k] for k in ["adapter", "driver", "engine", "vsync", "window"]},
        "counts": counts, "ms": {k: stats(v) for k, v in values.items()},
        "rates": analysis["rates"]["playing_drag"],
        "input_rejections": analysis["input_rejections"],
        "all_phase_terminal_outcomes": dict(Counter(str(e["detail"]["outcome"]) for e in events if e["event"] == "result_taken")),
        "background_before": manifest["background_processes_before"],
        "background_after": manifest["background_processes_after"],
    }
    return record, values, sources


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    args = parser.parse_args()
    records, pooled, counts, source_sets, samples, pairs = {}, {}, {}, [], {}, defaultdict(list)
    for path in sorted(args.directory.glob("*.analysis.json")):
        raw_path = path.with_suffix("").with_suffix(".json")
        record, values, sources = collect(raw_path)
        records[raw_path.stem] = record
        samples[raw_path.stem] = values
        source_sets.append(sources)
        config = record["configuration"]
        # A repetition pairs the two variants, regardless of execution order.
        # Retain both but exclude the pair if either lost window focus.
        pair = config["tool"] + "/" + raw_path.stem.rsplit("_", 1)[-1]
        pairs[pair].append(raw_path.stem)
    if not records:
        parser.error("No captures found")
    for names in pairs.values():
        variants = {records[n]["configuration"]["retirement_variant"] for n in names}
        eligible = (variants == {"deferred_reference", "owner_thread_ack"}
                    and len(names) == 2
                    and all(records[n]["valid"] and records[n]["counts"]["unfocused_frames"] == 0 for n in names))
        for name in names:
            records[name]["primary_pair_eligible"] = eligible
    for name, record in records.items():
        if not record["primary_pair_eligible"]:
            continue
        config = record["configuration"]
        group = config["tool"] + "/" + config["retirement_variant"]
        pooled.setdefault(group, defaultdict(list))
        counts.setdefault(group, Counter())
        for key, items in samples[name].items():
            pooled[group][key].extend(items)
        counts[group].update(record["counts"])
    differing = sorted({key for sources in source_sets for key in sources
                        if any(other.get(key) != sources[key] for other in source_sets)})
    result = {
        "scope": "Current main live dig/fill; identical source with optional old deferred ACK scheduling, then current owner-thread ACK. CPU timestamps; not input-to-display or calibrated GPU timing.",
        "all_valid": all(r["valid"] for r in records.values()),
        "sources_identical_between_runs": not differing,
        "differing_sources": differing,
        "primary_exclusions": {n: "Pair incomplete, invalid, or unfocused during live drag"
                               for n, r in records.items() if not r["primary_pair_eligible"]},
        "sources": source_sets[0],
        "runs": records,
        "pooled_live_drag": {group: {"counts": dict(counts[group]), "ms": {k: stats(v) for k, v in fields.items()}}
                             for group, fields in pooled.items()},
        "limits": [
            "Short captures on one machine; per-run data retained. Pooled percentiles are descriptive, not statistical significance.",
            "One input move per process frame; fixed path/seed/profile, but wall-clock input cadence and evolving simulation state differ.",
            "Reference selects the former unconditional deferred ACK through the test harness only. Both variants use real transport retirement and the same numeric dispatches.",
            "Godot process snapshots cover endpoints only; no continuous system load, temperature or frequency telemetry.",
            "Confirmed retirement can remove avoidable slot waiting; it cannot eliminate GPU execution, CPU command recording or collision update costs.",
        ],
    }
    target = args.directory / "comparison.json"
    target.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({k: result[k] for k in ["all_valid", "sources_identical_between_runs", "pooled_live_drag"]}, ensure_ascii=False))
    print(target.resolve())


if __name__ == "__main__":
    main()
