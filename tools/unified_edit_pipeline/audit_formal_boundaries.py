"""Independent formal lifecycle metadata/container audit, not kernel/cost acceptance."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile

from native_variant import VariantReader
from audit_front_lifecycle import PHYSICAL, DISPLAY, PROFILES, MASKS

ROOT = Path(__file__).resolve().parents[2]


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("run", type=Path)
    args = parser.parse_args();folder = args.run.resolve();out = folder / "audit.json"
    if out.exists():raise SystemExit("Fresh audit output required")
    checks = []

    def check(name, value):checks.append({"name": name, "pass": bool(value)})

    report = json.loads((folder / "report.json").read_text("utf-8"))
    expected = {m + "_" + k for m in ["capture", "height", "physics", "recorded", "save", "close", "candidate"] for k in ["main", "test1_geometry"]}
    expected |= {"suite_" + k for k in ["main", "test1_geometry"]}
    check("all_eighteen_cases", report["pass"] and {r["case"] for r in report["runs"]} == expected)
    with zipfile.ZipFile(report["source_zip"]) as z:
        check("source_zip_sha256", sha(Path(report["source_zip"])) == report["source_zip_sha256"])
        check("source_zip_crc", z.testzip() is None)
        for name, digest in report["sources"].items():check("source_" + name, hashlib.sha256(z.read(name.removeprefix("res://"))).hexdigest() == digest)

    def native(snapshot, name):
        path = Path(snapshot["path"]);raw = path.read_bytes()
        if "sha256" in snapshot:check(name + "_file_sha", sha(path) == snapshot["sha256"])
        check(name + "_header", raw[:8] == b"SANDUE06" and int.from_bytes(raw[8:12], "little") == 1)
        check(name + "_length", int.from_bytes(raw[12:16], "little") == len(raw) - 48)
        check(name + "_payload_sha", hashlib.sha256(raw[48:]).digest() == raw[16:48])
        reader = VariantReader(raw[48:]);check(name + "_dictionary", reader.unpack("<I") == 27)
        count = reader.unpack("<I");prefix = {}
        for _ in range(count):
            key = reader.value();prefix[key] = reader.value()
            if key == "configuration":break
        check(name + "_epoch", prefix["generation"] == 1001)
        check(name + "_completed_sequence", prefix["state_seq"] == snapshot["state_seq"])
        check(name + "_runtime_identity", prefix["configuration"]["sources"]["res://scripts/simulation/unified_edit/domain_runtime.gd"] == report["sources"]["res://scripts/simulation/unified_edit/domain_runtime.gd"])
        return prefix

    for run in report["runs"]:
        case = run["case"];path = Path(run["evidence"])
        check(case + "_evidence_sha", sha(path) == run["evidence_sha256"])
        check(case + "_real_exit_and_logs", run["exit_code"] == 0 and run["clean_logs"])
        data = json.loads(path.read_text("utf-8"));obs = data["observations"]
        check(case + "_runtime_checks", data["pass"] and all(c["pass"] for c in data["checks"]))
        check(case + "_no_forced_cleanup", not obs.get("forced_cleanup", False))
        key = case.split("_", 1)[1]
        entry = "res://scenes/main.tscn" if key == "main" else "res://scenes/playable/" + key + ".tscn"
        check(case + "_formal_source_consumed", obs["sources"].get(entry) == report["sources"][entry])
        rows = sorted(obs.get("results", []), key=lambda r: r["command_id"])
        for row in rows:
            tag = case + "_" + str(row["command_id"])
            check(tag + "_gpu_terminal", row["magic"] in [PHYSICAL, DISPLAY] and row["completion_phase"] == 1 and row["stride"] == 384 and row["generation"] == 1001 and row["outcome"] in [1, 2] and row["error_code"] == 0)
        if case.startswith("capture_"):
            before = obs["capture_before"];after = obs["capture_after"];live = obs["live_capture"]
            check(case + "_real_unknown_capture", before["phase"] == "unknown" and before["registered"] > 0 and before["pending"] == 0 and not before["finished"])
            check(case + "_live_capture_error_recovered", live["finished"] and live["error"] == "checkpoint_readback_registration" and not live["owner_released"])
            check(case + "_retired_capture_proof_completed", after["finished"] and after["released"] and after["error"] == "checkpoint_readback_registration")
            check(case + "_no_failed_snapshot_file", not (path.parent / "unknown_current.sandue").exists() and not (path.parent / "unknown_close.sandue").exists())
        elif case.startswith("height_"):
            events = obs["height_events"];unknowns = [e for e in events if e["event"] == "readback_unknown"]
            check(case + "_actual_unknown_exists", bool(unknowns))
            for unknown in unknowns:
                later = [e for e in events if e["identity"] == unknown["identity"] and e["frame"] >= unknown["frame"]]
                check(case + "_same_reader_delivered", any(e["event"] == "capture" for e in later))
                check(case + "_same_reader_last_consumer", any(e["event"] == "last_consumer" for e in later))
            check(case + "_actual_collision_converged", obs["state_seq"] > 0 and obs["applied"] >= obs["state_seq"])
        elif case.startswith("physics_"):
            value = native(obs["snapshot"], case)
            check(case + "_saved_ahead_of_collision", value["state_seq"] > obs["snapshot"]["applied_before"])
            retired = next(e for e in obs["events"] if e["kind"] == "retire_started")
            check(case + "_height_ack_after_close", any(e["event"] == "last_consumer" and e["frame"] >= retired["frame"] for e in obs["height_events"]))
        elif case.startswith("recorded_"):
            value = native(obs["snapshot"], case)
            check(case + "_three_commands_consumed", [r["command_id"] for r in rows] == [1, 2, 3] and value["highwater_id"] == 3)
            check(case + "_actual_publication_saved", value["state_seq"] == max(r["state_seq"] for r in rows))
        elif case.startswith("suite_"):
            declarations = obs["declarations"]
            check(case + "_all_eleven_profiles", {d["profile_id"] for d in declarations.values() if d["profile_id"] and d["profile_id"] != "gravel_drop"} == PROFILES)
            check(case + "_all_accepted_ids", [r["command_id"] for r in rows] == list(range(1, len(declarations) + 1)))
            for row in rows:
                d = declarations[str(row["command_id"])];tag = case + "_" + str(row["command_id"])
                check(tag + "_frozen_identity", row["effective_hash"] == d["effective_hash"] and row["profile_version"] == d["profile_version"])
                if d["profile_id"] == "gravel_drop":check(tag + "_display_only", row["magic"] == DISPLAY and row["changed_fields"] == 0 and row["display_count"] == d["count"])
                else:check(tag + "_declared_fields", row["magic"] == PHYSICAL and row["changed_fields"] & ~MASKS.get(d["profile_id"], 32) == 0)
        elif case.startswith("save_"):
            value = native(obs["saved"], case)
            check(case + "_full_queue_and_end", len(rows) == 65 and value["highwater_id"] == 65 and [r["command_id"] for r in rows] == list(range(1, 66)))
            check(case + "_batch_sequence_not_command_count", value["state_seq"] == max(r["state_seq"] for r in rows) < 65)
        elif case.startswith("close_"):
            check(case + "_edit_water_display_order", [r["command_id"] for r in rows] == [1, 2, 3] and [r["state_seq"] for r in rows] == [1, 1, 3] and [r["applied_tick"] for r in rows] == [0, 0, 1])
        elif case.startswith("candidate_"):
            failures = obs["failures"]
            check(case + "_three_actual_failure_kinds", [x["kind"] for x in failures] == ["initialize", "preflight", "cancel"])
            check(case + "_failed_epochs_not_reused", [x["generation"] for x in failures] == [1002, 1003, 1004] and obs["final_generation"] == 1005)
            for failure in failures:check(case + "_released_" + failure["kind"], failure["error"] and failure["released"] and failure["owned"] == 0 and failure["old_generation"] == 1001 and failure["state_seq"] > 0)
    result = {"pass": all(c["pass"] for c in checks), "checks": checks,
              "scope": "Formal lifecycle metadata, same-reader retry identity, native prefix and source archive. No new physics formula, startup cost or performance acceptance.",
              "auditor_sha256": sha(Path(__file__)), "dependencies": {name: sha(ROOT / "tools/unified_edit_pipeline" / name) for name in ["native_variant.py", "audit_front_lifecycle.py"]}}
    out.write_text(json.dumps(result, indent=2), encoding="utf-8")
    print("FORMAL_BOUNDARY_AUDIT", result["pass"], "checks", len(checks))
    raise SystemExit(0 if result["pass"] else 1)


if __name__ == "__main__":main()
