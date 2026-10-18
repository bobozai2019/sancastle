"""Seal current batch/actual-dirty component evidence; this is not the full G5."""
import hashlib
import json
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT/"test_output/unified_edit_pipeline"
OUT = ROOT/"task/sandcastle_unified_edit_pipeline/验收/G5_批次与脏块组件.json"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def main():
    names = ["g5_joint_delivery07/run-manifest.json", "g5_joint_independent07/result.json", "g5_profiles_delivery07/run-manifest.json", "g5_profiles_independent07/result.json", "g5_water_independent07/result.json", "g5_spine_delivery07/run-manifest.json"]
    reports = {name: read(RAW/name) for name in names}
    assert all(r["pass"] for r in reports.values())
    manifests = [r for r in reports.values() if "sources" in r]
    source_sets = [{p.replace("\\", "/").removeprefix("res://"): h.lower() for p, h in m["sources"].items()} for m in manifests]
    common = set.intersection(*(set(s) for s in source_sets))
    runtime = sorted(p for p in common if p.startswith(("scripts/", "shaders/", "assets/", "scenes/")))
    drift = [p for p in runtime if len({s[p] for s in source_sets}) != 1 or sha(ROOT/p) != source_sets[0][p]]
    assert runtime and not drift, drift
    for m in manifests:
        assert not m["drift"]
        for r in m["runs"]:
            assert r["pass"] and sha(Path(r["result"])) == r["result_sha256"].lower()
            directory = Path(r["result"]).parent
            log = (directory/"stdout.txt").read_text(encoding="utf-8-sig")+(directory/"probe.log").read_text(encoding="utf-8-sig")
            assert "was leaked" not in log and "were leaked" not in log and "SCRIPT ERROR:" not in log and "\nERROR:" not in log
    fixtures = {r["case"] for r in reports[names[0]]["runs"]}
    assert fixtures == {"height_basic", "height_faults", "height_erosion", "height_flow", "height_batch"}
    snapshot_dir = RAW/"g5_component_sources07"
    snapshot_dir.mkdir(exist_ok=True)
    archive = snapshot_dir/"sources.zip"
    sources = {}
    for s in source_sets:
        for p, h in s.items():
            assert sha(ROOT/p) == h, p
            sources[p] = h
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as z:
        for p in sorted(sources):
            z.write(ROOT/p, p)
        z.writestr("source-index.json", json.dumps(sources, indent=2))
    with zipfile.ZipFile(archive) as z:
        assert z.testzip() is None
        assert all(hashlib.sha256(z.read(p)).hexdigest() == h for p, h in sources.items())
    result = {"role": "T05 batch/publication gate and actual dirty component progress, not full G5", "pass": True, "G5_complete": False, "complete_objectives": ["T05.1"], "total_completed": 21, "total_objectives": 36, "gpu_checks": {name.split('/')[0]: sum(r["checks"] for r in m["runs"]) for name, m in reports.items() if "runs" in m}, "independent_checks": {name.split('/')[0]: len(r["checks"]) for name, r in reports.items() if "checks" in r}, "common_pinned_runtime_sources": len(runtime), "runtime_sources": {p: source_sets[0][p] for p in runtime}, "source_drift": drift, "source_archive": {"path": str(archive), "sha256": sha(archive), "files": len(sources), "verify": "Zip CRC and each uncompressed member SHA256 match pinned sources"}, "reports": {name: {"path": str(RAW/name), "sha256": sha(RAW/name)} for name in names}, "verified": ["11 default profiles and 17 sequential/batched command equivalence on current runtime", "same-batch business rejection followed by valid command without CPU authorization", "mid-batch revision fatal preserves valid predecessor authority, stops remaining commands, and leaves previous complete public view/stamp", "63 edits plus real coupled tick recorded as three work units while two height slots remain borrowed", "512 bounded terminal reservations, 513 cancellation/consumption exercise, exact backpressure and recovery", "all 64 native height maps and real physics ray", "actual corner/shared-edge dirtiness and borrowed newer versions", "non-bed/nochange/rejection does not rebuild collision", "coupled tick actual bed changes reach complete versioned collision", "exact-output unknown retry, malformed identity/size and nonfinite worker rejection, real last-consumer acknowledgements"], "pending": ["T05.2 cumulative stroke coverage beyond latest segment needs real height/dirty convergence verification", "T05.3 full preview/presentation consumer binding and complete-version validation", "T05.4 long open stroke with water fairness/queue age/height latency/recovery and further ownership boundaries", "G6 formal entries/restore/close/old path retirement", "G7 configuration-only extension and reachability audit", "G8 end-to-end visible cost/lifecycle/long-run"], "preserved_failures": ["g5_height_attempt01: function checks passed, inherited private compact reference leaked at exit; excluded for resource qualification", "g5_batch_delivery06: predecessor authority survives fatal but old unconditional publication also changed public view; fixed with post-seal GPU guarded publication", "g5_profiles_delivery04: D disk full, incomplete raw writes; own PID12140 terminated and run excluded", "g5_height_independent03: verifier requested uncaptured published_water key and exited, no report"], "storage": {"action": "Windows NTFS compact /C /S on this task generated evidence directory only; no file deletion or byte transformation", "files": 55242, "directories": 470, "logical_bytes": 23338971685, "allocated_bytes": 3812051864, "validation": "Current independent reports hash raw native files after compression; all prior paths preserved"}, "tool_sha256": sha(Path(__file__))}
    OUT.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"pass": True, "completed": "21/36", "runtime_sources": len(runtime), "archive_files": len(sources), "gpu_checks": result["gpu_checks"], "independent_checks": result["independent_checks"]}))


if __name__ == "__main__":
    main()
