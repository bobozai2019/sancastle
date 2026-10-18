"""Native complete-view copies, independent footprint queries and real pixels."""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image

from verify_water_response import digest, PRE, raw

ROOT = Path(__file__).resolve().parents[2]
COPY = {"rock": "rock", "obstacle": "obstacle", "sand": "sand0", "water": "water", "sediment": "sediment0", "momentum_x": "qx0", "momentum_z": "qz0", "wetness": "wetness0", "compaction": "compact0", "mold_support": "support0", "flux": "flux0", "baseline": "baseline"}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--run", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--index-name", default="run-manifest.json", choices=["run-manifest.json", "report.json"])
    parser.add_argument("--cases", nargs="+", choices=["views_core", "views_fatal"])
    args = parser.parse_args()
    if args.output.exists():
        raise SystemExit("Fresh output required")
    args.output.mkdir(parents=True)
    manifest = json.loads((args.run/args.index_name).read_text(encoding="utf-8-sig"))
    selected = [r for r in manifest["runs"] if args.cases is None or r["case"] in args.cases]
    checks = []

    def check(name, passed, detail=None):
        checks.append({"name": name, "pass": bool(passed), "detail": detail})

    def publication(label, fields, compare_authority=True):
        check(label+"_native_identities", digest(fields))
        if compare_authority:
            for view, source in COPY.items():
                check(label+"_exact_complete_"+view, fields["view_"+view]["sha256"] == fields[source]["sha256"])
            check(label+"_published_stroke_exact", fields["view_stroke"]["sha256"] == fields["stroke"]["sha256"])
        stamp = np.fromfile(fields["publication_stamp"]["path"], dtype="<i8")
        clock = np.fromfile(fields["view_clock"]["path"], dtype="<f4")
        check(label+"_int64_generation", int(stamp[0]) == 9007199254740993)
        return int(stamp[1]), float(clock[0])

    def render(label, fields, render):
        png = Path(render["path"])
        check(label+"_render_png_identity", hashlib.sha256(png.read_bytes()).hexdigest() == render["sha256"])
        pixels = np.asarray(Image.open(png).convert("RGBA"))
        check(label+"_three_static_consumers", pixels.shape == (16, 48, 4))
        value = lambda name, dtype="<f4": float(raw(fields, name, dtype)[128, 192])
        clock = float(np.fromfile(fields["view_clock"]["path"], dtype="<f4")[0])
        expected = [[value("view_sand"), value("view_water"), value("view_compaction", "<f2")], [value("view_sediment"), value("view_momentum_x")+.5, value("view_wetness", "<f2")], [value("view_rock"), value("view_baseline"), clock]]
        for index, x in enumerate((8, 24, 40)):
            actual = pixels[8, x, :3].astype(float)/255
            # RGBA8 CanvasItem output, half-LSB quantization plus renderer
            # conversion rounding. This does not loosen any physics budget.
            error = np.abs(actual-np.clip(expected[index], 0, 1))
            check(label+f"_material_pixels_{index}", np.all(error <= 1/255+1e-7) and pixels[8, x, 3] == 255, {"native_expected": expected[index], "actual_rgba8": pixels[8, x].tolist()})
            check(label+f"_reported_pixels_{index}", np.max(np.abs(np.array(render["pixels"][index])-pixels[8, x].astype(float)/255)) < 1e-7)

    check("two_complete_view_cases", {r["case"] for r in selected} == {"views_core", "views_fatal"})
    check("immutable_source", not manifest.get("drift", []))
    zz, xx = np.indices((256, 256))
    wx, wz = (xx+.5-128)*.125, (zz+.5-128)*.125
    template = np.fromfile(ROOT/"assets/brushes/castle/four_towers_v1.rgba32f", dtype="<f4").reshape(65, 65, 4)
    source_hashes = {p.removeprefix("res://").replace("\\", "/"): h.lower() for p, h in manifest["sources"].items()}
    check("actual_template_identity", hashlib.sha256(template.tobytes()).hexdigest() == source_hashes["assets/brushes/castle/four_towers_v1.rgba32f"])
    for run in selected:
        path = Path(run.get("result", run.get("evidence")))
        evidence = json.loads(path.read_text(encoding="utf-8"))
        label = run["case"]
        check(label+"_gpu_and_cleanup", manifest["pass"] and run["pass"] and evidence["pass"])
        check(label+"_result_identity", hashlib.sha256(path.read_bytes()).hexdigest() == run.get("result_sha256", run.get("evidence_sha256")).lower())
        log = (path.parent/"stdout.txt").read_text(encoding="utf-8-sig")+(path.parent/"probe.log").read_text(encoding="utf-8-sig")
        check(label+"_no_exit_leaks", "was leaked" not in log and "were leaked" not in log and "\nERROR:" not in log)
        obs = evidence["observations"]
        views = obs["views"]
        inputs = views["initial"]["physical"]
        check(label+"_native_half_subnormals_preserved", np.fromfile(inputs["wetness0"]["path"], dtype="<u2")[0] == np.fromfile(inputs["view_wetness"]["path"], dtype="<u2")[0] == 1 and np.fromfile(inputs["compact0"]["path"], dtype="<u2")[1] == np.fromfile(inputs["view_compaction"]["path"], dtype="<u2")[1] == 1)
        check(label+"_native_signed_zero_preserved", np.fromfile(inputs["qx0"]["path"], dtype="<u4")[2] == np.fromfile(inputs["view_momentum_x"]["path"], dtype="<u4")[2] == 0x80000000)
        snapshots = {}
        for phase in ("initial", "final"):
            fields = views[phase]["physical"]
            version, _ = publication(label+"_"+phase, fields)
            snapshots[version] = fields
            render(label+"_"+phase, fields, views[phase]["render"])
        surface = views["final"]["surface"]
        payload = Path(surface["path"]).read_bytes()
        check(label+"_physics_surface_identity", len(payload) == surface["bytes"] and hashlib.sha256(payload).hexdigest() == surface["sha256"])
        heights = np.frombuffer(payload, dtype="<f4").reshape(64, 33, 33)
        final_fields = views["final"]["physical"]
        final_bed = raw(final_fields, "view_rock")+raw(final_fields, "view_sand")
        final_version = int(np.fromfile(final_fields["publication_stamp"]["path"], dtype="<i8")[1])
        for chunk in range(64):
            x = np.minimum(255, chunk % 8*32+np.arange(33));z = np.minimum(255, chunk // 8*32+np.arange(33))
            check(label+f"_physics_matches_render_bed_{chunk}", np.array_equal(heights[chunk], final_bed[np.ix_(z, x)]) and 0 <= surface["versions"][str(chunk)] <= final_version)
        after = views["after_queries"]
        check(label+"_pure_queries_readonly", all(views["initial"]["physical"][physical]["sha256"] == after[physical]["sha256"] for physical in set(PRE.values()) | {"rock", "obstacle", "flux0", "flux1", "wetness0", "wetness1"}))
        check(label+"_preview_uses_no_edit_reservation", views["before_preview_highwater"] == views["after_pure_preview_highwater"] and views["before_preview_reservations"] == views["after_pure_preview_reservations"] and views["bound_materials"] == 3)
        orphan = obs.get("orphan_preview")
        if orphan:
            check(label+"_destroyed_receiver_releases_pending", not orphan["receiver_valid"] and not orphan["pending_after_delivery"] and orphan["query_serial"] > 0)
        for case in evidence["cases"]:
            version, _ = publication(label+"_"+case["label"], case["after"])
            snapshots[version] = case["after"]
            check(label+"_precommit_"+case["label"], all(case["before"][physical]["sha256"] == case["after"]["pre_"+key]["sha256"] for key, physical in PRE.items()))
        if "gpu_ahead_view" in obs:
            ahead = obs["gpu_ahead_view"]
            version, _ = publication(label+"_gpu_ahead", ahead["physical"])
            snapshots[version] = ahead["physical"]
            check(label+"_actual_publication_ahead_of_cpu", version == ahead["query_state_seq"] == ahead["cpu_state_seq"]+1)
        for query in views["queries"]:
            prefix = label+"_"+query["label"]
            data = Path(query["raw"]["path"]).read_bytes()
            check(prefix+"_native_receipt", len(data) == query["raw"]["bytes"] == 96 and hashlib.sha256(data).hexdigest() == query["raw"]["sha256"])
            words = np.frombuffer(data, dtype="<u4");floats = words.view("<f4")
            values, wire = query["result"], query["wire"]
            version = int(np.frombuffer(data, dtype="<i8")[3])
            fields = snapshots[version]
            check(prefix+"_real_source_version", values["generation"] == int(np.frombuffer(data, dtype="<i8")[2]) == 9007199254740993 and values["state_seq"] == version and data[16:48] == Path(fields["publication_stamp"]["path"]).read_bytes())
            ax, az, bx, bz = [float(np.float32(wire[k])) for k in ("start_x", "start_z", "end_x", "end_z")]
            if wire["shape"] == 2:
                angle, scale = float(np.float32(wire["yaw_rad"])), float(np.float32(wire["scale_xz"]))
                co, si = np.cos(angle), np.sin(angle)
                lx, lz = (co*(wx-ax)+si*(wz-az))/scale, (-si*(wx-ax)+co*(wz-az))/scale
                inside = (np.abs(lx) <= 2) & (np.abs(lz) <= 2)
                tx = np.clip(np.floor((lx+2)/.0625+.5).astype(int), 0, 64)
                tz = np.clip(np.floor((lz+2)/.0625+.5).astype(int), 0, 64)
                mask = inside & (template[tz, tx, 1] >= .5)
            else:
                dx, dz = bx-ax, bz-az
                length2 = dx*dx+dz*dz
                t = np.clip(((wx-ax)*dx+(wz-az)*dz)/length2, 0, 1) if length2 else 0
                distance = np.hypot(wx-ax-t*dx, wz-az-t*dz)
                radius = wire["bottom_width_m"]*.5 if wire["operation"] == 1 else (wire["trench_width_m"]*.5+wire["shoulder_width_m"] if wire["operation"] == 2 else wire["radius_m"])
                mask = (distance <= radius) & (radius > 0)
            sand, water = raw(fields, "view_sand"), raw(fields, "view_water")
            bed = raw(fields, "view_rock")+sand
            check(prefix+"_independent_footprint_count", int(mask.sum()) == int(words[16]) == values["count"])
            check(prefix+"_independent_min_max_water", floats[13] == bed[mask].min() and floats[14] == bed[mask].max() and floats[15] == water[mask].max())
            check(prefix+"_obstacle_count", int(np.count_nonzero(raw(fields, "view_obstacle", "u1")[mask] >= 128)) == words[17] == values["obstacles"])
            stroke = np.fromfile(fields["view_stroke"]["path"], dtype="<u4")
            stroke_id = int(stroke[2]) | int(stroke[3]) << 32;baseline_id = int(stroke[4]) | int(stroke[5]) << 32
            using = wire["height_reference"] == 2 and stroke[0] == 1 and stroke_id == wire["stroke_id"] and baseline_id == wire["baseline_token"]
            x, z = int(np.clip(np.floor(ax/.125+128), 0, 255)), int(np.clip(np.floor(az/.125+128), 0, 255))
            expected_base = wire["datum_y_m"] if wire["height_reference"] == 1 else (raw(fields, "view_baseline")[z, x] if using else bed[z, x])
            check(prefix+"_baseline_policy_and_native_base", floats[12] == np.float32(expected_base) and words[18] == using == values["uses_baseline"])
            check(prefix+"_completed_clock", floats[19] == np.fromfile(fields["view_clock"]["path"], dtype="<f4")[0] and values["tick"] == int(np.frombuffer(data, dtype="<i8")[5]))
            expected_error = {"superseded": "preview_superseded", "future_minimum": "stale_preview_version", "unknown_old_output": "stale_preview_version", "closing": "view_closed"}.get(query["label"], "")
            check(prefix+"_lifecycle_outcome", values["error"] == expected_error)
        if "view_fatal" in obs:
            fatal = obs["view_fatal"]
            check(label+"_fatal_raw_identities", digest(fatal["before"]) and digest(fatal["after"]))
            check(label+"_prefatal_authority_commit_survives", fatal["before"]["sand0"]["sha256"] != fatal["after"]["sand0"]["sha256"])
            for field in list(COPY)+["clock"]:
                check(label+"_fatal_view_preserved_"+field, fatal["before"]["view_"+field]["sha256"] == fatal["after"]["view_"+field]["sha256"])
            check(label+"_fatal_view_stamp_and_stroke", fatal["before"]["publication_stamp"]["sha256"] == fatal["after"]["publication_stamp"]["sha256"] and fatal["before"]["view_stroke"]["sha256"] == fatal["after"]["view_stroke"]["sha256"])
            render(label+"_fatal", fatal["before"], fatal["render"])
    report = {"pass": all(c["pass"] for c in checks), "checks": checks, "tool_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), "scope": "Only listed complete-view consumer cases. Native published render/material/baseline fields, 64-bit source stamp, independent disk/capsule/template footprints, actual RGBA8 material rendering, obsolete/unknown/closing queries and fatal last-complete preservation. No full G5/G6 formal-entry/restore/performance claim."}
    (args.output/"result.json").write_text(json.dumps(report, indent=2))
    print(json.dumps({"pass": report["pass"], "checks": len(checks), "failures": [c["name"] for c in checks if not c["pass"]]}))
    return 0 if report["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
