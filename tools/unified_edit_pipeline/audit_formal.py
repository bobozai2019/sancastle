"""Formal entry, native family cache and immutable source audit; not G7 writer audit."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import zipfile

from native_variant import VariantReader

ROOT = Path(__file__).resolve().parents[2]
KEYS = ["main", "test1_capture", "test1_backwash", "test1_geometry"]
FORMAL = {key: "res://scenes/main.tscn" if key == "main" else f"res://scenes/playable/{key}.tscn" for key in KEYS}
CANDIDATE = {key: f"res://scenes/unified_edit/playable/{key}.tscn" for key in KEYS}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def local(path):
    return ROOT / path.removeprefix("res://")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("run", type=Path)
    parser.add_argument("--static", type=Path, required=True)
    parser.add_argument("--cutover", type=Path, required=True)
    args = parser.parse_args()
    folder = args.run.resolve();output = folder / "audit.json"
    if output.exists():raise SystemExit("Fresh audit output required")
    checks = []

    def check(name, passed):
        checks.append({"name": name, "pass": bool(passed)})

    report = json.loads((folder / "report.json").read_text("utf-8"))
    check("runner_pass", report["pass"])
    check("seven_required_cases", {x["case"] for x in report["runs"]} == {"startup", "formal_service", "candidate_service", *{"formal_" + k for k in KEYS}})
    with zipfile.ZipFile(report["source_zip"]) as archive:
        check("source_zip_hash", sha(Path(report["source_zip"])) == report["source_zip_sha256"])
        check("source_zip_crc", archive.testzip() is None)
        for path, digest in report["sources"].items():
            check("archived_" + path, hashlib.sha256(archive.read(path.removeprefix("res://"))).hexdigest() == digest)
            check("current_" + path, sha(local(path)) == digest)
    before = json.loads((args.cutover / "before.json").read_text("utf-8"))
    with zipfile.ZipFile(args.cutover / "before.zip") as archive:
        check("pre_cutover_zip_crc", archive.testzip() is None)
        for path, identity in before["sources"].items():
            raw = archive.read(path)
            check("pre_cutover_" + path, len(raw) == identity["bytes"] and hashlib.sha256(raw).hexdigest() == identity["sha256"])
    static = json.loads((args.static / "audit.json").read_text("utf-8"))
    check("static_node_audit_pass", static["pass"] and all(x["pass"] for x in static["checks"]))
    for entry in static["entries"]:
        check("static_entry_" + entry["key"], sha(local(entry["path"])) == entry["sha256"] and entry["path"] == FORMAL[entry["key"]])
        check("one_runtime_" + entry["key"], list(entry["scripts"].values()).count("res://scripts/simulation/unified_edit/domain_runtime.gd") == 1)
    for key in KEYS:
        formal = local(FORMAL[key]).read_text("utf-8")
        candidate = local(CANDIDATE[key]).read_text("utf-8")
        check("wrapper_equivalence_" + key, re.sub(r' uid="[^"]+"', '', formal) == candidate)
        check("unified_root_binding_" + key, 'path="res://scripts/beach/unified_playable_entry.gd"' in formal and 'path="res://scripts/beach/unified_performance_panel.gd"' in formal)
        manifest = json.loads((ROOT / f"assets/unified_edit/presentation/{key}.json").read_text("utf-8"))["metadata"]
        check("extraction_source_preserved_" + key, manifest["source_scene_sha256"] == before["sources"][FORMAL[key].removeprefix("res://")]["sha256"])

    def native(path, family, key):
        raw = Path(path).read_bytes()
        tag = family + "_" + key + "_" + Path(path).name
        check(tag + "_header", raw[:8] == b"SANDUE06" and int.from_bytes(raw[8:12], "little") == 1)
        check(tag + "_length", int.from_bytes(raw[12:16], "little") == len(raw) - 48)
        check(tag + "_digest", hashlib.sha256(raw[48:]).digest() == raw[16:48])
        reader = VariantReader(raw[48:])
        check(tag + "_dictionary", reader.unpack("<I") == 27)
        count = reader.unpack("<I");prefix = {}
        for _ in range(count):
            name = reader.value();prefix[name] = reader.value()
            if name == "configuration":break
        config = prefix["configuration"]
        scene = (FORMAL if family == "formal" else CANDIDATE)[key]
        check(tag + "_exact_scene_identity", config["sources"].get(scene) == report["sources"][scene])
        check(tag + "_domain", config["domain_id"] == ("main_beach" if key == "main" else key))
        check(tag + "_unified_family", config["family"] == "unified_edit")
        return prefix

    for run in report["runs"]:
        name = run["case"];path = Path(run["evidence"])
        check(name + "_evidence_identity", sha(path) == run["evidence_sha256"])
        check(name + "_exit_logs", run["exit_code"] == 0 and run["clean_logs"])
        data = json.loads(path.read_text("utf-8"))
        check(name + "_probe_pass", data["pass"] and all(x["pass"] for x in data["checks"]))
        observed = data["observations"]
        for file, digest in observed["sources"].items():check(name + "_consumed_" + file, report["sources"][file] == digest)
        if name == "startup":
            check("default_startup_real_clock", observed["tick"] >= 3 and observed["time"] > 0)
            check("default_startup_render", (path.parent / "startup.png").is_file())
        elif name in ["formal_service", "candidate_service"]:
            family = "formal" if name == "formal_service" else "candidate"
            saved = observed["saved"]
            expected = {family + ":" + k for k in (KEYS if family == "formal" else ["main", "test1_capture"])}
            check(name + "_separate_progress_keys", set(saved) == expected)
            for cache, value in saved.items():native(value["path"], family, cache.split(":", 1)[1])
            check(name + "_actual_roots_freed", all(x["gpu_released"] and x["node_freed"] for x in observed["release_records"]))
        else:
            key = name.removeprefix("formal_")
            native(path.parent / "playable.sandue", "formal", key)
            check(name + "_tool_results", len(observed["tool_results"]) == 13 and all(r["outcome"] in [1, 2] and r["generation"] == 1001 for r in observed["tool_results"]))
            check(name + "_actual_material_render", (path.parent / "playable.png").is_file())
    result = {"pass": all(x["pass"] for x in checks), "checks": checks,
              "auditor_sha256": sha(Path(__file__)), "decoder_sha256": sha(ROOT / "tools/unified_edit_pipeline/native_variant.py"),
              "scope": "Formal/candidate entry identity and cache containers, archived/current source hashes, actual static nodes and runtime probe evidence; not full G7 writer or G8 cost acceptance"}
    output.write_text(json.dumps(result, indent=2), encoding="utf-8")
    print("FORMAL_AUDIT", result["pass"], "checks", len(checks))
    raise SystemExit(0 if result["pass"] else 1)


if __name__ == "__main__":main()
