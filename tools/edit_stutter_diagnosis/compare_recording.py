"""Compare saved recorder/height-budget captures without averaging percentiles.

The cache-only dig capture is a single-factor comparison. Combined captures
retain all source/configuration differences, including unrelated workspace work.
"""
import argparse
from collections import Counter, defaultdict
import hashlib
import json
from pathlib import Path

from compare_retirement import collect, read
from analyze_shovel_latency import interval_overlap_query, stats


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    args = parser.parse_args()
    directory = args.directory.resolve()
    names = ["dig_before_01", "fill_before_01", "dig_cached_only_01"]
    names += sorted(p.stem for p in directory.glob("*_combined_*.json")
                    if p.stem.rsplit("_", 1)[-1].isdigit())
    records, sources, samples, environments = {}, {}, {}, {}
    for name in names:
        path = directory / (name + ".json")
        record, values, source_set = collect(path)
        raw = read(path)
        analysis = read(path.with_suffix(".analysis.json"))
        overlap = interval_overlap_query(
            (c["start_us"], c["start_us"] + c["elapsed_us"])
            for c in raw["observations"]["collision_calls"])
        values["shape_cpu_per_frame_overlap"] = [
            overlap(f["at_us"] - f["frame_us"], f["at_us"]) / 1000
            for f in raw["frames"] if f["phase"] == "playing_drag" and f["frame_us"] > 0]
        record["ms"] = {k: stats(v) for k, v in values.items()}
        record["eligible"] = record["valid"] and record["counts"]["unfocused_frames"] == 0
        record["all_phase_height_budget_observed"] = {
            "max_frame_shape_calls": max(
                (e["detail"].get("frame_apply_count", 0)
                 for e in raw["observations"]["timeline"]["events"]
                 if e["event"] == "height_apply_end"), default=0),
            "max_frame_shape_usec": max(
                (e["detail"].get("frame_apply_usec", 0)
                 for e in raw["observations"]["timeline"]["events"]
                 if e["event"] == "height_apply_end"), default=0),
        }
        record["height_application"] = {
            key: value for key, value in analysis["phase_ms"]["playing_drag"].items()
            if key.startswith("height_")}
        records[name], sources[name], samples[name] = record, source_set, values
        environments[name] = raw["runtime"]["configuration"]["environment"]

    pooled, counts = {}, {}
    for name, record in records.items():
        if not record["eligible"]:
            continue
        variant = "combined" if "_combined_" in name else (
            "cache_only" if "_cached_only_" in name else "before")
        group = name.split("_")[0] + "/" + variant
        pooled.setdefault(group, defaultdict(list))
        counts.setdefault(group, Counter()).update(record["counts"])
        for key, items in samples[name].items():
            pooled[group][key].extend(items)

    baseline = sources["dig_before_01"]
    differences = {
        name: {p: {"before": baseline.get(p), "run": source_set.get(p)}
               for p in sorted(set(baseline) | set(source_set))
               if baseline.get(p) != source_set.get(p)}
        for name, source_set in sources.items()}
    expected_cache_change = {
        "res://scripts/simulation/unified_edit/water.gd",
        "res://scripts/simulation/unified_edit/coupled.gd"}
    cache_controlled = (
        set(differences["dig_cached_only_01"]) == expected_cache_change
        and environments["dig_before_01"] == environments["dig_cached_only_01"]
        and records["dig_before_01"]["eligible"]
        and records["dig_cached_only_01"]["eligible"])
    project = Path(__file__).resolve().parents[2]
    latest = sources[names[-1]]
    current_drift = []
    for path, expected in latest.items():
        local = project / path.removeprefix("res://")
        if not local.is_file() or hashlib.sha256(local.read_bytes()).hexdigest() != expected:
            current_drift.append(path)
    report = {
        "scope": "Visible current main, wet dig/fill, 1280x720, seed 101, full current load. CPU wall-clock spans, not calibrated GPU execution or input-to-display latency.",
        "all_captures_valid_foreground": all(r["eligible"] for r in records.values()),
        "cache_only_single_factor_sources_confirmed": cache_controlled,
        "source_differences_from_before": differences,
        "effective_environments": environments,
        "source_drift_since_last_capture": current_drift,
        "runs": records,
        "pooled_live_drag": {
            group: {"counts": dict(counts[group]), "ms": {k: stats(v) for k, v in fields.items()}}
            for group, fields in pooled.items()},
        "excluded_experiments": {
            "dig_batch_only_01": "Merged compute lists with explicit barriers did not improve recorder CPU time; implementation reverted before the cached recorder.",
            "batched_smoke": "Initial merged-list experiment had validation errors; retained as failed evidence.",
        },
        "limits": [
            "One before capture and two combined captures per tool; descriptive short windows on one machine, not significance or long-run stability.",
            "Cache-only dig changes exactly the two recorder sources. Combined runs also contain separate numerics-selection work; effective solver remains rusanov_first_order_v1. Combined differences are not a strict single-factor causal estimate.",
            "Each input move occurs once per rendered frame. Fixed path/profile/seed does not imply identical wall-clock input cadence or evolving simulation state.",
            "Collision budget is per height owner and rendered frame: at most 8 calls, stop after 1500us measured shape-call CPU. An atomic native call can overrun. Worker preparation and other physics work are outside this soft budget.",
            "Frame intervals include VSync/presentation and work outside the measured sections. Reduced CPU cost alone does not establish smoother whole-frame delivery.",
            "Godot process snapshots cover endpoints, not continuous background load, CPU frequency or temperature.",
        ],
    }
    output = directory / "comparison.json"
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({
        "valid_foreground": report["all_captures_valid_foreground"],
        "cache_only_controlled": cache_controlled,
        "current_drift": current_drift,
        "groups": report["pooled_live_drag"],
    }, ensure_ascii=False))
    print(output)


if __name__ == "__main__":
    main()
