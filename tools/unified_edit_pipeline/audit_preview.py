"""Independent reads of 96-byte query results and immutable physical snapshots."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import zipfile

from PIL import Image


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def audit(folder):
    report = json.loads((folder / "report.json").read_text("utf-8"));checks = [];details = {};total = 0

    def check(name, value):checks.append({"name": name, "pass": bool(value)})

    def raw(item, label):
        path = Path(item["path"]);value = path.read_bytes()
        check(label + ":identity", len(value) == item["bytes"] and sha(path) == item["sha256"])
        return value

    def query(value, item, label):
        data = raw(item, label)
        check(label + ":schema", len(data) == 96 and struct.unpack_from("<I", data)[0] == 1 and not any(data[80:]))
        for key, offset in [("query_serial", 8), ("generation", 16), ("state_seq", 24), ("revision", 32), ("tick", 40)]:
            check(label + ":" + key, struct.unpack_from("<q", data, offset)[0] == value[key])
        for key, offset in [("flags", 4), ("count", 64), ("obstacles", 68)]:
            check(label + ":" + key, struct.unpack_from("<I", data, offset)[0] == value[key])
        for key, offset in [("base", 48), ("minimum", 52), ("maximum", 56), ("water", 60), ("time_s", 76)]:
            check(label + ":" + key, abs(struct.unpack_from("<f", data, offset)[0] - value[key]) < 1e-6)
        check(label + ":baseline", bool(struct.unpack_from("<I", data, 72)[0]) == value["uses_baseline"])

    check("runner_pass", report["pass"] is True)
    archive_path = Path(report["source_zip"])
    check("archive_identity", sha(archive_path) == report["source_zip_sha256"])
    with zipfile.ZipFile(archive_path) as archive:
        check("archive_crc", archive.testzip() is None)
        check("archive_index", json.loads(archive.read("evidence/source-index.json")) == report["sources"])
        for name, digest in report["sources"].items():check("source:" + name, hashlib.sha256(archive.read(name.removeprefix("res://"))).hexdigest() == digest)
    for run in report["runs"]:
        case = run["case"];path = Path(run["evidence"]);data = json.loads(path.read_text("utf-8"));o = data.get("observations", {})
        total += len(data["checks"])
        check(case + ":report_identity", sha(path) == run["evidence_sha256"])
        check(case + ":all_direct_checks", data["pass"] is True and all(c["pass"] for c in data["checks"]))
        for name in ["stdout.txt", "probe.log"]:check(case + ":" + name, re.search(r"ERROR:|SCRIPT ERROR:|\bleaked\b|Stray Node:|resources still in use", (path.parent / name).read_text("utf-8", errors="replace"), re.I) is None)
        if case == "snapshot":
            rows = {row["label"]: row["result"] for row in o["queries"]}
            for label, value in rows.items():query(value, value["raw"], label)
            check("snapshot:older_complete_accepted", rows["snapshot_behind"]["error"] == "" and rows["snapshot_behind"]["state_seq"] == 0 and rows["snapshot_behind"]["state_lag"] == 2)
            check("snapshot:strict_rejects", rows["strict_behind"]["error"] == "stale_preview_version" and rows["strict_behind"]["freshness"] == 0)
            check("snapshot:minimum_still_required", rows["future_minimum"]["error"] == "stale_preview_version")
            check("snapshot:context_still_required", rows["superseded"]["error"] == "preview_superseded")
            check("snapshot:retry_keeps_original", rows["retry"]["state_seq"] == 3 and rows["retry"]["state_lag"] == 1)
            check("snapshot:actual_obstacle", rows["obstacle"]["obstacles"] == 1)
            check("snapshot:actual_baseline", rows["baseline"]["uses_baseline"] is True)
            for key, item in o["before"].items():check("readonly:" + key, raw(item, "before:" + key) == raw(o["after"][key], "after:" + key))
        elif case.startswith("entry_"):
            for label in ["playing", "baseline", "restored"]:
                value = o[label];query(value, value["raw_file"], case + ":" + label)
                check(case + ":" + label + ":snapshot_advisory", value["freshness"] == 1 and value["advisory"] is True and value["error"] == "")
            check(case + ":while_playing", o["playing"]["tick"] > 0 and o["playing"]["generation"] == 1001)
            check(case + ":stroke_baseline", o["baseline"]["uses_baseline"] is True)
            check(case + ":new_generation", o["restored"]["generation"] == 1002)
            image = Image.open(path.parent / "preview.png")
            check(case + ":actual_viewport_size", image.size == (1280, 720))
            details[case] = {"playing_seq": o["playing"]["state_seq"], "playing_tick": o["playing"]["tick"], "restore_seq": o["restored"]["state_seq"]}
    return {"pass": all(c["pass"] for c in checks), "checks": checks, "direct_checks": total,
            "details": details, "source_count": len(report["sources"]), "auditor_sha256": sha(Path(__file__)),
            "scope": "Actual query bytes, minimum/context policies, immutable physical fields and live frontend scoped snapshots. Preview stays advisory; no placement/latency/cost acceptance."}


if __name__ == "__main__":
    parser = argparse.ArgumentParser();parser.add_argument("folder", type=Path);args = parser.parse_args()
    folder = args.folder.resolve();target = folder / "audit.json"
    if target.exists():raise FileExistsError(target)
    result = audit(folder);target.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"pass": result["pass"], "checks": len(result["checks"]), "direct": result["direct_checks"], "sources": result["source_count"]}))
    raise SystemExit(0 if result["pass"] else 1)
