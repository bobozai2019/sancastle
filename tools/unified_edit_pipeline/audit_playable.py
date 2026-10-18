"""Independent candidate input/result and sealed-source audit."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import zipfile


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def audit(folder):
    report = json.loads((folder / "report.json").read_text("utf-8"))
    checks = []

    def check(name, passed):
        checks.append({"name": name, "pass": bool(passed)})

    check("runner_pass", report["pass"] is True)
    archive_path = Path(report["source_zip"])
    check("zip_identity", sha(archive_path) == report["source_zip_sha256"])
    with zipfile.ZipFile(archive_path) as archive:
        check("zip_crc", archive.testzip() is None)
        check("zip_index", json.loads(archive.read("evidence/source-index.json")) == report["sources"])
        for path, digest in report["sources"].items():
            check("source:" + path, hashlib.sha256(archive.read(path.removeprefix("res://"))).hexdigest() == digest)
        for path in ["scripts/simulation/unified_edit/player_input.gd", "scripts/beach/unified_playable_entry.gd"]:
            source = archive.read(path).decode("utf-8")
            check("no_private_gpu_writer:" + path, not any(token in source for token in ["call_on_render_thread", "RenderingDevice", ".pump(", "buffer_update(", "texture_update("]))
        source = archive.read("scripts/beach/unified_playable_entry.gd").decode("utf-8")
        check("node3d_root_only", source.startswith("extends Node3D\n"))
    total = 0
    for run in report["runs"]:
        case = run["case"]
        path = Path(run["evidence"])
        document = json.loads(path.read_text("utf-8"))
        total += len(document["checks"])
        check(case + ":result_identity", sha(path) == run["evidence_sha256"])
        check(case + ":all_checks", document["pass"] is True and all(row["pass"] is True for row in document["checks"]))
        for name in ["stdout.txt", "probe.log"]:
            log = (path.parent / name).read_text("utf-8", errors="replace")
            check(case + ":log:" + name, re.search(r"ERROR:|SCRIPT ERROR:|\bleaked\b|Stray Node:|resources still in use", log, re.I) is None)
        observations = document["observations"]
        if case == "pointer":
            rows = {row["command_id"]: row for row in observations["results"]}
            check("pointer:five_common_commands", set(rows) == set(range(1, 6)))
            check("pointer:all_actual_terminal", all(row["completion_phase"] == 1 and row["outcome"] in [1, 2] and row["invalid_flags"] == 0 for row in rows.values()))
            check("pointer:actual_fill", rows[1]["outcome"] == 1 and rows[1]["added_m3"] > 0)
            check("pointer:shape_same_baseline", all(rows[i]["stroke_id"] == rows[i]["baseline_token"] == 2 for i in range(2, 6)))
            check("pointer:keyboard_clock", observations["first_space"]["playing"] is True and observations["second_space"]["playing"] is False and observations["second_space"]["tick"] >= 1)
            camera = observations["camera"]
            check("pointer:camera_and_projection", camera["before"] != camera["after"] and camera["source_projection"] == camera["reflection_projection"] and abs(camera["source_fov"] - camera["reflection_fov"]) < 1e-5)
            continue
        if case == "scene_service":
            records = observations["release_records"]
            check("service:all_disposed", len(records) >= 3 and all(row["gpu_released"] and row["node_freed"] for row in records))
            check("service:both_domains_saved", set(observations["saved"]) == {"main", "test1_capture"})
            continue
        sources = observations["sources"]
        check(case + ":project_settings_pinned", "res://project.godot" in sources)
        check(case + ":import_settings_pinned", any(path.endswith(".import") for path in sources))
        check(case + ":imported_binaries_pinned", any(path.startswith("res://.godot/imported/") for path in sources))
        rows = {row["command_id"]: row for row in observations["tool_results"]}
        check(case + ":complete_identity_set", set(rows) == set(range(1, 14)))
        for command_id, row in rows.items():
            name = f"{case}:command:{command_id}:"
            check(name + "actual_terminal_phase", row["completion_phase"] == 1)
            check(name + "outcome", row["outcome"] in [1, 2])
            check(name + "epoch", row["generation"] == 1001)
            check(name + "error_free", row["invalid_flags"] == 0 and row["error_code"] == 0)
            for key in ["added_m3", "removed_m3", "transferred_m3", "sand_error_m3", "water_error_m3"]:
                check(name + key + ":finite", math.isfinite(row[key]))
        for command_id, stroke in [(3, 3), (4, 3), (5, 3), (6, 6), (7, 6), (8, 6), (9, 6), (10, 10), (11, 10), (12, 10), (13, 10)]:
            check(f"{case}:stroke:{command_id}", rows[command_id]["stroke_id"] == rows[command_id]["baseline_token"] == stroke)
        for command_id, expected in [(1, 0.1), (2, max(0.1 / 30, 0.05 * 0.1 / 0.75))]:
            row = rows[command_id]
            check(f"{case}:physical_drag_volume:{command_id}", abs(row["added_m3"] - expected) <= row["eps_sand_m3"])
        check(case + ":real_wave_declaration", abs(observations["wave"]["amplitude"] - 0.07) < 1e-12 and observations["wave"]["highwater"] == 1)
    return {"pass": all(row["pass"] for row in checks), "checks": checks, "direct_checks": total,
            "source_count": len(report["sources"]), "report_sha256": sha(folder / "report.json"),
            "auditor_sha256": sha(Path(__file__)),
            "scope": "Declaration/result identities, physical click/drag volumes, sources/import identities and logs. Not a full UI/pointer/preview/gravel/cost acceptance."}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("folder", type=Path)
    args = parser.parse_args()
    folder = args.folder.resolve()
    target = folder / "audit.json"
    if target.exists():
        raise FileExistsError(target)
    result = audit(folder)
    target.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"pass": result["pass"], "checks": len(result["checks"]), "direct": result["direct_checks"], "sources": result["source_count"]}))
    raise SystemExit(0 if result["pass"] else 1)
