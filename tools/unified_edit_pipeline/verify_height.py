"""Independent complete native bed -> 64 physical height maps/version audit."""
import argparse
import hashlib
import json
from pathlib import Path
import statistics

import numpy as np

from verify_water_response import digest, PRE, raw


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--run", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--cases", nargs="+", choices=["height_basic", "height_faults", "height_erosion", "height_flow", "height_batch", "height_coverage", "height_long"], help="Explicit affected subset; omission preserves the established matrix rules")
    args = parser.parse_args()
    if args.output.exists():
        raise SystemExit("Fresh output required")
    args.output.mkdir(parents=True)
    manifest = json.loads((args.run/"run-manifest.json").read_text(encoding="utf-8-sig"))
    checks = []
    metrics = {}

    def check(name, passed, detail=None):
        checks.append({"name": name, "pass": bool(passed), "detail": detail})

    def surface(label, physical, target, require_ack=True):
        data = Path(target["path"]).read_bytes()
        check(label+"_surface_identity", len(data) == target["bytes"] and hashlib.sha256(data).hexdigest() == target["sha256"])
        check(label+"_physical_digests", digest(physical))
        actual = np.frombuffer(data, dtype="<f4").reshape(64, 33, 33)
        bed = raw(physical, "rock")+raw(physical, "sand0")
        for chunk in range(64):
            x = np.minimum(255, chunk % 8*32+np.arange(33))
            z = np.minimum(255, chunk // 8*32+np.arange(33))
            expected = bed[np.ix_(z, x)]
            check(label+f"_native_chunk_{chunk}", np.array_equal(actual[chunk], expected))
        dirty = np.fromfile(physical["height_dirty"]["path"], dtype="<u4")[:256].reshape(64, 4)
        if require_ack:
            check(label+"_dirty_all_acknowledged", np.all(dirty[:, 0] == 0))
        if "publication_stamp" in physical:
            stamp = np.fromfile(physical["publication_stamp"]["path"], dtype="<u4")
            control = np.fromfile(physical["control"]["path"], dtype="<u4")
            check(label+"_actual_complete_publication_stamp", np.array_equal(stamp, control[[2, 3, 4, 5, 10, 11, 6, 7]]))
            check(label+"_complete_water_publication", physical["water"]["sha256"] == physical["published_water"]["sha256"])
        return actual

    def dirty_chunks(before, after):
        changed = raw(before, "sand0") != raw(after, "sand0")
        chunks = set()
        for z, x in np.argwhere(changed):
            for cx in ([x//32-1, x//32] if x > 0 and x % 32 == 0 else [x//32]):
                for cz in ([z//32-1, z//32] if z > 0 and z % 32 == 0 else [z//32]):
                    chunks.add(int(cz*8+cx))
        return chunks, int(changed.sum())

    expected = {"height_basic", "height_faults", "height_erosion", "height_flow", "height_batch"}
    actual = {r["case"] for r in manifest["runs"]}
    check("all_requested_height_cases", actual == set(args.cases) if args.cases else actual in (expected, expected | {"height_coverage", "height_long"}, {"height_flow"}, {"height_batch"}, {"height_coverage"}, {"height_long"}, {"height_coverage", "height_long"}))
    check("source_immutable", not manifest["drift"])
    for run in manifest["runs"]:
        path = Path(run["result"])
        evidence = json.loads(path.read_text())
        label = run["case"]
        check(label+"_result_identity", hashlib.sha256(path.read_bytes()).hexdigest() == run["result_sha256"].lower())
        log = (path.parent/"probe.log").read_text(encoding="utf-8-sig")+(path.parent/"stdout.txt").read_text(encoding="utf-8-sig")
        check(label+"_run_and_resource_cleanup", run["pass"] and evidence["pass"] and "was leaked" not in log and "were leaked" not in log)
        obs = evidence["observations"]
        initial, corner, no_bed = [obs[k] for k in ("initial", "corner", "no_bed")]
        initial_maps = surface(label+"_initial", initial["physical"], initial["surface"])
        corner_maps = surface(label+"_corner", corner["physical"], corner["surface"])
        no_bed_maps = surface(label+"_no_bed", no_bed["physical"], no_bed["surface"])
        dirty, cells = dirty_chunks(initial["physical"], corner["physical"])
        check(label+"_single_grid_corner", cells == 1 and dirty == {27, 28, 35, 36})
        for chunk in range(64):
            check(label+f"_exact_version_{chunk}", corner["surface"]["versions"][str(chunk)] == (2 if chunk in dirty else 0))
            check(label+f"_no_false_rebuild_{chunk}", np.array_equal(initial_maps[chunk], corner_maps[chunk]) == (chunk not in dirty))
        borrowed = np.fromfile(obs["held"]["physical"]["height_dirty"]["path"], dtype="<u4")[:256].reshape(64, 4)
        check(label+"_borrowed_newer_dirty_not_lost", set(np.flatnonzero(borrowed[:, 0] == 2)) == dirty and np.all(borrowed[list(dirty), 1] == 2))
        slots = obs["held"]["height_slots"]
        check(label+"_two_immutable_height_leases", len(slots) == 2 and all(s["phase"] == "read_pending" and s["identity"] for s in slots) and slots[0]["identity"]["snapshot_seq"] != slots[1]["identity"]["snapshot_seq"])
        check(label+"_held_ray_stale", abs(obs["held"]["ray"]-initial["ray"]) < 1e-6)
        bed = raw(corner["physical"], "rock")+raw(corner["physical"], "sand0")
        check(label+"_actual_physics_ray_native_bed", abs(corner["ray"]-float(bed[128, 128])) < 2e-6 and corner["ray"] > initial["ray"]+1)
        check(label+"_nonbed_does_not_rebuild", np.array_equal(corner_maps, no_bed_maps) and no_bed["surface"]["shape_updates"] == corner["surface"]["shape_updates"] and no_bed["surface"]["versions"] == corner["surface"]["versions"])
        for case in evidence["cases"]:
            prefix = label+"_"+case["label"]
            check(prefix+"_raw_identity", digest(case["before"]) and digest(case["after"]))
            check(prefix+"_precommit_authority_readonly", all(case["before"][physical]["sha256"] == case["after"]["pre_"+key]["sha256"] for key, physical in PRE.items()))
        if "recovered" in obs:
            recovered = obs["recovered"]
            surface(label+"_recovered", recovered["physical"], recovered["surface"])
            check(label+"_three_bad_packets_requeued", recovered["invalid_results"] == 3)
            check(label+"_unknown_retained_lease", any(s["phase"] in ("read_unknown", "ack_unknown") and s["identity"] for s in obs["unknown"]["slots"]))
            check(label+"_authority_not_replayed", len(evidence["cases"]) == len({c["result"]["command_id"] for c in evidence["cases"]}) == 9)
            final = raw(recovered["physical"], "sand0")+raw(recovered["physical"], "rock")
            check(label+"_recovered_real_ray", abs(recovered["ray"]-float(final[128, 128])) < 2e-6)
        if "erosion" in obs:
            erosion = obs["erosion"]
            surface(label+"_erosion", erosion["after"], erosion["surface"])
            dirty, cells = dirty_chunks(erosion["before"], erosion["after"])
            check(label+"_actual_coupled_height_change", cells > 0 and erosion["tick"] == 1)
            for chunk in range(64):
                target = erosion["state_seq"] if chunk in dirty else no_bed["surface"]["versions"][str(chunk)]
                check(label+f"_erosion_exact_chunk_version_{chunk}", erosion["surface"]["versions"][str(chunk)] == target)
            check(label+"_actual_tick_versions", all(erosion["surface"]["ticks"][str(chunk)] == 1 and erosion["surface"]["revisions"][str(chunk)] == erosion["revision"] for chunk in dirty))
        if "flow" in obs:
            flow = obs["flow"]
            surface(label+"_flow", flow["after"], flow["surface"])
            control = np.fromfile(flow["gpu_completed"]["control"]["path"], dtype="<u4")
            check(label+"_record_ahead_actual_gpu_state", control[4] == flow["first_state_seq"]+3 == flow["state_seq"] and control[5] == 0 and control[6] == 1 and control[7] == 0 and control.view("<f4")[8] > 0)
            check(label+"_actual_slot_and_queue_bounds", (flow["queue_peak"], flow["work_slots_peak"], flow["height_slots_peak"]) == (64, 3, 2))
            check(label+"_63_ordered_per_command_results", len(flow["results"]) == 63 and [r["command_id"] for r in flow["results"]] == list(range(520, 583)))
            for index, result in enumerate(flow["results"]):
                check(label+f"_actual_batch_tick_{index}", result["outcome"] == 1 and result["state_seq"] == flow["first_state_seq"]+(1 if index < 32 else 3) and result["applied_tick"] == (0 if index < 32 else 1) and result["output_revision"] == result["input_revision"]+1)
            check(label+"_complete_bed_publication", flow["after"]["sand0"]["sha256"] == flow["after"]["published"]["sha256"])
            if "publications_after" in flow:
                check(label+"_one_publication_per_work", flow["publications_after"]-flow["publications_before"] == 3)
            history = obs["result_history"]
            check(label+"_bounded_results_fully_consumed", history["capacity"] == 512 and history["cancelled_and_consumed"] == 513 and history["pending"] == history["reservations"] == flow["final_reservations"] == 0)
            dirty, cells = dirty_chunks(flow["before"], flow["after"])
            check(label+"_flow_real_bed_changes", cells > 0 and all(flow["surface"]["versions"][str(chunk)] == flow["state_seq"] for chunk in dirty))
        if "batch_reject" in obs:
            batch = obs["batch_reject"]
            surface(label+"_batch_reject", batch["after"], batch["surface"], require_ack=False)
            pending = np.fromfile(batch["after"]["height_dirty"]["path"], dtype="<u4")[:256].reshape(64, 4)
            expected_dirty, _ = dirty_chunks(batch["before"], batch["after"])
            check(label+"_batch_actual_pending_dirty", set(np.flatnonzero(pending[:, 0])) == expected_dirty)
            a, b = batch["results"]
            check(label+"_same_batch_reject_successor", a["outcome"] == 3 and a["error_code"] == 9 and b["outcome"] == 1 and a["batch_seq"] == b["batch_seq"] and a["state_seq"] == b["state_seq"] == batch["first_state_seq"]+1 and a["input_revision"] == a["output_revision"] == b["input_revision"] and b["output_revision"] == b["input_revision"]+1 and batch["publications"] == 1)
            difference = raw(batch["after"], "sand0") != raw(batch["before"], "sand0")
            check(label+"_only_valid_successor_wrote", np.count_nonzero(difference) == 1 and difference[128, 160])
            fatal = obs["batch_fatal"]
            check(label+"_fatal_native_digests", digest(fatal["before"]) and digest(fatal["after"]))
            control = np.fromfile(fatal["after"]["control"]["path"], dtype="<u4")
            old_control = np.fromfile(fatal["before"]["control"]["path"], dtype="<u4")
            check(label+"_actual_midbatch_counter_fatal", control[1] == 32 and control[10] == 0xffffffff and control[11] == 0x7fffffff and np.array_equal(control[4:6], old_control[4:6]))
            difference = raw(fatal["after"], "sand0") != raw(fatal["before"], "sand0")
            check(label+"_only_prefatal_command_wrote", np.count_nonzero(difference) == 1 and difference[128, 192])
            for name in ("water", "water1", "sediment0", "sediment1", "qx0", "qx1", "qz0", "qz1", "wetness0", "wetness1", "baseline", "coverage"):
                check(label+"_fatal_unchanged_"+name, fatal["before"][name]["sha256"] == fatal["after"][name]["sha256"])
            for name in ("published", "published_water", "publication_stamp"):
                check(label+"_fatal_keeps_complete_"+name, fatal["before"][name]["sha256"] == fatal["after"][name]["sha256"])
        if "coverage" in obs:
            coverage = obs["coverage"]
            old, dug, late, restored = [coverage[k] for k in ("old", "dug", "late", "restored")]
            for phase, data in (("old", old), ("dug", dug), ("restored", restored)):
                surface(label+"_coverage_"+phase, data["physical"], data["surface"])
            far = next(c for c in evidence["cases"] if c["label"] == "coverage_far_restores")
            wire = far["wire"]
            z, x = np.indices((256, 256))
            latest_rect = (x >= wire["rect_x"]) & (x < wire["rect_x"]+wire["rect_w"]) & (z >= wire["rect_z"]) & (z < wire["rect_z"]+wire["rect_h"])
            before, after = raw(far["before"], "sand0"), raw(far["after"], "sand0")
            changed = before != after
            outside = changed & ~latest_rect
            check(label+"_real_coverage_change_outside_latest_rect", outside.any() and np.any(changed & latest_rect) and np.all(after[outside] > before[outside]), {"changed_cells": int(changed.sum()), "outside_cells": int(outside.sum()), "latest_rect": [wire[k] for k in ("rect_x", "rect_z", "rect_w", "rect_h")]})
            check(label+"_outside_bed_restored_to_old_wall", np.array_equal(after[~latest_rect], raw(old["physical"], "sand0")[~latest_rect]))
            check(label+"_newest_segment_not_stale_shape", far["before"]["sand0"]["sha256"] == dug["physical"]["sand0"]["sha256"])
            dirty, _ = dirty_chunks(far["before"], far["after"])
            pending = np.fromfile(late["physical"]["height_dirty"]["path"], dtype="<u4")[:256].reshape(64, 4)
            check(label+"_actual_coverage_dirty_exact", set(np.flatnonzero(pending[:, 0])) == dirty)
            for chunk in range(64):
                target = coverage["state_seq"] if chunk in dirty else dug["surface"]["versions"][str(chunk)]
                check(label+f"_coverage_final_version_{chunk}", restored["surface"]["versions"][str(chunk)] == target)
            check(label+"_delayed_old_coverage_ray", abs(late["ray"]-dug["ray"]) < 1e-6 and old["ray"]-dug["ray"] > .01)
            actual_bed = raw(restored["physical"], "rock")+raw(restored["physical"], "sand0")
            check(label+"_restored_real_old_coverage_ray", abs(restored["ray"]-float(actual_bed[128, 56])) < 2e-6 and abs(restored["ray"]-old["ray"]) < 1e-6)
            for name in ("coverage_repeat", "coverage_stationary", "coverage_end"):
                case = next(c for c in evidence["cases"] if c["label"] == name)
                check(label+"_coverage_nochange_"+name, case["result"]["outcome"] == 2 and case["before"]["sand0"]["sha256"] == case["after"]["sand0"]["sha256"])
        if "long" in obs:
            long = obs["long"]
            surface(label+"_long", long["after"], long["surface"])
            commands, results, windows = long["commands"], long["results"], long["windows"]
            check(label+"_300_continuous_samples", len(commands) == len(results) == long["sample_count"] == 300 and [c["sample_index"] for c in commands] == list(range(1, 301)))
            check(label+"_one_open_stroke", len({c["stroke_id"] for c in commands}) == len({c["baseline_token"] for c in commands}) == 1)
            check(label+"_default_water_policy_really_used", all(c["features"]["water_policy"] == 3 and r["eps_water_m3"] >= 1e-7 for c, r in zip(commands, results)) and any(r["displaced_water_m3"] > 0 for r in results))
            stroke = np.fromfile(long["before_end"]["stroke"]["path"], dtype="<u4")
            ended = np.fromfile(long["after"]["stroke"]["path"], dtype="<u4")
            check(label+"_actual_gpu_stroke_open_at_sample300", stroke[0] == stroke[8] == 1 and stroke[6] == 300 and stroke[7] == 0 and ended[0] == 0)
            check(label+"_bounded_slots_and_pending", long["queue_peak"] == 26 and long["work_slots_peak"] == 3 and long["height_slots_peak"] == 2 and long["final_reservations"] == 0)
            check(label+"_twelve_open_water_windows", len(windows) == long["tick"] == 12 and all(w["tick_before"] == i and w["tick_after"] == i+1 and w["stroke_still_open"] and w["pending"] == 0 for i, w in enumerate(windows)))
            check(label+"_water_progress_despite_worker_hold", all(w["height_slots"] == 2 for w in windows[:3]) and all(windows[i]["actual_time_s"] > (windows[i-1]["actual_time_s"] if i else 0) for i in range(12)))
            control = np.fromfile(long["before_end"]["control"]["path"], dtype="<u4")
            check(label+"_actual_gpu_open_clock", control[6] == 12 and control[7] == 0 and abs(float(control.view("<f4")[8])-windows[-1]["actual_time_s"]) < 1e-12 and control.view("<f4")[8] > 0)
            record_by_id = {}
            water_records = 0
            for row in long["recorded"]:
                if row["kind"] == 1:
                    water_records += 1
                for command_id in row["ids"]:
                    check(label+f"_recorded_once_{command_id}", command_id not in record_by_id)
                    record_by_id[command_id] = row
            check(label+"_twelve_real_render_tick_recordings", water_records == 12)
            ages, completions = [], []
            for index, (command, result) in enumerate(zip(commands, results)):
                key = str(command["command_id"])
                record = record_by_id[command["command_id"]]
                consumed = long["consumed"][key]
                queued = long["queued_us"][key]
                age = record["record_start_us"]-queued
                latency = consumed["observed_complete_us"]-queued
                ages.append(age);completions.append(latency)
                check(label+f"_long_ordered_result_{index}", result["command_id"] == command["command_id"] and result["sample_index"] == command["sample_index"] and result["outcome"] in (1, 2) and result["error_code"] == 0 and result["applied_tick"] == command["sim_tick"] == index//25+(1 if index % 25 >= 12 else 0) and consumed["state_seq"] == result["state_seq"] and consumed["tick"] == result["applied_tick"])
                check(label+f"_long_actual_queue_causality_{index}", queued <= record["record_start_us"] <= record["record_end_us"] <= consumed["observed_complete_us"])
            events = {}
            for event in long["height_events"]:
                key = event["identity"]["snapshot_seq"]
                events.setdefault(key, {})[event["event"]] = event
            height_delays = []
            for serial, group in events.items():
                check(label+f"_height_final_consumer_{serial}", "request" in group and "capture" in group and "last_consumer" in group)
                if "physics" not in group:
                    continue
                check(label+f"_height_physics_after_capture_{serial}", group["request"]["frame"] <= group["capture"]["frame"] <= group["physics"]["frame"] <= group["last_consumer"]["frame"])
                height_delays.append(group["physics"]["observed_us"]-group["request"]["observed_us"])
            check(label+"_nonempty_height_latency_evidence", len(height_delays) > 4 and min(height_delays) >= 0)
            def summary(values):
                return {"count": len(values), "min_us": min(values), "median_us": statistics.median(values), "max_us": max(values)}
            metrics[label] = {"queue_until_render_record": summary(ages), "enqueue_until_cpu_gpu_completion": summary(completions), "height_request_until_observed_physics": summary(height_delays), "height_latency_scope": "Events carry actual frame IDs; observed_us is first process observation after physics, quantized by process/physics cadence, not a GPU duration or scanout time.", "stroke_elapsed_observed_us": long["open_end_us"]-long["open_start_us"], "actual_advanced_time_s": windows[-1]["actual_time_s"], "p99": "not estimated; not final T08 performance"}
    report = {"pass": all(c["pass"] for c in checks), "checks": checks, "metrics": metrics, "tool_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), "scope": "Only selected candidate height cases: complete native maps/version/ray/dirty, optional cumulative coverage and 300-sample open stroke. CPU boundary timestamps and observed physics latency are functional scheduling evidence, not final FPS/scanout/GPU duration/P99/formal entry/restore claim."}
    (args.output/"result.json").write_text(json.dumps(report, indent=2))
    print(json.dumps({"pass": report["pass"], "checks": len(checks), "failures": [c["name"] for c in checks if not c["pass"]]}))
    return 0 if report["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
