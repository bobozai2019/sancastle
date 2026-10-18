import argparse
import hashlib
import json
from pathlib import Path
import struct
import zipfile


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser();parser.add_argument("run", type=Path);args = parser.parse_args();folder = args.run.resolve()
    out = folder / "audit.json"
    if out.exists():raise SystemExit("Fresh audit output required")
    checks = []
    def check(name, value):checks.append({"name": name, "pass": bool(value)})
    report = json.loads((folder / "report.json").read_text("utf-8"))
    check("two_formal_cases", report["pass"] and {r["case"] for r in report["runs"]} == {"completion_main", "completion_test1_geometry"})
    with zipfile.ZipFile(report["source_zip"]) as z:
        check("zip_hash", sha(Path(report["source_zip"])) == report["source_zip_sha256"]);check("zip_crc", z.testzip() is None)
        for name, digest in report["sources"].items():check("source_" + name, hashlib.sha256(z.read(name.removeprefix("res://"))).hexdigest() == digest)
    for run in report["runs"]:
        name = run["case"];file = Path(run["evidence"]);data = json.loads(file.read_text("utf-8"));o = data["observations"]
        check(name + "_evidence", sha(file) == run["evidence_sha256"] and run["exit_code"] == 0 and run["clean_logs"] and data["pass"])
        raw = Path(o["raw"]["path"]).read_bytes();id = o["raw"]["identity"]
        check(name + "_raw_identity", sha(Path(o["raw"]["path"])) == o["raw"]["sha256"] and len(raw) == o["raw"]["bytes"] == 480)
        check(name + "_raw_header", struct.unpack_from("<4I", raw) == (0x31434555, 1, 96, 1))
        for key, offset in [("generation", 16), ("batch_seq", 24), ("lease_id", 32)]:check(name + "_raw_" + key, struct.unpack_from("<q", raw, offset)[0] == id[key])
        check(name + "_raw_first_publication", struct.unpack_from("<q", raw, 40)[0] == 1 and struct.unpack_from("<q", raw, 48)[0] == 0)
        a = o["arrivals"][:4]
        check(name + "_real_duplicate_out_of_order", len(a) == 4 and a[0] in [2, 3] and a[1] == a[0] and a[2] == 1 and a[3] in [2, 3] and a[3] != a[0])
        check(name + "_results_once", sorted(r["command_id"] for r in o["results"]) == [1, 2])
        check(name + "_original_epoch_results", all(r["generation"] == 1001 and r["outcome"] in [1, 2] for r in o["results"]))
        check(name + "_new_epoch_not_republished", o["current"]["generation"] == 1002 and o["current"]["state_seq"] == 3 and o["current"]["tick"] == 1)
        check(name + "_ledger_not_rebooked", o["current"]["ledger"] == o["ledger"])
    result = {"pass": all(x["pass"] for x in checks), "checks": checks,"auditor_sha256": sha(Path(__file__)), "scope": "Actual captured GPU completion header, duplicate/reordered delivery, epoch-isolated receipts and preserved ledger; not new physical formula/cost acceptance"}
    out.write_text(json.dumps(result, indent=2), encoding="utf-8");print("COMPLETION_AUDIT", result["pass"], "checks", len(checks));raise SystemExit(0 if result["pass"] else 1)


if __name__ == "__main__":main()
