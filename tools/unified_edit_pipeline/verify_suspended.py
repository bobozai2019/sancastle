"""Independent wet-mask/addition oracle and retained coupled-kernel byte audit."""
import argparse
import hashlib
import json
import math
import struct
from pathlib import Path

import numpy as np

U, AREA = 2**-24, .015625
AUTHORITY = ["sand0", "sand1", "sediment0", "sediment1", "support0", "support1", "compact0", "compact1", "baseline", "coverage"]


def field(index, key, dtype="<f4", channels=1):
    return np.fromfile(index[key]["path"], dtype=dtype).astype(np.float64).reshape(256, 256, channels).squeeze()


def valid_index(index):
    return all(Path(meta["path"]).stat().st_size == meta["bytes"] and hashlib.sha256(Path(meta["path"]).read_bytes()).hexdigest() == meta["sha256"] for meta in index.values())


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
    selected = [run for run in manifest["runs"] if args.cases is None or run["case"] in args.cases]
    if not selected or (args.cases is not None and set(args.cases) != {run["case"] for run in selected}):
        raise SystemExit("Requested cases missing")
    checks = []

    def check(name, passed, detail=None):
        checks.append({"name": name, "pass": bool(passed), "detail": detail})

    axis = (np.arange(256)+.5-128)*.125
    x, z = np.meshgrid(axis, axis)
    for run in selected:
        evidence = json.loads(Path(run["result"]).read_text(encoding="utf-8-sig"))
        check(run["case"]+"_gpu_pass", run["pass"] and evidence["pass"])
        check(run["case"]+"_result_digest", hashlib.sha256(Path(run["result"]).read_bytes()).hexdigest() == run["result_sha256"].lower())
        check(run["case"]+"_typed_digest", hashlib.sha256(Path(evidence["typed_evidence"]["path"]).read_bytes()).hexdigest() == evidence["typed_evidence"]["sha256"])
        for case in evidence["cases"]:
            label = run["case"]+"_"+case["label"]
            before, after, w, result = case["before"], case["after"], case["wire"], case["result"]
            check(label+"_all_native_digests", valid_index(before) and valid_index(after))
            for key in AUTHORITY:
                check(label+"_precommit_"+key, before[key]["sha256"] == after["pre_"+key]["sha256"])
            suspended = w["destination"] == 1
            nominal = float(np.float32(np.float32(w["amount_m3"])*np.float32(w["strength"])))
            check(label+"_nominal_ledger", np.float32(result["source_m3"]) == np.float32(nominal) and result["sink_m3"] == 0)
            if suspended:
                check(label+"_read_only", all(before[key]["sha256"] == after[key]["sha256"] for key in ["sand0", "sand1", "support0", "support1", "compact0", "compact1", "water", "water1", "wetness0", "wetness1", "qx0", "qx1", "qz0", "qz1", "rock", "obstacle", "baseline", "coverage", "flux0", "flux1"]))
            else:
                check(label+"_suspended_unchanged", before["sediment0"]["sha256"] == after["sediment0"]["sha256"] and before["sediment1"]["sha256"] == after["sediment1"]["sha256"])
            if result["outcome"] == 3:
                check(label+"_atomic_rejection", all(before[key]["sha256"] == after[key]["sha256"] for key in AUTHORITY))
                continue
            if not suspended:
                continue
            old, new = field(before, "sediment0"), field(after, "sediment0")
            check(label+"_sediment_twins", after["sediment0"]["sha256"] == after["sediment1"]["sha256"])
            # JSON numbers are narrowed back to the actual wire binary32. This
            # matters at exact h==dry_depth; decimal text is not the GPU value.
            wire = {key: float(np.float32(w[key])) for key in ["start_x", "start_z", "end_x", "end_z", "radius_m", "dry_depth_m"]}
            dx, dz = wire["end_x"]-wire["start_x"], wire["end_z"]-wire["start_z"]
            length_squared = dx*dx+dz*dz
            t = np.clip(((x-wire["start_x"])*dx+(z-wire["start_z"])*dz)/length_squared, 0, 1) if length_squared > 1e-6 else np.zeros_like(x)
            distance = np.hypot(x-wire["start_x"]-t*dx, z-wire["start_z"]-t*dz)
            eligible = (distance <= wire["radius_m"]) & (field(before, "water") > wire["dry_depth_m"]) & (field(before, "obstacle", dtype="u1") < 128)
            weights = np.where(eligible, np.maximum(.001, 1-distance/wire["radius_m"]), 0)
            count = int(eligible.sum())
            check(label+"_independent_wet_touch_count", count == result["touched_cells"])
            expected = np.asarray(old+nominal*weights/math.fsum(weights.ravel())/AREA, dtype="<f4").astype(np.float64)
            # Positive weighted-addition sensitivity to independent geometry,
            # the balanced reduction and final binary32 arithmetic.
            gamma16 = 16*U/(1-16*U)
            dw = gamma16*(np.maximum(np.abs(x), np.abs(z))+max(abs(v) for k, v in wire.items() if k.startswith("start") or k.startswith("end"))+1)/wire["radius_m"]
            total, error_total = math.fsum(weights.ravel()), math.fsum(dw[eligible])
            check(label+"_well_conditioned_weights", total > error_total)
            amount_error = nominal/AREA*((dw+weights*error_total/total)/(total-error_total)+gamma16*weights/total)
            bound = amount_error+gamma16*(np.abs(old)+np.abs(expected-old))
            check(label+"_independent_volume_operator", np.all(np.abs(new[eligible]-expected[eligible]) <= bound[eligible]), {"max_error_m": float(np.max(np.abs(new-expected))), "max_forward_bound_m": float(np.max(bound[eligible]))})
            check(label+"_dry_blocked_outside_exact", np.array_equal(old[~eligible], new[~eligible]))
            delta = new-old
            actual = math.fsum(delta.ravel())*AREA
            absolute = math.fsum(np.abs(delta).ravel())*AREA
            epsilon = max(1e-7, math.fsum(2*ulp(np.maximum(np.abs(old), np.abs(new))[eligible]))*AREA+max(1e-8, (4*U+2*count*U*U)*absolute))
            check(label+"_frozen_physical_budget", abs(actual-nominal) <= epsilon)
            changed = int(np.count_nonzero(delta))
            check(label+"_actual_field_and_changes", result["changed_fields"] == (2 if changed else 0) and result["changed_cells"] == changed)
            if result["outcome"] == 1:
                check(label+"_reported_budget", abs(result["eps_sand_m3"]-epsilon) <= max(16*U*epsilon, 1e-12) and result["eps_sediment_m3"] == result["eps_sand_m3"])
                check(label+"_actual_quantities", abs(result["added_m3"]-actual) <= max(1e-10, 16*U*abs(actual)) and result["removed_m3"] == 0 and abs(result["sediment_error_m3"]-(actual-nominal)) <= max(1e-10, 16*U*abs(actual)))
            np.asarray(expected, dtype="<f4").tofile(args.output/(label+"_reference.bin"))
        observation = evidence["observations"].get("coupled")
        if observation:
            label = run["case"]
            before, after, reference = observation["before"], observation["after"], observation["reference"]
            check(label+"_native_digests", valid_index(before) and valid_index(after) and valid_index(reference))
            decision = bytes.fromhex(observation["decision_hex"])
            steps, actual_dt = struct.unpack_from("<I", decision, 4)[0], struct.unpack_from("<f", decision, 12)[0]
            check(label+"_actual_gpu_substeps", steps == min(64, int(label.split("_")[1])))
            check(label+"_actual_completed_clock", observation["tick"] == 1 and observation["revision"] == steps and abs(observation["actual_time_s"]-actual_dt) <= U*actual_dt)
            mapping = {"sand": "sand0", "sediment": "sediment0", "water": "water", "qx": "qx0", "qz": "qz0", "wetness": "wetness0", "compact": "compact0", "support": "support0", "flux": "flux0"}
            for key, actual_key in mapping.items():
                check(label+"_retained_exact_"+key, reference[key]["sha256"] == after[actual_key]["sha256"])
            for key in ["sand0", "sediment0", "water", "qx0", "qz0", "compact0", "wetness0"]:
                value = field(after, key, dtype="<f2" if key in ["compact0", "wetness0"] else "<f4")
                check(label+"_finite_"+key, np.all(np.isfinite(value)))
                if key not in ["qx0", "qz0"]:check(label+"_nonnegative_"+key, np.all(value >= 0))
            total_before = math.fsum((field(before, "sand0")+field(before, "sediment0")).ravel())*AREA
            total_after = math.fsum((field(after, "sand0")+field(after, "sediment0")).ravel())*AREA
            dt = struct.unpack_from("<f", decision, 8)[0]
            check(label+"_coupled_actual_advancement", (before["wetness0"]["sha256"] != after["wetness0"]["sha256"] or dt*1.5 < 2**-14) and before["sediment0"]["sha256"] != after["sediment0"]["sha256"], {"total_sand_before_m3": total_before, "total_sand_after_m3": total_after, "measured_drift_m3": total_after-total_before, "wetness_changed": before["wetness0"]["sha256"] != after["wetness0"]["sha256"], "wetness_increment_before_R16_store": dt*1.5, "initial_wetness_R16_quantum": 2**-14, "scope": "Measured diagnostic; full coupled conservation/long-run gate remains T04/T08, not inferred solely from endpoint sums. R16F may swallow each tiny substep even while dt accumulates."})
    report = {"pass": all(c["pass"] for c in checks), "selected_cases": [r["case"] for r in selected], "excluded_cases": [r["case"] for r in manifest["runs"] if r not in selected], "checks": checks, "tool_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), "scope": "Suspended disk/sweep wet admission, private candidate/conditional sediment commit and original R32F volume budget. Coupled substeps compare nine native fields to retained legacy binding/recorder on an isolated copy; no full water-policy/restore/cost/long-stability claim."}
    (args.output/"result.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps({"pass": report["pass"], "checks": len(checks), "failures": [c["name"] for c in checks if not c["pass"]]}))
    return 0 if report["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
