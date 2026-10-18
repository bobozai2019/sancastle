"""Audit declaration/result identity, lifecycle evidence and saved container prefix.

This does not re-prove the physical kernels or decode the full native payload.
Those remain covered by their original, separately scoped gates.
"""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile

from native_variant import VariantReader

ROOT = Path(__file__).resolve().parents[2]
PHYSICAL = 0x31524555
DISPLAY = 0x31524455
PROFILES = {"dig_v1", "dig_sweep_v1", "fill_v1", "fill_sweep_v1", "suspended_v1",
            "suspended_sweep_v1", "castle_v1", "wall_v1", "shovel_v1", "smooth_v1", "compact_v1"}
MASKS = {name: 31 for name in PROFILES}
MASKS.update(suspended_v1=2, suspended_sweep_v1=2, smooth_v1=5, compact_v1=4,
             castle_v1=63, wall_v1=63, shovel_v1=63)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("run", type=Path)
    args = parser.parse_args()
    folder = args.run.resolve()
    target = folder / "audit.json"
    if target.exists():raise SystemExit("Fresh audit output required")
    checks = []

    def check(name, passed):
        checks.append({"name": name, "pass": bool(passed)})

    report = json.loads((folder / "report.json").read_text("utf-8"))
    check("runner_pass", report["pass"])
    check("nine_explicit_cases", {r["case"] for r in report["runs"]} ==
          {"suite_main", "suite_test1_capture", "suite_test1_backwash", "suite_test1_geometry",
           "save_main", "save_test1_geometry", "close_main", "close_test1_geometry", "pointer"})
    with zipfile.ZipFile(report["source_zip"]) as archive:
        check("source_zip_sha256", sha(Path(report["source_zip"])) == report["source_zip_sha256"])
        check("source_zip_crc", archive.testzip() is None)
        for name, digest in report["sources"].items():
            check("source_" + name, hashlib.sha256(archive.read(name.removeprefix("res://"))).hexdigest() == digest)

    for run in report["runs"]:
        case = run["case"]
        path = Path(run["evidence"])
        check(case + "_evidence_hash", sha(path) == run["evidence_sha256"])
        check(case + "_actual_exit_and_logs", run["exit_code"] == 0 and run["clean_logs"])
        data = json.loads(path.read_text("utf-8"))
        check(case + "_all_probe_checks", data["pass"] and all(x["pass"] for x in data["checks"]))
        if case == "pointer":continue
        rows = sorted(data["observations"]["results"], key=lambda r: r["command_id"])
        ids = [r["command_id"] for r in rows]
        check(case + "_dense_unique_results", ids == list(range(1, len(rows) + 1)))
        seq = [r["state_seq"] for r in rows]
        check(case + "_ordered_batch_publications", seq == sorted(seq) and min(seq) >= 1)
        for row in rows:
            name = case + "_" + str(row["command_id"])
            check(name + "_real_gpu_header", row["magic"] in [PHYSICAL, DISPLAY] and row["version"] == 1 and row["stride"] == 384 and row["completion_phase"] == 1)
            check(name + "_successful_terminal", row["outcome"] in [1, 2] and row["error_code"] == 0 and row["invalid_flags"] == 0)
            check(name + "_exact_epoch", row["generation"] == 1001)
        if case.startswith("suite_"):
            declarations = data["observations"]["declarations"]
            check(case + "_all_accepted_ids_recorded", set(declarations) == {str(x) for x in ids})
            check(case + "_eleven_physical_profiles", {d["profile_id"] for d in declarations.values() if d["profile_id"] and d["profile_id"] != "gravel_drop"} == PROFILES)
            for row in rows:
                declaration = declarations[str(row["command_id"])]
                profile = declaration["profile_id"]
                name = case + "_" + str(row["command_id"])
                check(name + "_configuration_snapshot", row["effective_hash"] == declaration["effective_hash"] and row["profile_version"] == declaration["profile_version"])
                check(name + "_no_water_tick", row["applied_tick"] == 0)
                if profile == "gravel_drop":
                    check(name + "_display_namespace", row["magic"] == DISPLAY and row["display_count"] == declaration["count"] and row["changed_fields"] == 0 and not row["authority_changed"])
                else:
                    check(name + "_physical_namespace", row["magic"] == PHYSICAL)
                    check(name + "_declared_fields_only", row["changed_fields"] & ~MASKS.get(profile, 32) == 0)
                    if profile in ["smooth_v1", "compact_v1"]:
                        check(name + "_disk_stamp_endpoints", declaration["start"] == declaration["end"])
            check(case + "_visible_render", (path.parent / "suite.png").is_file())
        elif case.startswith("save_"):
            saved = data["observations"]["saved"]
            file = Path(saved["path"])
            raw = file.read_bytes()
            check(case + "_saved_file_identity", sha(file) == saved["sha256"])
            check(case + "_native_header", raw[:8] == b"SANDUE06" and int.from_bytes(raw[8:12], "little") == 1)
            check(case + "_container_length", int.from_bytes(raw[12:16], "little") == len(raw) - 48)
            check(case + "_payload_checksum", hashlib.sha256(raw[48:]).digest() == raw[16:48])
            reader = VariantReader(raw[48:])
            check(case + "_dictionary_prefix", reader.unpack("<I") == 27)
            count = reader.unpack("<I")
            prefix = {}
            for _ in range(count):
                key = reader.value()
                if key == "configuration":break
                prefix[key] = reader.value()
            check(case + "_sixty_four_commands_and_one_end", len(rows) == 65 and prefix["highwater_id"] == 65)
            check(case + "_actual_batch_sequence_saved", prefix["state_seq"] == max(seq) == saved["state_seq"] and prefix["sim_tick"] == 0)
            check(case + "_no_command_count_as_publication", prefix["state_seq"] < 65)
        elif case.startswith("close_"):
            check(case + "_all_three_input_results", len(rows) == 3 and sum(r["magic"] == PHYSICAL for r in rows) == 2 and sum(r["magic"] == DISPLAY for r in rows) == 1)
            check(case + "_water_between_edit_and_display", [r["state_seq"] for r in rows] == [1, 1, 3] and [r["applied_tick"] for r in rows] == [0, 0, 1])
            events = data["observations"]["events"]
            retired = next(e for e in events if e["kind"] == "retire_started")
            released = next(e for e in events if e["kind"] == "retired")
            check(case + "_retirement_waited_real_frames", released["frame"] > retired["frame"] and released["physics_frame"] > retired["physics_frame"])
            check(case + "_final_closed_event", events[-1]["kind"] == "closed")
    result = {"pass": all(c["pass"] for c in checks), "checks": checks,
              "scope": "Independent declaration/result metadata, saved container prefix, source archive and lifecycle audit; not a new physical algorithm or cost acceptance",
              "auditor_sha256": sha(Path(__file__)), "decoder_sha256": sha(ROOT / "tools/unified_edit_pipeline/native_variant.py")}
    target.write_text(json.dumps(result, indent=2), encoding="utf-8")
    print("FRONT_AUDIT", result["pass"], "checks", len(checks))
    raise SystemExit(0 if result["pass"] else 1)


if __name__ == "__main__":main()
