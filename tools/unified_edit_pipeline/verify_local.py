"""Independent float64 local-operator oracle and native storage/accounting audit."""
import argparse
import hashlib
import json
import math
from pathlib import Path

import numpy as np

U = 2**-24
AREA = .015625


def field(index, key, channels=1, dtype="<f4"):
    return np.fromfile(index[key]["path"], dtype=dtype).astype(np.float64).reshape(256, 256, channels).squeeze()


def positive_half_toward_zero(value):
    """Floor nonnegative finite values to binary16 (no arithmetic tolerance)."""
    nearest = value.astype("<f2")
    return np.where(nearest.astype(np.float64) > value,
                    np.nextafter(nearest, np.float16(0)), nearest).astype(np.float64)


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
        result_bytes = Path(run["result"]).read_bytes()
        evidence = json.loads(result_bytes.decode("utf-8-sig"))
        check(run["case"]+"_result_digest", hashlib.sha256(result_bytes).hexdigest().lower() == run["result_sha256"].lower())
        check(run["case"]+"_gpu_run", run["pass"] and evidence["pass"])
        for case in evidence["cases"]:
            label = run["case"]+"_"+case["label"]
            before, after, wire, receipt = case["before"], case["after"], case["wire"], case["result"]
            for name, index in [("before", before), ("after", after)]:
                check(label+"_"+name+"_all_raw_digests", all(Path(meta["path"]).stat().st_size == meta["bytes"] and hashlib.sha256(Path(meta["path"]).read_bytes()).hexdigest() == meta["sha256"] for meta in index.values()))
            for key in ["sand0", "sand1", "support0", "support1", "compact0", "compact1", "baseline", "coverage"]:
                check(label+"_precommit_"+key, before[key]["sha256"] == after["pre_"+key]["sha256"])
            check(label+"_read_only", all(before[key]["sha256"] == after[key]["sha256"] for key in ["rock", "water", "obstacle", "baseline", "coverage"]))
            check(label+"_duals_and_published", all(after[a]["sha256"] == after[b]["sha256"] for a, b in [("sand0", "sand1"), ("compact0", "compact1"), ("support0", "support1"), ("sand0", "published")]))
            if receipt["outcome"] == 3:
                check(label+"_atomic_rejection", all(before[key]["sha256"] == after[key]["sha256"] for key in ["sand0", "sand1", "support0", "support1", "compact0", "compact1"]))
                continue
            if wire["operation"] not in [3, 4]:
                continue
            old, new = field(before, "sand0"), field(after, "sand0")
            compact_before, compact_after = field(before, "compact0", dtype="<f2"), field(after, "compact0", dtype="<f2")
            radius, strength = wire["radius_m"], wire["strength"]
            distance = np.hypot(x-wire["start_x"], z-wire["start_z"])
            touched = distance <= radius
            weights = np.where(touched, np.maximum(.001, 1-distance/radius), 0)
            count = np.count_nonzero(touched)
            check(label+"_touch_count", count == receipt["touched_cells"])
            check(label+"_unchanged_source_sink", receipt["source_m3"] == receipt["sink_m3"] == 0)
            # Six elementary coordinate/distance/weight roundings, including
            # cancellation at the <=16m domain edge. All geometry uses actual
            # wire binary32 values, not the requested double parameters.
            gamma6 = 6*U/(1-6*U)
            weight_error = gamma6*math.sqrt(2)*(np.maximum(np.abs(x), np.abs(z))+max(abs(wire["start_x"]), abs(wire["start_z"]))+1)/radius+U
            if wire["operation"] == 4:
                nominal = np.clip(compact_before+.2*strength*weights, 0, 1)
                arithmetic_error = gamma6*(np.abs(compact_before)+.2*strength*weights)+.2*strength*weight_error
                # First establish the native conversion on a retained-kernel
                # run over isolated input copies. On this D3D12 device R16F
                # image stores truncate positive values. Do not infer this
                # from the new candidate or simply widen to one half ULP.
                legacy = field(before, "legacy_compact", dtype="<f2")
                legacy_cells = np.fromfile(before["legacy_cells"]["path"], dtype="<u4").reshape(256, 256, 16)
                # The retained shader clears only its command rectangle; old
                # flags elsewhere are scratch, not participation in this run.
                zz, xx = np.indices((256, 256))
                in_rect = ((xx >= wire["rect_x"]) & (xx < wire["rect_x"]+wire["rect_w"]) &
                           (zz >= wire["rect_z"]) & (zz < wire["rect_z"]+wire["rect_h"]))
                legacy_touched = (legacy_cells[:, :, 15] == 1) & in_rect
                proposal = legacy_cells[:, :, 1].copy().view("<f4").astype(np.float64)
                check(label+"_retained_kernel_geometry", np.array_equal(legacy_touched, touched))
                check(label+"_retained_kernel_unrounded_operator", np.all(np.abs(proposal[touched]-nominal[touched]) <= arithmetic_error[touched]))
                check(label+"_observed_native_positive_truncation", np.array_equal(legacy[touched], positive_half_toward_zero(proposal)[touched]),
                      {"differs_from_nearest_even_cells": int(np.count_nonzero(touched & (legacy != proposal.astype("<f2").astype(np.float64)))), "scope": "Retained kernel and recorded D3D12 device only"})
                check(label+"_retained_kernel_exact_output", np.array_equal(legacy, compact_after))
                lo = positive_half_toward_zero(np.clip(nominal-arithmetic_error, 0, 1))
                hi = positive_half_toward_zero(np.clip(nominal+arithmetic_error, 0, 1))
                valid = (compact_after >= lo) & (compact_after <= hi)
                check(label+"_native_half_interval", np.all(valid[touched]), {"tie_ambiguous_cells": int(np.count_nonzero(touched & (lo != hi)))})
                check(label+"_outside_exact", np.array_equal(compact_before[~touched], compact_after[~touched]))
                check(label+"_no_sand_or_tag_write", all(before[key]["sha256"] == after[key]["sha256"] for key in ["sand0", "sand1", "support0", "support1"]))
                check(label+"_no_volume_or_error_budget", all(receipt[key] == 0 for key in ["added_m3", "removed_m3", "max_cell_delta_m", "absolute_volume_delta_m3", "sand_error_m3", "eps_sand_m3"]))
                expected_changes = int(np.count_nonzero(compact_before != compact_after))
                check(label+"_actual_native_changes", receipt["changed_cells"] == expected_changes and receipt["changed_fields"] == (4 if expected_changes else 0))
                continue
            weights_sum = math.fsum(weights[touched])
            mean = math.fsum((old*weights)[touched])/weights_sum
            proposed = np.where(touched, old+(mean-old)*strength*weights, old).astype("<f4").astype(np.float64)
            before_sum = math.fsum(old[touched])
            correction = (before_sum-math.fsum(proposed[touched]))/count
            expected = np.where(touched, np.maximum(0, proposed+correction), old).astype("<f4").astype(np.float64)
            # A balanced 256-lane reduction plus compensated block merge has
            # <=gamma(10) positive-sum forward error here. Mean/proposal and
            # uniform-correction errors are propagated separately; this bound
            # is not the physical conservation allowance below.
            gamma10 = 10*U/(1-10*U)
            dw = math.fsum(weight_error[touched])
            denominator = weights_sum-dw
            check(label+"_mean_well_conditioned", denominator > 0)
            mean_error = (2*np.max(np.abs(old[touched]))*dw+gamma10*math.fsum(np.abs(old*weights)[touched]))/denominator+gamma10*abs(mean)
            proposal_error = strength*(weights*mean_error+np.abs(mean-old)*weight_error)+6*U*(np.abs(old)+abs(mean))
            correction_error = float(np.mean(proposal_error[touched]))+gamma10*(before_sum+math.fsum(np.abs(proposed[touched])))/count
            bound = proposal_error+correction_error+2*U*(np.abs(proposed)+abs(correction))
            error = np.abs(new-expected)
            check(label+"_double_operator", np.all(error[touched] <= bound[touched]), {"max_error_m": float(error.max()), "max_forward_bound_m": float(np.max(bound[touched]))})
            check(label+"_outside_exact", np.array_equal(new[~touched], old[~touched]))
            check(label+"_compact_unchanged", before["compact0"]["sha256"] == after["compact0"]["sha256"])
            delta = new-old
            volume = math.fsum(delta.ravel())*AREA
            maximum = np.maximum(np.abs(old), np.abs(new))[touched]
            ulps = np.where(maximum < 2**-126, 2**-149, np.exp2(np.floor(np.log2(np.maximum(maximum, 2**-126)))-23))
            absolute = math.fsum(np.abs(delta).ravel())*AREA
            epsilon = max(1e-7, math.fsum(2*ulps)*AREA+max(1e-8, (8*U+2*(count+256)*U*U)*absolute))
            check(label+"_actual_conservation", abs(volume) <= epsilon and abs(volume)/AREA <= max(1e-5, 2e-6*abs(before_sum)), {"net_m3": volume, "physical_budget_m3": epsilon})
            if receipt["outcome"] == 1:
                check(label+"_independent_reported_budget", abs(receipt["eps_sand_m3"]-epsilon) <= max(16*U*epsilon, 1e-12))
                check(label+"_receipt_from_actual", abs(math.fsum(np.maximum(delta, 0).ravel())*AREA-receipt["added_m3"]) <= epsilon and abs(math.fsum(np.maximum(-delta, 0).ravel())*AREA-receipt["removed_m3"]) <= epsilon)
            old32, new32 = old.astype("<f4"), new.astype("<f4")
            support = field(before, "support0", 2).astype("<f4")
            tag = np.minimum(np.maximum(support[:, :, 0]-np.maximum(old32-new32, np.float32(0)), np.float32(0)), new32)
            check(label+"_tag_top_loss", np.array_equal(field(after, "support0", 2)[:, :, 0], tag))
            check(label+"_material_reference", np.array_equal(field(after, "support0", 2)[:, :, 1], np.where(tag > 0, new32, np.float32(0))))
            np.asarray(expected, dtype="<f4").tofile(args.output/(label+"_reference.bin"))
    report = {"pass": all(c["pass"] for c in checks), "selected_cases": [run["case"] for run in selected], "excluded_cases": [run["case"] for run in manifest["runs"] if run not in selected], "checks": checks, "tool_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), "scope": "Local redistribute/field_adjust only. Independent geometry/rounding forward bound, separate native R32F conservation. R16F positive truncation established from isolated retained-kernel unrounded proposals and output on this D3D12 device, then independently bounded; no cross-device rounding claim."}
    (args.output/"result.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps({"pass": report["pass"], "checks": len(checks)}))
    return 0 if report["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
