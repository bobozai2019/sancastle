"""Independent special-lifecycle, raw preview and formal source identity audit."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import zipfile

ROOT = Path(__file__).resolve().parents[2]


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser();parser.add_argument("run", type=Path);args = parser.parse_args()
    folder = args.run.resolve();out = folder / "audit.json"
    if out.exists():raise SystemExit("Fresh audit output required")
    checks = []

    def check(name, value):checks.append({"name": name, "pass": bool(value)})

    report = json.loads((folder / "report.json").read_text("utf-8"))
    expected = {m + "_" + k for m in ["boot", "restoreclose", "faultrestore", "faultclose", "detach", "preview", "gravel", "migration"] for k in ["main", "test1_geometry"]}
    check("sixteen_required_cases", report["pass"] and {r["case"] for r in report["runs"]} == expected)
    with zipfile.ZipFile(report["source_zip"]) as archive:
        check("source_zip_hash", sha(Path(report["source_zip"])) == report["source_zip_sha256"])
        check("source_zip_crc", archive.testzip() is None)
        for name, digest in report["sources"].items():check("archived_" + name, hashlib.sha256(archive.read(name.removeprefix("res://"))).hexdigest() == digest)
    for run in report["runs"]:
        name = run["case"];mode, key = name.split("_", 1);path = Path(run["evidence"])
        check(name + "_evidence_sha", sha(path) == run["evidence_sha256"])
        check(name + "_real_exit_logs", run["exit_code"] == 0 and run["clean_logs"])
        data = json.loads(path.read_text("utf-8"));obs = data["observations"]
        check(name + "_all_runtime_checks", data["pass"] and all(c["pass"] for c in data["checks"]))
        entry = "res://scenes/main.tscn" if key == "main" else "res://scenes/playable/test1_geometry.tscn"
        check(name + "_actual_formal_entry", obs["sources"].get(entry) == report["sources"][entry])
        if mode in ["boot", "restoreclose", "faultrestore", "faultclose", "detach"]:
            released = obs["released"]
            for field, value in released.items():
                if field == "owned" or field.endswith("_owned"):check(name + "_zero_" + field, value == 0)
                if field == "released" or field.endswith("_released"):check(name + "_true_" + field, value)
            events = obs["events"]
            if mode == "faultrestore":
                # This observation is taken while the recovered root is live;
                # the shared _close() then verifies closed/released separately.
                check(name + "_old_retired_event", any(e["kind"] == "retired" and e["detail"]["generation"] == 1001 for e in events))
                check(name + "_final_release_receipt", any(c["name"] == "entry_released" and c["pass"] for c in data["checks"]))
            else:check(name + "_closed_event", events[-1]["kind"] == "closed")
            if mode == "boot":check(name + "_never_committed", not any(e["kind"] == "commit" for e in events))
            if mode == "restoreclose":check(name + "_cancelled_restore", bool(released["restore_error"]))
            if mode == "detach":check(name + "_real_detach_confirmation", released["detached_confirmed"])
            if mode.startswith("fault"):
                rows = obs["unknown_results"]
                check(name + "_unknown_once", len(rows) == 1 and rows[0]["generation"] == 1001 and rows[0]["command_id"] == 1)
                check(name + "_no_fabricated_outcome", rows[0]["unknown"] and rows[0]["submitted"] and "outcome" not in rows[0])
                check(name + "_no_unknown_publication", released["completed_state_seq"] == 0)
                if mode == "faultrestore":
                    fresh = [r for r in obs["new_results"] if r.get("generation") == 1002 and r.get("command_id") == 1]
                    check(name + "_new_epoch_has_own_outcome", len(fresh) == 1 and fresh[0]["outcome"] == 1 and fresh[0]["state_seq"] > 0)
        elif mode == "preview":
            for label in ["playing", "baseline", "restored"]:
                value = obs[label];item = value["raw_file"];raw = Path(item["path"]).read_bytes();tag = name + "_" + label
                check(tag + "_exact_bytes", len(raw) == item["bytes"] == 96 and sha(Path(item["path"])) == item["sha256"])
                check(tag + "_schema_reserved", struct.unpack_from("<I", raw)[0] == 1 and not any(raw[80:]))
                for field, offset in [("query_serial", 8), ("generation", 16), ("state_seq", 24), ("revision", 32), ("tick", 40)]:check(tag + "_" + field, struct.unpack_from("<q", raw, offset)[0] == value[field])
                for field, offset in [("flags", 4), ("count", 64), ("obstacles", 68)]:check(tag + "_" + field, struct.unpack_from("<I", raw, offset)[0] == value[field])
                for field, offset in [("base", 48), ("minimum", 52), ("maximum", 56), ("water", 60), ("time_s", 76)]:check(tag + "_" + field, abs(struct.unpack_from("<f", raw, offset)[0] - value[field]) < 1e-6)
                check(tag + "_baseline", bool(struct.unpack_from("<I", raw, 72)[0]) == value["uses_baseline"])
                check(tag + "_advisory_snapshot", value["freshness"] == 1 and value["advisory"] and not value["error"])
            check(name + "_real_time_preview", obs["playing"]["generation"] == 1001 and obs["playing"]["tick"] > 0)
            check(name + "_actual_stroke_baseline", obs["baseline"]["uses_baseline"])
            check(name + "_new_epoch_preview", obs["restored"]["generation"] == 1002)
        elif mode == "migration":
            rows = obs["migrations"]
            check(name + "_migration_scope", len(rows) == (2 if key == "main" else 0))
            for row in rows:
                check(name + "_source_" + row["format"], sha(ROOT / row["source"].removeprefix("res://")) == row["source_sha256"])
                check(name + "_native_" + row["format"], sha(Path(row["native"])) == row["native_sha256"])
        elif mode == "gravel":check(name + "_population_grew", obs["final_count"] > obs["initial_count"])
    result = {"pass": all(c["pass"] for c in checks), "checks": checks,
              "auditor_sha256": sha(Path(__file__)),
              "scope": "Formal node source, exact preview bytes, unknown terminal namespace, owner release and real subprocess evidence; old/native full raw fields are independently audited by audit_migration.gd"}
    out.write_text(json.dumps(result, indent=2), encoding="utf-8")
    print("FORMAL_REMAINING_AUDIT", result["pass"], "checks", len(checks))
    raise SystemExit(0 if result["pass"] else 1)


if __name__ == "__main__":main()
