"""All registered defaults, common candidate spine, and sequential/batch equivalence."""
import argparse
import hashlib
import json
import re
import struct
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
FINAL = ["rock", "sand0", "sand1", "sediment0", "sediment1", "water", "water1", "qx0", "qx1", "qz0", "qz1", "wetness0", "wetness1", "support0", "support1", "compact0", "compact1", "obstacle", "baseline", "coverage", "published", "published_water"]
QUANTITIES = ["outcome", "error_code", "input_revision", "output_revision", "changed_fields", "changed_cells", "touched_cells", "dirty_low", "dirty_high", "added_m3", "removed_m3", "transferred_m3", "left_received_m3", "right_received_m3", "source_m3", "sink_m3", "eps_sand_m3", "eps_transfer_m3", "water_error_m3", "eps_water_m3", "sediment_error_m3", "eps_sediment_m3", "impulse_x_m4_s", "impulse_z_m4_s", "coverage_changed"]


def load(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def field(index, key, channels=1, dtype="<f4"):
    return np.fromfile(index[key]["path"], dtype=dtype).reshape(256, 256, channels).squeeze()


def verify_index(index):
    return all(Path(m["path"]).stat().st_size == m["bytes"] and hashlib.sha256(Path(m["path"]).read_bytes()).hexdigest() == m["sha256"] for m in index.values())


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--run", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise SystemExit("Fresh output required")
    args.output.mkdir(parents=True)
    manifest = load(args.run/"run-manifest.json")
    runs = {r["case"]: r for r in manifest["runs"]}
    sequential = load(Path(runs["all_profiles"]["result"]))
    batched = load(Path(runs["all_profiles_batch"]["result"]))
    checks = []

    def check(name, passed, detail=None):
        checks.append({"name": name, "pass": bool(passed), "detail": detail})

    check("both_actual_gpu_runs_pass", manifest["pass"] and sequential["pass"] and batched["pass"])
    source = {k.replace("\\", "/"): v.lower() for k, v in manifest["sources"].items()}
    catalog = ROOT/"assets/unified_edit/default_catalog.tres"
    catalog_paths = re.findall(r'path="(res://assets/unified_edit/[^"\n]+\.tres)"', catalog.read_text(encoding="utf-8"))
    defaults = {}
    for path in catalog_paths:
        physical = ROOT/path.removeprefix("res://")
        text = physical.read_text(encoding="utf-8")
        check("source_"+physical.stem, hashlib.sha256(physical.read_bytes()).hexdigest() == source[path.removeprefix("res://")])
        profile_id, = re.findall(r'^profile_id = &"([^"]+)"$', text, re.M)
        parameters, = re.findall(r'^defaults = (\{.*\})$', text, re.M)
        def numeric(name, fallback):
            match = re.search(r'^'+name+r' = (\d+)$', text, re.M)
            return int(match.group(1)) if match else fallback
        defaults[profile_id] = {"parameters": json.loads(parameters), "water_policy": numeric("water_policy", 3), "material_policy": numeric("material_policy", 0), "operation": numeric("operation", 0), "destination": numeric("destination", 0)}
    actual = {c["label"]: c for c in sequential["cases"] if not c["mode"]}
    check("all_eleven_actual_catalog_profiles", set(defaults) == set(actual) and len(actual) == 11)
    revision = 0
    for case in sequential["cases"]:
        label, result = case["label"], case["result"]
        check(label+"_all_native_digests", verify_index(case["before"]) and verify_index(case["after"]))
        check(label+"_actual_revision_chain", result["input_revision"] == revision and result["output_revision"] == revision+(result["outcome"] == 1))
        revision = result["output_revision"]
        spine = [m for m in case["trace"]["phases"] if m in [0, 1, 12, 5, 6, 7, 8]]
        check(label+"_same_common_spine", spine == [0, 1, 12, 5, 6, 7, 8])
        check(label+"_successful_terminal", result["outcome"] in [1, 2] and result["error_code"] == 0)
        if case["mode"]:
            continue
        profile, wire = defaults[label], case["wire"]
        check(label+"_default_features", all(wire[key] == profile[key] for key in ["water_policy", "material_policy", "operation", "destination"]))
        check(label+"_default_parameters", all(np.float32(wire[key]) == np.float32(value) for key, value in profile["parameters"].items()))
        check(label+"_public_field_capability", result["changed_fields"] & ~wire["fields"] == 0)
        stages = case["trace"]["water_stages"]
        check(label+"_shared_water_stage_choice", stages == (["prepare", "packed", "displace", "velocity", "velocity_reduce", "audit_blocks", "audit_merge"] if wire["water_policy"] > 0 else []))
        before, after = case["before"], case["after"]
        cells = np.fromfile(after["cells"]["path"], dtype="<u4").reshape(256, 256, 16)
        values = cells.copy().view("<f4")
        valid = np.ones((256, 256), bool)
        if wire["operation"] != 1:
            valid[:] = False;valid[wire["rect_z"]:wire["rect_z"]+wire["rect_h"], wire["rect_x"]:wire["rect_x"]+wire["rect_w"]] = True
        target = "sediment0" if wire["destination"] == 1 else "sand0"
        check(label+"_initialized_candidate_range", np.all(np.isfinite(values[:, :, :15][valid])))
        check(label+"_actual_old_new_target", np.array_equal(values[:, :, 0][valid], field(before, target)[valid]) and np.array_equal(values[:, :, 1][valid], field(after, target)[valid]))
        check(label+"_actual_input_anchor_fields", np.array_equal(values[:, :, 2][valid], field(before, "rock")[valid]) and np.array_equal(values[:, :, 3][valid], field(before, "water")[valid]))
        check(label+"_actual_old_compaction", np.array_equal(values[:, :, 4][valid], field(before, "compact0", dtype="<f2")[valid]))
        check(label+"_actual_new_compaction", np.array_equal(values[:, :, 5][valid], field(after, "compact0", dtype="<f2")[valid]))
        check(label+"_actual_old_material", np.array_equal(values[:, :, 6:8][valid], field(before, "support0", 2)[valid]))
        check(label+"_actual_new_material", np.array_equal(values[:, :, 8:10][valid], field(after, "support0", 2)[valid]))
        if result["outcome"] == 1:
            check(label+"_actual_physical_change", any(before[key]["sha256"] != after[key]["sha256"] for key in ["sand0", "sediment0", "water", "qx0", "qz0", "support0", "compact0"]))
    left, right = sequential["observations"], batched["observations"]
    check("identical_ordered_public_inputs", left["program"] == right["program"])
    check("batch_admitted_before_cpu_consumption", right["recorded_before_consumption"]["active"] > 0 and right["recorded_before_consumption"]["results"] == 0)
    check("same_initial_native_fields", all(sequential["cases"][0]["before"][key]["sha256"] == right["initial"][key]["sha256"] for key in FINAL))
    check("joint_final_digests", verify_index(left["final"]) and verify_index(right["final"]))
    for key in FINAL:
        check("sequential_batch_exact_"+key, left["final"][key]["sha256"] == right["final"][key]["sha256"])
    a, b = left["terminal_results"], right["terminal_results"]
    check("all_seventeen_results_both", len(a) == len(b) == len(left["program"]) == 17 and set(a) == set(b))
    for id in a:
        keys = set(a[id])-{"state_seq", "batch_seq", "slot_id", "lease_id"}
        check("same_public_result_"+id, set(a[id]) == set(b[id]) and all(a[id][key] == b[id][key] for key in keys))
    for name, observation in [("sequential", left), ("batched", right)]:
        control = Path(observation["final"]["control"]["path"]).read_bytes()
        check(name+"_actual_final_version", struct.unpack_from("<q", control, 40)[0] == revision and struct.unpack_from("<q", control, 24)[0] == 0 and struct.unpack_from("<I", control, 4)[0] == 0)
        check(name+"_complete_publication", observation["final"]["sand0"]["sha256"] == observation["final"]["published"]["sha256"] and observation["final"]["water"]["sha256"] == observation["final"]["published_water"]["sha256"])
    report = {"pass": all(c["pass"] for c in checks), "checks": checks, "profiles": defaults, "tool_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), "scope": "Eleven existing catalog defaults, actual initialized common candidates, identical public material/validate/commit/result spine, default water stage, and exact sequential/batched physical/receipt equivalence across 17 commands. Slot/lease/state_seq batching metadata may differ. Full water strategy edge cases, all source writers, cost, consumers and restore remain separate gates."}
    (args.output/"result.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps({"pass": report["pass"], "checks": len(checks), "failures": [c["name"] for c in checks if not c["pass"]]}))
    return 0 if report["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
