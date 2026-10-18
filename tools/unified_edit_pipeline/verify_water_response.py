"""Native input/commit audit, frozen conservation budgets and original-kernel comparison."""
import argparse
import hashlib
import json
import math
from pathlib import Path

import numpy as np

U, AREA = 2**-24, .015625
PRE = {"sand0": "sand0", "sand1": "sand1", "sediment0": "sediment0", "sediment1": "sediment1", "support0": "support0", "support1": "support1", "compact0": "compact0", "compact1": "compact1", "water0": "water", "water1": "water1", "qx0": "qx0", "qx1": "qx1", "qz0": "qz0", "qz1": "qz1", "baseline": "baseline", "coverage": "coverage"}


def raw(index, key, dtype="<f4", channels=1):
    return np.fromfile(index[key]["path"], dtype=dtype).reshape(256, 256, channels).squeeze()


def digest(index):
    return all(len(Path(m["path"]).read_bytes()) == m["bytes"] and hashlib.sha256(Path(m["path"]).read_bytes()).hexdigest() == m["sha256"] for m in index.values())


def ulp(value):
    return np.where(value < 2**-126, 2**-149, np.exp2(np.floor(np.log2(np.maximum(value, 2**-126)))-23))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--run", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--cases", nargs="+")
    args = parser.parse_args()
    if args.output.exists():
        raise SystemExit("Fresh output required")
    args.output.mkdir(parents=True)
    manifest = json.loads((args.run/"run-manifest.json").read_text(encoding="utf-8-sig"))
    selected = [r for r in manifest["runs"] if args.cases is None or r["case"] in args.cases]
    if not selected or (args.cases is not None and set(args.cases) != {r["case"] for r in selected}):
        raise SystemExit("Requested cases missing")
    checks = []

    def check(name, passed, detail=None):
        checks.append({"name": name, "pass": bool(passed), "detail": detail})

    zz, xx = np.indices((256, 256))
    for run in selected:
        result = Path(run["result"])
        evidence = json.loads(result.read_text(encoding="utf-8-sig"))
        check(run["case"]+"_result_digest", hashlib.sha256(result.read_bytes()).hexdigest() == run["result_sha256"].lower())
        check(run["case"]+"_gpu_pass", run["pass"] and evidence["pass"])
        overflow = evidence["observations"].get("overflow")
        if overflow:
            before, after = overflow["before"], overflow["after"]
            check(run["case"]+"_overflow_digests", digest(before) and digest(after))
            check(run["case"]+"_overflow_atomic", all(before[name]["sha256"] == after[name]["sha256"] for name in PRE.values()))
            control = np.fromfile(after["control"]["path"], dtype="<u4")
            check(run["case"]+"_overflow_actual_fatal", evidence["fault"] == "completion_counter" and control[1] == 32 and control[10] == 0xffffffff and control[11] == 0x7fffffff)
            check(run["case"]+"_overflow_no_completion", not evidence["cases"])
            inputs = np.fromfile(after["water_input"]["path"], dtype="<f4").reshape(-1, 8)
            candidate = np.fromfile(after["water_candidate"]["path"], dtype="<f4").reshape(-1, 4)
            check(run["case"]+"_overflow_water_only_candidate", np.all(np.isfinite(candidate)) and np.array_equal(inputs[:, 0], inputs[:, 1]) and np.array_equal(inputs[:, 2:4], candidate[:, :2]) and np.any(inputs[:, 4:6] != candidate[:, 2:]))
        for case in evidence["cases"]:
            label = run["case"]+"_"+case["label"]
            before, after, wire, receipt = case["before"], case["after"], case["wire"], case["result"]
            check(label+"_native_digests", digest(before) and digest(after))
            for key, physical in PRE.items():
                check(label+"_precommit_"+key, before[physical]["sha256"] == after["pre_"+key]["sha256"])
            if not wire or wire["water_policy"] == 0:
                continue
            if receipt["outcome"] == 3:
                check(label+"_atomic_rejection", all(before[name]["sha256"] == after[name]["sha256"] for name in PRE.values()))
                check(label+"_known_rejection", receipt["error_code"] in (16, 17) and receipt["changed_fields"] == receipt["changed_cells"] == 0)
                status = np.fromfile(after["water_receipt"]["path"], dtype="<u4")
                if receipt["error_code"] == 16:
                    decision = np.fromfile(after["decision"]["path"], dtype="<u4")
                    indirect = np.fromfile(after["water_indirect"]["path"], dtype="<u4")
                    check(label+"_material_before_water", decision[8] == 16 and np.all(status == 0) and np.all(indirect[[0, 3, 6]] == 0))
                else:
                    check(label+"_original_failure_flag", status[0] == 2 and status[1] != 0)
                if evidence["observations"].get("expected_water_failure") == "cfl":
                    check(label+"_actual_cfl_overload", status[1] == 16 and status[31] > 64)
                control = np.fromfile(after["control"]["path"], dtype="<u4")
                check(label+"_business_not_fatal", control[1] == 0)
                continue
            inputs = np.fromfile(after["water_input"]["path"], dtype="<f4").reshape(256, 256, 8)
            candidate = np.fromfile(after["water_candidate"]["path"], dtype="<f4").reshape(256, 256, 4)
            cells = np.fromfile(after["cells"]["path"], dtype="<u4").reshape(256, 256, 16)
            values = cells.copy().view("<f4")
            valid = np.ones((256, 256), bool) if wire["operation"] == 1 else ((xx >= wire["rect_x"]) & (xx < wire["rect_x"]+wire["rect_w"]) & (zz >= wire["rect_z"]) & (zz < wire["rect_z"]+wire["rect_h"]))
            bed_touch = valid & (values[:, :, 12] > 0)
            old_sand, new_sand, rock = raw(before, "sand0"), raw(after, "sand0"), raw(before, "rock")
            expected_new = np.where(bed_touch, values[:, :, 1], old_sand).astype("<f4")
            check(label+"_bed_commit_from_valid_candidate", np.array_equal(new_sand, expected_new))
            check(label+"_full_old_new_bed_input", np.array_equal(inputs[:, :, 0], rock+old_sand) and np.array_equal(inputs[:, :, 1], rock+expected_new))
            old = np.stack([raw(before, name) for name in ["water", "sediment0", "qx0", "qz0"]], axis=2)
            physical = np.stack([raw(after, name) for name in ["water", "sediment0", "qx0", "qz0"]], axis=2)
            check(label+"_full_physical_input", np.array_equal(inputs[:, :, 2:4], old[:, :, :2]) and np.array_equal(inputs[:, :, 4:6], old[:, :, 2:]))
            check(label+"_obstacle_input", np.array_equal(inputs[:, :, 6], raw(before, "obstacle", "u1").astype(np.float32)/255) and np.all(inputs[:, :, 7] == 0))
            check(label+"_finite_nonnegative_candidate", np.all(np.isfinite(candidate)) and np.all(candidate[:, :, :2] >= 0))
            check(label+"_conditional_public_commit", np.array_equal(candidate, physical))
            check(label+"_public_duals", all(after[a]["sha256"] == after[b]["sha256"] for a, b in [("water", "water1"), ("sediment0", "sediment1"), ("qx0", "qx1"), ("qz0", "qz1"), ("sand0", "sand1"), ("compact0", "compact1"), ("support0", "support1")]))
            changed_water = np.any(candidate != old, axis=2)
            touched = (old[:, :, 0] > np.float32(.001)) | changed_water | bed_touch
            count = int(touched.sum())
            delta = candidate.astype(np.float64)-old.astype(np.float64)
            errors, budgets = [], []
            for component, prefix in [(0, "water"), (1, "sediment")]:
                actual = math.fsum(delta[:, :, component].ravel())*AREA
                absolute = math.fsum(np.abs(delta[:, :, component]).ravel())*AREA
                maximum = np.maximum(np.abs(old[:, :, component]), np.abs(candidate[:, :, component])).astype(np.float64)
                epsilon = max(1e-7, math.fsum(2*ulp(maximum[touched]))*AREA+max(1e-8, (8*U+2*(count+256)*U*U)*absolute))
                check(label+"_frozen_"+prefix+"_conservation", abs(actual) <= epsilon, {"actual_error_m3": actual, "budget_m3": epsilon})
                check(label+"_reported_"+prefix+"_budget", abs(receipt["eps_"+prefix+"_m3"]-epsilon) <= max(32*U*epsilon, 1e-12))
                check(label+"_reported_"+prefix+"_error", abs(receipt[prefix+"_error_m3"]-actual) <= max(1e-10, 16*U*absolute))
                errors.append(actual);budgets.append(epsilon)
            material = (raw(before, "compact0", "<f2") != raw(after, "compact0", "<f2")) | np.any(raw(before, "support0", channels=2) != raw(after, "support0", channels=2), axis=2)
            changed = changed_water | material | (old_sand != new_sand)
            check(label+"_actual_union_count", receipt["changed_cells"] == int(changed.sum()) and receipt["touched_cells"] == count)
            fields = (1 if np.any(old_sand != new_sand) else 0) | (4 if np.any(material) else 0) | (8 if np.any(old[:, :, 0] != candidate[:, :, 0]) else 0) | (2 if np.any(old[:, :, 1] != candidate[:, :, 1]) else 0) | (16 if np.any(old[:, :, 2:] != candidate[:, :, 2:]) else 0) | (32 if before["coverage"]["sha256"] != after["coverage"]["sha256"] else 0)
            check(label+"_actual_field_mask", receipt["changed_fields"] == fields)
            dirty = 0
            for z, x in np.argwhere(changed):
                for cx in ([x//32, x//32-1] if x > 0 and x % 32 == 0 else [x//32]):
                    for cz in ([z//32, z//32-1] if z > 0 and z % 32 == 0 else [z//32]):dirty |= 1 << int(cz*8+cx)
            check(label+"_actual_dirty", receipt["dirty_low"] == (dirty & 0xffffffff) and receipt["dirty_high"] == dirty >> 32)
            coords = np.argwhere(changed)
            if len(coords):
                z0, x0 = coords.min(axis=0);z1, x1 = coords.max(axis=0)
                check(label+"_actual_bounds", (receipt["rect_x"], receipt["rect_z"], receipt["rect_w"], receipt["rect_h"]) == (int(x0), int(z0), int(x1-x0+1), int(z1-z0+1)))
            original = case["original_response"]
            check(label+"_original_digests", digest(original))
            reference = np.fromfile(original["candidate"]["path"], dtype="<f4").reshape(256, 256, 4)
            check(label+"_original_exact_depths", np.array_equal(candidate[:, :, :2], reference[:, :, :2]))
            difference = np.abs(candidate[:, :, 2:].astype(np.float64)-reference[:, :, 2:].astype(np.float64))
            # Frozen edit_protocol.gd / protocol_v2.json cell contract.
            bound = np.maximum(2e-7, 16*ulp(np.maximum(np.abs(candidate[:, :, 2:]), np.abs(reference[:, :, 2:])).astype(np.float64))+16*U*difference)
            check(label+"_original_frozen_velocity_cells", np.all(difference <= bound), {"max_error": float(difference.max()), "differing_components": int(np.count_nonzero(difference))})
            actual_receipt = np.fromfile(after["water_receipt"]["path"], dtype="<u4")
            if "capacity" in run["case"] or "sealed" in run["case"]:
                check(label+"_actual_retained_capacity", receipt["retained_water_m3"] > 0)
            if "limited" in run["case"]:
                check(label+"_actual_speed_limiter", actual_receipt[21] > 0)
                speed = np.linalg.norm(candidate[:, :, 2:].astype(np.float64), axis=2)/np.maximum(candidate[:, :, 0], 1e-30)
                check(label+"_limited_speed_bound", np.all(speed[candidate[:, :, 0] > .001] <= 4+2e-6))
            if "many" in run["case"]:
                check(label+"_packed_capacity_fallback", actual_receipt[27] == 0 and np.count_nonzero(np.diff((old[128, :, 0] > .001).astype(int))) > 16)
            if "dry" in run["case"]:
                check(label+"_dry_response_unchanged", np.array_equal(old, physical) and np.all(physical == 0))
            if "plain" in run["case"]:
                check(label+"_unused_material_unchanged", before["support0"]["sha256"] == after["support0"]["sha256"] and before["compact0"]["sha256"] == after["compact0"]["sha256"])
            if "only" in run["case"]:
                check(label+"_momentum_only_revision", fields == 16 and receipt["added_m3"] == receipt["removed_m3"] == 0 and receipt["output_revision"] == receipt["input_revision"]+1)
            original_receipt = np.fromfile(original["receipt"]["path"], dtype="<u4")
            fixed = [i for i in range(32) if i not in [17, 18, 19, 20, 22, 23, 24, 30]]
            check(label+"_original_topology_capacity_cfl", np.array_equal(actual_receipt[fixed], original_receipt[fixed]))
            scratch = np.fromfile(after["water_scratch"]["path"], dtype="<f4").reshape(5, 256, 256)
            for component, key in [(2, "impulse_x_m4_s"), (3, "impulse_z_m4_s")]:
                terms = ((candidate[:, :, component]-scratch[component-2])*np.float32(AREA)).astype(np.float64)
                expected = math.fsum(terms.ravel());absolute = math.fsum(np.abs(terms).ravel())
                check(label+"_actual_"+key, abs(receipt[key]-expected) <= max(1e-10, 16*U*absolute))
    report = {"pass": all(c["pass"] for c in checks), "checks": checks, "selected_cases": [r["case"] for r in selected], "excluded_cases": [r["case"] for r in manifest["runs"] if r not in selected], "tool_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), "scope": "Common edit response: full input, frozen water/sediment conservation, conditional native commit and actual union metadata. Original P08 private numerical reference: H/SED exact; Q within existing 2e-7/16ULP cell budget; nonvelocity topology/capacity/CFL diagnostic words exact. No visible-cost/long-run/restore claim."}
    (args.output/"result.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps({"pass": report["pass"], "checks": len(checks), "failures": [c["name"] for c in checks if not c["pass"]]}))
    return 0 if report["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
