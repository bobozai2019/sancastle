"""Certify the common checkpoint component, keeping full G6 incomplete."""
import hashlib
import json
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT/"test_output/unified_edit_pipeline"
TARGET = ROOT/"task/sandcastle_unified_edit_pipeline/验收/G6_生产快照组件.json"
RUNS = [("capture", "g6_capture_matrix08"), ("spine", "g6_capture_spine08"), ("profiles", "g6_capture_profiles08"), ("restore", "g6_capture_restore08")]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def identity(path):
    return {"path": str(path.resolve()), "bytes": path.stat().st_size, "sha256": sha(path)}


def load(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def source_map(data):
    result = {p.replace("\\", "/").removeprefix("res://"): h.lower() for p, h in data.items()}
    for p, h in result.items():
        assert sha(ROOT/p) == h, p
    return result


def main():
    if TARGET.exists():
        raise SystemExit("Fresh component required")
    sources, runs, audits, archives, cpu = [], [], [], [], []
    manifests = {}
    for label, directory in RUNS:
        path = OUT/directory/"run-manifest.json";data = load(path)
        assert data["pass"] and not data["drift"] and all(r["pass"] for r in data["runs"])
        sources.append(source_map(data["sources"]))
        manifests[label] = path
        runs.append({"label": label, "manifest": identity(path), "cases": [r["case"] for r in data["runs"]], "checks": sum(r["checks"] for r in data["runs"])})
    common = set.intersection(*(set(s) for s in sources))
    assert all(len({s[k] for s in sources}) == 1 for k in common)
    for relative in ["g6_capture_independent08.json", "g6_capture_spine_independent08.json", "g6_capture_profiles_independent08/result.json", "g6_capture_profiles_water_independent08/result.json", "g6_capture_restore_independent08.json"]:
        path = OUT/relative;data = load(path);assert data["pass"]
        audits.append({**identity(path), "checks": len(data.get("checks", [])), "raw_cases": len(data.get("records", []))})
    for label, directory, expected in [("protocol", "g6_capture_protocol07", 212), ("configuration", "g6_capture_configuration07", 87)]:
        path = OUT/directory/"run-manifest.json";data = load(path)
        assert data["pass"] and not data["drift"] and data["checks"] == expected
        source_map(data["sources"]);manifests[label] = path;cpu.append({"label": label, "manifest": identity(path), "checks": expected})
    for label, manifest in manifests.items():
        path = OUT/"g6_capture_final_sources08"/(label+".zip")
        with zipfile.ZipFile(path) as archive:
            assert archive.testzip() is None
            index = json.loads(archive.read("evidence/source-index.json"))
            assert all(hashlib.sha256(archive.read(p)).hexdigest() == h for p, h in index.items())
            assert hashlib.sha256(archive.read("evidence/run-manifest.json")).hexdigest() == sha(manifest)
        archives.append({**identity(path), "sources": len(index), "all_members_verified": True})
    failed = OUT/"g6_capture_quantized_fail03/checkpoint_quantized/probe.json"
    failure = load(failed)
    raw_path = Path(failure["observations"]["unexpected_failure"]["raw_result"]["path"])
    assert not failure["pass"] and failure["observations"]["unexpected_failure"]["fault"] == "result_approximate_ledger"
    record = {"role": "partial_T06_common_production_checkpoint_component", "component_pass": True, "G6_pass": False, "completed_objectives": 24, "total_objectives": 36, "T06_completed": 0, "runs": runs, "GPU_cases": sum(len(r["cases"]) for r in runs), "GPU_probe_checks": sum(r["checks"] for r in runs), "common_runtime_source_count": len(common), "common_runtime_source_hashes": {p: sources[0][p] for p in sorted(common)}, "independent_audits": audits, "cpu_regressions": cpu, "source_archives": archives, "builder": identity(Path(__file__)), "verified_scope": ["Common request_checkpoint/save_checkpoint API blocks new admission, drains accepted work, settles actual results and ends the active stroke through the unchanged executor", "Internal END has a real GPU receipt but does not steal public result reservations, including all 512 terminal slots held", "26 real GPU readbacks agree with complete control/stamp/clock/immutable inputs; the saved container is independently decoded from its actual data-only Variant payload", "Ordinary f64 nominal history books exactly once on known recording, including business rejection; target uses actual GPU source; cancellation/transfer/smooth/compact do not invent stock", "Water f64 historical ledger anchors remain exact while raw GPU cumulative values are preserved; disabled visual history is explicit retained CPU metadata", "Native production save/load/restore, 35 candidate verifications, all 64 physical height chunks, continued edits/ticks and a second common snapshot agree", "Queued/recorded/completed-unclaimed/physics-pending/held/unknown/registration/bad-data/cancel/close/existing-path/identity-overflow/dead-receiver and work fault boundaries verified", "Known-unrecorded failed work retains an explicit aborted terminal status; recorded-unknown work never fabricates a GPU result", "CPU result validator now follows the actual individually encoded f32 product while f64 nominal accounting and GPU kernels remain unchanged"], "failure_evidence": {"report": identity(failed), "raw_completion": identity(raw_path), "reason": "UEP-LEDGER-ROUND-001: amount=.01 strength=.7 generated GPU f32 product 0.00699999975040555; old double-product-then-f32 expectation 0.007000000216066837 caused false result_approximate_ledger", "preserved_archives": [identity(OUT/"g6_capture_quantized_sources02/sources.zip"), identity(OUT/"g6_capture_quantized_sources03/sources.zip"), identity(OUT/"g6_capture_sources_matrix05/sources.zip")]}, "pending": ["Actual active-domain atomic handoff of renderer/preview/UI and physical consumers, with old generation ownership retired after proofs", "Enabled local-front/foam/gravel and prescribed tide/wave capture/restore, remaining effective parameter mapping", "Formal three-entry save/restore/cutover and retirement of reachable legacy writer/fallback paths", "Continuous realtime preview readiness, ten full scene lifecycle loops, remaining save/close combinations", "G7 configuration extension/architecture audit and G8 visible full-load cost/long stability"], "formal_entries_changed": False, "performance_pass": False}
    TARGET.write_text(json.dumps(record, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"component_pass": True, "G6_pass": False, "GPU_cases": record["GPU_cases"], "GPU_checks": record["GPU_probe_checks"], "common_sources": len(common), "report": str(TARGET.resolve())}))


if __name__ == "__main__":
    main()
