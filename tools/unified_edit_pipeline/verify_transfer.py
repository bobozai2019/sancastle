"""Independent capsule/capacity intervals, native conservation and material audit.

The allocation oracle uses float64 monotone sums over individual receivers, not
the GPU's sorted prefix lookup. Physical conservation uses the frozen R32F ULP
formula independently of the (necessarily larger) operator forward intervals.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path

import numpy as np

U = 2**-24
AREA = .015625
FIELDS = ["sand0", "sand1", "support0", "support1", "compact0", "compact1", "coverage", "baseline"]


def raw(index, name, channels=1, dtype="<f4"):
    return np.fromfile(index[name]["path"], dtype=dtype).astype(np.float64).reshape(256, 256, channels).squeeze()


def half_floor(value):
    nearest = value.astype("<f2")
    return np.where(nearest.astype(np.float64) > value, np.nextafter(nearest, np.float16(0)), nearest).astype(np.float64)


def gamma(n):
    return n*U/(1-n*U)


def solve(capacity, weights, target):
    active = (capacity > 0) & (weights > 0)
    if target <= 0 or not np.any(active):
        return 0.0
    capacity, weights = capacity[active], weights[active]
    if math.fsum(capacity) < target:
        return math.inf
    lo, hi = 0.0, float(np.max(capacity/weights))
    for _ in range(100):
        middle = (lo+hi)*.5
        if math.fsum(np.minimum(capacity, middle*weights)) < target:
            lo = middle
        else:
            hi = middle
    return (lo+hi)*.5


def ulps(value):
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
    zz, xx = np.indices((256, 256))
    firsts = {}
    for run in selected:
        result_path = Path(run["result"])
        evidence = json.loads(result_path.read_text(encoding="utf-8-sig"))
        check(run["case"]+"_gpu_pass", run["pass"] and evidence["pass"])
        check(run["case"]+"_result_digest", hashlib.sha256(result_path.read_bytes()).hexdigest() == run["result_sha256"].lower())
        typed = evidence["typed_evidence"]
        check(run["case"]+"_typed_digest", hashlib.sha256(Path(typed["path"]).read_bytes()).hexdigest() == typed["sha256"])
        for case in evidence["cases"]:
            label = run["case"]+"_"+case["label"]
            before, after, wire, result = case["before"], case["after"], case["wire"], case["result"]
            for side, index in [("before", before), ("after", after)]:
                check(label+"_"+side+"_raw_digests", all(Path(meta["path"]).stat().st_size == meta["bytes"] and hashlib.sha256(Path(meta["path"]).read_bytes()).hexdigest() == meta["sha256"] for meta in index.values()))
            for name in FIELDS:
                check(label+"_precommit_"+name, before[name]["sha256"] == after["pre_"+name]["sha256"])
            check(label+"_duals_and_publication", all(after[a]["sha256"] == after[b]["sha256"] for a, b in [("sand0", "sand1"), ("support0", "support1"), ("compact0", "compact1"), ("sand0", "published")]))
            check(label+"_read_only", all(before[name]["sha256"] == after[name]["sha256"] for name in ["water", "rock", "obstacle"]))
            if result["outcome"] == 3:
                check(label+"_atomic_rejection", all(before[name]["sha256"] == after[name]["sha256"] for name in FIELDS))
                continue
            if not wire:
                continue
            check(label+"_transfer_operation", wire["operation"] == 2 and result["ledger"] == 2)
            old, new = raw(before, "sand0"), raw(after, "sand0")
            base, rock = raw(before, "baseline"), raw(before, "rock")
            previous, current = raw(before, "coverage", 2), raw(after, "coverage", 2)
            ax, az, bx, bz = (wire[name] for name in ["start_x", "start_z", "end_x", "end_z"])
            dx, dz = bx-ax, bz-az
            stationary = dx*dx+dz*dz <= 1e-12
            inner, shoulder = wire["trench_width_m"]*.5, wire["shoulder_width_m"]
            if stationary:
                distance = np.full_like(x, math.inf)
            else:
                t = np.clip(((x-ax)*dx+(z-az)*dz)/(dx*dx+dz*dz), 0, 1)
                distance = np.hypot(x-(ax+t*dx), z-(az+t*dz))
            donor = distance < inner
            receiver = (distance >= inner) & (distance < inner+shoulder) & (previous[:, :, 1] == 0) & (raw(before, "obstacle", dtype="u1") == 0)
            signed = (z-az)*dx-(x-ax)*dz
            left, right = receiver & (signed >= 0), receiver & (signed < 0)
            touched = donor | receiver
            check(label+"_independent_participation", int(touched.sum()) == result["touched_cells"])
            check(label+"_zero_source_sink", result["source_m3"] == result["sink_m3"] == 0)
            profile = np.where(donor, np.maximum(0, 1-distance*distance/(inner*inner)), 0)
            target = np.maximum(rock, base-wire["depth_m"]*profile)
            target = np.where(previous[:, :, 1] > 0, np.maximum(rock, np.where(profile <= previous[:, :, 1], previous[:, :, 0], np.minimum(target, previous[:, :, 0]))), target)
            planned = np.minimum(old, np.maximum(0, target-rock))
            cut = np.where(donor, old-planned, 0)
            cap = np.where(receiver, np.maximum(0, base+.5-rock-old), 0)
            weight = np.where(receiver, np.sin(math.pi*(np.where(receiver, distance, inner)-inner)/shoulder), 0)
            # Coordinate/distance arithmetic and a sin forward envelope for
            # the recorded backend. Interval masks are checked separately;
            # fixtures avoid ambiguous footprint boundary classification.
            distance_error = gamma(16)*(np.maximum(np.abs(x), np.abs(z))+max(abs(ax), abs(az), abs(bx), abs(bz))+1)
            profile_error = (2*np.where(donor, distance, 0)*distance_error+distance_error**2)/(inner*inner)+gamma(8)*(1+np.where(donor, distance, 0)**2/(inner*inner))
            cut_error = wire["depth_m"]*profile_error+gamma(8)*(np.abs(base)+np.abs(rock)+np.abs(old)+wire["depth_m"])
            cut_lo, cut_hi = np.where(donor, np.maximum(0, cut-cut_error), 0), np.where(donor, np.minimum(old, cut+cut_error), 0)
            cap_error = gamma(4)*(np.abs(base)+.5+np.abs(rock)+np.abs(old))
            cap_lo, cap_hi = np.where(receiver, np.maximum(0, cap-cap_error), 0), np.where(receiver, cap+cap_error, 0)
            weight_error = math.pi*distance_error/shoulder+gamma(8)*math.pi+4*U
            weight_lo, weight_hi = np.where(receiver, np.maximum(0, weight-weight_error), 0), np.where(receiver, weight+weight_error, 0)
            cut_total_lo, cut_total_hi = math.fsum(cut_lo.ravel()), math.fsum(cut_hi.ravel())
            limit_lo = min(cut_total_lo, wire["transfer_budget_m3"]/AREA, 2*min(math.fsum(cap_lo[left]), math.fsum(cap_lo[right])))
            limit_hi = min(cut_total_hi, wire["transfer_budget_m3"]/AREA, 2*min(math.fsum(cap_hi[left]), math.fsum(cap_hi[right])))
            scale_lo = limit_lo/cut_total_hi if cut_total_hi else 0
            scale_hi = min(1, limit_hi/cut_total_lo) if cut_total_lo else (1 if limit_hi else 0)
            rounding = gamma(4)*(np.abs(old)+cut_hi)
            donor_lo = np.maximum(0, old-cut_hi*scale_hi-rounding).astype("<f4").astype(np.float64)
            donor_hi = np.minimum(old, old-cut_lo*scale_lo+rounding).astype("<f4").astype(np.float64)
            expected_lo, expected_hi = old.copy(), old.copy()
            expected_lo[donor], expected_hi[donor] = donor_lo[donor], donor_hi[donor]
            moved_lo = max(0, math.fsum((old-donor_hi)[donor]))
            moved_hi = max(0, math.fsum((old-donor_lo)[donor]))
            # Reduction roundings in donor totals are distinct from cell-store
            # quantization and from the final frozen physical mass allowance.
            moved_lo = max(0, moved_lo*(1-gamma(10)))
            moved_hi *= 1+gamma(10)
            for mask in [left, right]:
                lambda_lo = solve(cap_hi[mask], weight_hi[mask], moved_lo*.5)
                lambda_hi = solve(cap_lo[mask], weight_lo[mask], moved_hi*.5)
                low_amount = np.minimum(cap_lo[mask], lambda_lo*weight_lo[mask])
                high_amount = cap_hi[mask] if math.isinf(lambda_hi) else np.minimum(cap_hi[mask], lambda_hi*weight_hi[mask])
                # Two frozen residual rounds alter each R32F receiver by at
                # most two total-sand ULPs; include proposal arithmetic too.
                rounding = 2*ulps(old[mask]+high_amount)+gamma(4)*(old[mask]+high_amount)
                expected_lo[mask] = np.maximum(old[mask], old[mask]+low_amount-rounding)
                expected_hi[mask] = old[mask]+high_amount+rounding
            check(label+"_independent_capped_operator", np.all((new >= expected_lo) & (new <= expected_hi)), {"max_interval_width_m": float(np.max(expected_hi-expected_lo))})
            check(label+"_outside_exact", np.array_equal(new[~touched], old[~touched]))
            if case["label"] == "max_repeat":
                native_closure = np.minimum(old.astype("<f4"), np.maximum(np.float32(0), previous[:, :, 0].astype("<f4")-rock.astype("<f4")))
                check(label+"_retained_world_coverage_roundoff", np.array_equal(new[donor], native_closure[donor]),
                      {"changed_donor_cells": int(np.count_nonzero(donor & (new != old))), "removed_m3": float(math.fsum((old-new)[donor])*AREA)})
            delta = new-old
            removed = math.fsum(np.maximum(-delta, 0).ravel())*AREA
            added = math.fsum(np.maximum(delta, 0).ravel())*AREA
            received_left, received_right = math.fsum(np.maximum(delta[left], 0))*AREA, math.fsum(np.maximum(delta[right], 0))*AREA
            net, absolute = math.fsum(delta.ravel())*AREA, math.fsum(np.abs(delta).ravel())*AREA
            eps = max(1e-7, math.fsum(2*ulps(np.maximum(np.abs(old), np.abs(new))[touched]))*AREA+max(1e-8, (8*U+2*(int(touched.sum())+256)*U*U)*absolute))
            check(label+"_frozen_conservation", abs(net) <= 2*eps and abs(removed-received_left-received_right) <= 2*eps and abs(received_left-received_right) <= 2*eps, {"net_m3": net, "eps_base_m3": eps})
            check(label+"_authorization", removed <= wire["transfer_budget_m3"]+eps)
            check(label+"_capacity_and_direction", np.all(delta[donor] <= 0) and np.all(delta[receiver] >= 0) and np.all(delta[receiver] <= cap_hi[receiver]+2*ulps(new[receiver])))
            if result["outcome"] == 1:
                check(label+"_reported_budget", abs(result["eps_sand_m3"]-2*eps) <= max(32*U*eps, 1e-12) and result["eps_transfer_m3"] == result["eps_sand_m3"])
                check(label+"_actual_receipt", all(abs(result[name]-value) <= max(1e-10, gamma(12)*(absolute if name == "sand_error_m3" else abs(value))) for name, value in [("added_m3", added), ("removed_m3", removed), ("transferred_m3", removed), ("left_received_m3", received_left), ("right_received_m3", received_right), ("sand_error_m3", net)]))
            support = raw(before, "support0", 2)
            tag_removed = math.fsum(np.minimum(support[:, :, 0], np.maximum(-delta, 0))[donor])
            moved = removed/AREA
            comp = raw(before, "compact0", dtype="<f2")
            comp_average = math.fsum((np.maximum(-delta, 0)*comp)[donor])/moved if moved else 0
            tag_fraction = tag_removed/moved if moved else 0
            tag = np.clip(np.maximum(support[:, :, 0]-np.maximum(-delta, 0), 0)+np.maximum(delta, 0)*tag_fraction, 0, new)
            tag_error = gamma(20)*(np.abs(support[:, :, 0])+np.abs(delta)+np.abs(tag))+2**-149
            actual_support = raw(after, "support0", 2)
            check(label+"_finite_material_authority", np.all(np.isfinite(actual_support)) and np.all(np.isfinite(new)) and np.all(new >= 0))
            check(label+"_material_tag_transport", np.all(np.abs(actual_support[:, :, 0]-tag) <= tag_error))
            check(label+"_material_reference", np.array_equal(actual_support[:, :, 1], np.where(actual_support[:, :, 0] > 0, new, 0)))
            comp_nominal = np.where(delta > 0, (old*comp+np.maximum(delta, 0)*comp_average)/np.maximum(new, 2**-126), comp)
            comp_error = gamma(20)*(np.abs(comp_nominal)+comp+abs(comp_average))
            comp_lower, comp_upper = half_floor(np.clip(comp_nominal-comp_error, 0, 1)), half_floor(np.clip(comp_nominal+comp_error, 0, 1))
            actual_comp = raw(after, "compact0", dtype="<f2")
            check(label+"_native_material_mix", np.all((actual_comp >= comp_lower) & (actual_comp <= comp_upper)))
            check(label+"_nonreceiver_compact_exact", np.array_equal(actual_comp[~receiver], comp[~receiver]))
            check(label+"_coverage_outside_donors", np.array_equal(previous[~donor], current[~donor]))
            cv_error = wire["depth_m"]*profile_error+gamma(8)*(np.abs(base)+np.abs(rock)+np.abs(new)+1)
            expected_cv_x = np.maximum(target, new+rock)
            expected_cv_y = np.maximum(profile, previous[:, :, 1])
            check(label+"_coverage_committed_actual_bed", np.all(np.abs(current[:, :, 0][donor]-expected_cv_x[donor]) <= cv_error[donor]) and np.all(np.abs(current[:, :, 1][donor]-expected_cv_y[donor]) <= profile_error[donor]))
            changed = (old != new) | (comp != actual_comp) | np.any(support != actual_support, axis=2)
            check(label+"_actual_changed_count", result["changed_cells"] == int(changed.sum()))
            check(label+"_coverage_receipt", bool(result["coverage_changed"]) == bool(np.any(previous != current)))
            expected_fields = (1 if np.any(old != new) else 0) | (4 if np.any(comp != actual_comp) or np.any(support != actual_support) else 0) | (32 if np.any(previous != current) else 0)
            check(label+"_actual_field_mask", result["changed_fields"] == expected_fields)
            dirty = 0
            changed_coordinates = np.argwhere(changed)
            for rz, rx in changed_coordinates:
                for cx in ([rx//32, rx//32-1] if rx % 32 == 0 and rx > 0 else [rx//32]):
                    for cz in ([rz//32, rz//32-1] if rz % 32 == 0 and rz > 0 else [rz//32]):
                        dirty |= 1 << int(cz*8+cx)
            check(label+"_actual_dirty_bits", result["dirty_low"] == dirty & 0xffffffff and result["dirty_high"] == dirty >> 32)
            if len(changed_coordinates):
                rz0, rx0 = changed_coordinates.min(axis=0)
                rz1, rx1 = changed_coordinates.max(axis=0)
                check(label+"_actual_change_bounds", (result["rect_x"], result["rect_z"], result["rect_w"], result["rect_h"]) == (int(rx0), int(rz0), int(rx1-rx0+1), int(rz1-rz0+1)))
            # Supplementary implementation audit: verify sorted tables against
            # their actual initialized candidate inputs. This is separate from
            # the independent geometry/allocation oracle above.
            cells = np.fromfile(after["cells"]["path"], dtype="<u4").reshape(256, 256, 16)
            local = cells[wire["rect_z"]:wire["rect_z"]+wire["rect_h"], wire["rect_x"]:wire["rect_x"]+wire["rect_w"]].reshape(-1, 16)
            rect = np.s_[wire["rect_z"]:wire["rect_z"]+wire["rect_h"], wire["rect_x"]:wire["rect_x"]+wire["rect_w"]]
            check(label+"_independent_directed_side_flags", all(np.array_equal((local[:, 15] & bit) != 0, mask[rect].ravel()) for bit, mask in [(2, donor), (4, left), (8, right)]))
            native = local.copy().view("<f4")
            groups = (len(local)+255)//256
            table = np.fromfile(after["transfer_prefix"]["path"], dtype="<f4").reshape(256, 2, 256, 4)
            prefix_ok, zero_ok = True, True
            for group in range(groups):
                group_cells = local[group*256:(group+1)*256]
                group_native = native[group*256:(group+1)*256]
                for side, bit in [(0, 4), (1, 8)]:
                    ratios = np.full(256, np.finfo(np.float32).max, dtype="<f4")
                    capacities, weights = np.zeros(256, dtype="<f4"), np.zeros(256, dtype="<f4")
                    participating = (group_cells[:, 15] & bit) != 0
                    caps = np.maximum(np.float32(0), (group_native[:, 11]-group_native[:, 2])-group_native[:, 0])
                    active = participating & (caps > 0) & (group_native[:, 12] > 0)
                    active_indices = np.flatnonzero(active)
                    capacities[active_indices], weights[active_indices] = caps[active], group_native[active, 12]
                    ratios[active_indices] = caps[active]/group_native[active, 12]
                    order = np.lexsort((np.arange(256), ratios))
                    cap_prefix = np.array([math.fsum(capacities[order[:j+1]]) for j in range(256)])
                    weight_prefix = np.array([math.fsum(weights[order[:j+1]]) for j in range(256)])
                    actual = table[group, side].astype(np.float64)
                    # Division can lower via reciprocal; validate its native
                    # ratio within two binary32 ULPs, not an arbitrary epsilon.
                    prefix_ok &= (np.all(np.abs(actual[:, 0]-ratios[order].astype(np.float64)) <= 2*ulps(ratios[order].astype(np.float64))) and
                                  np.all(np.abs(actual[:, 1]-cap_prefix) <= gamma(3)*cap_prefix+2**-149) and
                                  np.all(np.abs(actual[:, 2]-weight_prefix) <= gamma(3)*weight_prefix+2**-149))
                    zero_ok &= bool(np.all(actual[:, 3] == 0))
            check(label+"_sorted_native_prefix_inputs", prefix_ok)
            check(label+"_prefix_reserved_zero", zero_ok)
            tx = np.fromfile(after["transfer_state"]["path"], dtype="<f4").astype(np.float64)
            check(label+"_actual_donor_material_summary", abs(tx[4]-moved) <= gamma(12)*moved+1e-12 and abs(tx[5]-tag_removed) <= gamma(12)*tag_removed+1e-12 and abs(tx[6]-comp_average) <= gamma(12)*abs(comp_average)+1e-12)
            if case["label"] == "straight":
                firsts[run["case"]] = case
            np.asarray(expected_lo, dtype="<f4").tofile(args.output/(label+"_reference_lo.bin"))
            np.asarray(expected_hi, dtype="<f4").tofile(args.output/(label+"_reference_hi.bin"))
    if "transfer" in firsts and "transfer_reverse" in firsts:
        # This recorded horizontal fixture has no zero-side shoulder cells.
        # It is a fixture observation, not a general endpoint-invariance rule.
        check("horizontal_fixture_direction_invariance", all(firsts["transfer"]["after"][name]["sha256"] == firsts["transfer_reverse"]["after"][name]["sha256"] for name in FIELDS))
    report = {"pass": all(c["pass"] for c in checks), "selected_cases": [run["case"] for run in selected], "excluded_cases": [run["case"] for run in manifest["runs"] if run not in selected], "checks": checks, "tool_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), "scope": "Dry balanced transfer only. Independent float64 per-receiver monotone allocation intervals, separate frozen R32F mass/side budgets, actual native materials and precommit authority bytes. R16F positive truncation is the previously measured D3D12 device convention, not a cross-backend claim."}
    (args.output/"result.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps({"pass": report["pass"], "checks": len(checks), "failures": [c["name"] for c in checks if not c["pass"]]}))
    return 0 if report["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
