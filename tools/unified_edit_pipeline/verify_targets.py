"""Independent float64 geometry, actual R32F accounting and precommit oracle."""
import argparse
import hashlib
import json
import math
import struct
from pathlib import Path

import numpy as np

U = 2**-24
AREA = 0.015625
ROOT = Path(__file__).resolve().parents[2]
FIELDS = ["sand0", "sand1", "support0", "support1", "compact0", "compact1"]


def raw(index, key, channels=1, dtype="<f4"):
    return np.fromfile(index[key]["path"], dtype=dtype).astype(np.float64).reshape(256, 256, channels).squeeze()


def capsule(x, z, ax, az, bx, bz):
    dx, dz = bx-ax, bz-az
    length = math.hypot(dx, dz)
    if length <= 1e-6:
        return np.full_like(x, np.inf)
    along = ((x-ax)*dx+(z-az)*dz)/length
    perpendicular = np.abs((x-ax)*dz-(z-az)*dx)/length
    return np.where(along < 0, np.hypot(x-ax, z-az), np.where(along > length, np.hypot(x-bx, z-bz), perpendicular))


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

    def check(name, value, detail=None):
        checks.append({"name": name, "pass": bool(value), "detail": detail})

    template = np.fromfile(ROOT/"assets/brushes/castle/four_towers_v1.rgba32f", dtype="<f4").astype(np.float64).reshape(65, 65, 4)
    gradient = max(np.abs(np.diff(template[:, :, 0], axis=0)).max(), np.abs(np.diff(template[:, :, 0], axis=1)).max())/.0625
    axis = (np.arange(256)+.5-128)*.125
    x, z = np.meshgrid(axis, axis)
    seen = set()
    for run in selected:
        evidence = json.loads(Path(run["result"]).read_text(encoding="utf-8-sig"))
        check(run["case"]+"_selected_run_pass", run["pass"] and evidence["pass"])
        typed = evidence["typed_evidence"]
        check(run["case"]+"_typed_digest", hashlib.sha256(Path(typed["path"]).read_bytes()).hexdigest() == typed["sha256"])
        for case in evidence["cases"]:
            label = run["case"]+"_"+case["label"]
            before, after, result, wire = case["before"], case["after"], case["result"], case["wire"]
            for index in [before, after]:
                for field, entry in index.items():
                    if entry["path"] in seen:
                        continue
                    seen.add(entry["path"])
                    data = Path(entry["path"]).read_bytes()
                    check(label+"_digest_"+field, len(data) == entry["bytes"] and hashlib.sha256(data).hexdigest() == entry["sha256"])
            for field in FIELDS+["baseline", "coverage"]:
                check(label+"_precommit_"+field, before[field]["sha256"] == after["pre_"+field]["sha256"])
            for field in ["rock", "water", "obstacle"]:
                check(label+"_readonly_"+field, before[field]["sha256"] == after[field]["sha256"])
            check(label+"_duals", all(after[a]["sha256"] == after[b]["sha256"] for a, b in [("sand0", "sand1"), ("support0", "support1"), ("compact0", "compact1"), ("sand0", "published")]))
            if result["outcome"] == 3:
                check(label+"_rejected_atomic", all(before[field]["sha256"] == after[field]["sha256"] for field in FIELDS+["baseline", "coverage", "published"]))
                check(label+"_rejected_amounts", result["added_m3"] == result["removed_m3"] == 0)
                continue
            old, new, rock = raw(before, "sand0"), raw(after, "sand0"), raw(before, "rock")
            if case["mode"]:
                check(label+"_control_authority", all(before[field]["sha256"] == after[field]["sha256"] for field in FIELDS))
                if case["mode"] == "begin":
                    expected_base = (old.astype("<f4")+rock.astype("<f4")).astype(np.float64)
                    check(label+"_new_actual_baseline", np.array_equal(raw(after, "baseline"), expected_base))
                    check(label+"_clear_coverage", not raw(after, "coverage", 2).any())
                else:
                    check(label+"_end_retains_scratch", before["baseline"]["sha256"] == after["baseline"]["sha256"] and before["coverage"]["sha256"] == after["coverage"]["sha256"])
                continue
            if wire["operation"] != 1:
                continue  # Ordinary dig is independently covered by G2.
            previous = raw(before, "coverage", 2)
            target = old+rock
            expected_cv = previous.copy()
            if wire["shape"] == 2:
                yaw, scale, height = map(lambda a: float(np.float32(a)), (wire["yaw_rad"], wire["scale_xz"], wire["height_m"]))
                dx, dz = x-wire["start_x"], z-wire["start_z"]
                lx, lz = (math.cos(yaw)*dx+math.sin(yaw)*dz)/scale, (-math.sin(yaw)*dx+math.cos(yaw)*dz)/scale
                ux, uz = np.clip((lx+2)*16, 0, 64), np.clip((lz+2)*16, 0, 64)
                ix, iz = np.floor(ux).astype(int), np.floor(uz).astype(int)
                jx, jz = np.minimum(ix+1, 64), np.minimum(iz+1, 64)
                tx, tz = ux-ix, uz-iz
                h = ((template[iz, ix, 0]*(1-tx)+template[iz, jx, 0]*tx)*(1-tz)+(template[jz, ix, 0]*(1-tx)+template[jz, jx, 0]*tx)*tz)*height+wire["datum_y_m"]
                nx, nz = np.floor(ux+.5).astype(int), np.floor(uz+.5).astype(int)
                touched = (np.abs(lx) <= 2) & (np.abs(lz) <= 2) & (template[nz, nx, 1] >= .5) & (raw(before, "obstacle", dtype="u1") <= 0)
                target = np.where(touched, h, target)
                bound = 8*U*(np.maximum(1, np.abs(old))+np.abs(rock)+height)+32*U*16*gradient*height/scale
            else:
                distance = capsule(x, z, wire["start_x"], wire["start_z"], wire["end_x"], wire["end_z"])
                inner, outer = wire["top_width_m"]/2, wire["bottom_width_m"]/2
                section = np.where(distance <= inner, 1, np.clip((outer-distance)/max(outer-inner, 1e-8), 0, 1))
                hit = section > 0
                moving = math.hypot(wire["end_x"]-wire["start_x"], wire["end_z"]-wire["start_z"]) > 1e-6
                touched = (hit | (previous[:, :, 1] > 0)) & moving
                target = np.where(hit, raw(before, "baseline")+wire["height_m"]*section, previous[:, :, 0])
                target = np.where(previous[:, :, 1] > 0, np.maximum(target, previous[:, :, 0]), target)
                bound = 8*U*(np.maximum(1, np.abs(old))+np.abs(rock)+wire["height_m"])+32*U*16*wire["height_m"]/max(outer-inner, 1e-8)
            expected = np.where(touched, np.maximum(old, target-rock), old)
            expected_cv[:, :, 0] = np.where(touched, target, previous[:, :, 0])
            expected_cv[:, :, 1] = np.where(touched, 1, previous[:, :, 1])
            error = np.abs(new-expected)
            check(label+"_float64_geometry", np.all(error <= bound), {"max_error_m": float(error.max()), "max_bound_m": float(np.max(bound))})
            check(label+"_outside_exact", np.array_equal(new[~touched], old[~touched]))
            check(label+"_coverage_mask", np.array_equal(raw(after, "coverage", 2)[:, :, 1], expected_cv[:, :, 1]))
            check(label+"_coverage_height", np.all(np.abs(raw(after, "coverage", 2)[:, :, 0]-expected_cv[:, :, 0]) <= bound))
            check(label+"_baseline_fixed", before["baseline"]["sha256"] == after["baseline"]["sha256"])
            delta = new-old
            volume = math.fsum(delta.ravel())*AREA
            if result["outcome"] == 1:
                maximum = np.maximum(np.abs(old), np.abs(new))[touched]
                exponents = np.floor(np.log2(np.maximum(maximum, np.float64(2**-126))))-23
                ulps = np.where(maximum < 2**-126, 2**-149, np.exp2(exponents))
                quant = math.fsum(2*ulps)*AREA
                absolute = math.fsum(np.abs(delta).ravel())*AREA
                epsilon = max(1e-7, quant+max(1e-8, (8*U+2*(np.count_nonzero(touched)+256)*U*U)*absolute))
                check(label+"_independent_budget", abs(result["eps_sand_m3"]-epsilon) <= max(16*U*epsilon, 1e-12), {"reference": epsilon, "reported": result["eps_sand_m3"]})
                check(label+"_actual_volume", abs(volume-result["added_m3"]) <= epsilon)
                check(label+"_exact_external_source", result["source_m3"] == result["added_m3"] and result["sink_m3"] == 0)
            else:
                check(label+"_nochange_authority", np.array_equal(old, new) and result["source_m3"] == result["sink_m3"] == 0)
            old32, new32 = old.astype("<f4"), new.astype("<f4")
            support = raw(before, "support0", 2).astype("<f4")
            tag = np.maximum(support[:, :, 0]-np.maximum(old32-new32, np.float32(0)), np.float32(0))
            if wire["material_policy"] == 1:
                tag = tag+np.maximum(new32-old32, np.float32(0))
            tag = np.minimum(np.maximum(tag, np.float32(0)), new32)
            check(label+"_material_tag", np.array_equal(raw(after, "support0", 2)[:, :, 0], tag))
            check(label+"_material_reference", np.array_equal(raw(after, "support0", 2)[:, :, 1], np.where(tag > 0, new32, np.float32(0))))
            expected_compact = raw(before, "compact0", dtype="<f2")
            if wire["material_policy"] == 1:
                expected_compact = np.where(new > old, np.maximum(expected_compact, .9501953125), expected_compact)
            check(label+"_stored_half_compaction", np.array_equal(raw(after, "compact0", dtype="<f2"), expected_compact))
            np.asarray(expected, dtype="<f4").tofile(args.output/(label+"_reference.bin"))
        for label, index in evidence.get("observations", {}).items():
            for field, entry in index.items():
                payload = Path(entry["path"]).read_bytes()
                check(run["case"]+"_observation_digest_"+label+"_"+field, len(payload) == entry["bytes"] and hashlib.sha256(payload).hexdigest() == entry["sha256"])
            stroke = Path(index["stroke"]["path"]).read_bytes()
            control = Path(index["control"]["path"]).read_bytes()
            check(run["case"]+"_observation_generation_"+label, struct.unpack_from("<q", control, 8)[0] == 9007199254740993 and struct.unpack_from("<I", control, 4)[0] == 0)
            if label == "long_stroke":
                check("long_stroke_int64_and_sample", struct.unpack_from("<q", stroke, 8)[0] == 9007199254740994 and struct.unpack_from("<q", stroke, 16)[0] == 9007199254742004 and struct.unpack_from("<q", stroke, 24)[0] == 303)
            if label == "control_barrier":
                check("future_control_barrier_gpu_state", struct.unpack_from("<q", control, 24)[0] == 2 and struct.unpack_from("<I", stroke, 0)[0] == 0)
    report = {"pass": all(c["pass"] for c in checks), "selected_cases": [run["case"] for run in selected], "excluded_cases": [run["case"] for run in manifest["runs"] if run not in selected], "checks": checks, "tool_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), "scope": "Only explicitly selected cases. Independent double geometry, native-byte authority boundary and actual R32F/half accounting; no full water or cost claim."}
    (args.output/"result.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps({"pass": report["pass"], "checks": len(checks)}))
    return 0 if report["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
