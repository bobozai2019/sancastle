"""Build the current native-candidate component; never certify the whole G6."""
import hashlib
import json
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT/"test_output/unified_edit_pipeline"
TARGET = ROOT/"task/sandcastle_unified_edit_pipeline/验收/G6_native候选恢复组件.json"
RUNS = [("native", "g6_restore_gpu07"), ("early", "g6_early_gpu02"), ("initialization", "g6_init_gpu03"), ("spine", "g6_restore_spine03"), ("coupled", "g6_restore_coupled02"), ("half", "g6_half_gpu05")]
AUDITS = ["g6_restore_independent07.json", "g6_early_independent02.json", "g6_init_independent03.json", "g6_restore_spine_independent03.json", "g6_restore_coupled_independent02/result.json", "g6_half_independent05.json"]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def identity(path):
    return {"path": str(path.resolve()), "bytes": path.stat().st_size, "sha256": sha(path)}


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def check_sources(sources):
    normalized = {k.replace("\\", "/").removeprefix("res://"): h.lower() for k, h in sources.items()}
    for path, expected in normalized.items():
        assert sha(ROOT/path) == expected, path
    return normalized


def main():
    if TARGET.exists():
        raise SystemExit("Fresh component required; keep prior evidence")
    runs, sources, archives, audits = [], [], [], []
    for label, directory in RUNS:
        path = OUT/directory/"run-manifest.json"
        data = read(path)
        assert data["pass"] and not data["drift"] and all(r["pass"] for r in data["runs"])
        sources.append(check_sources(data["sources"]))
        runs.append({"label": label, "manifest": identity(path), "cases": [r["case"] for r in data["runs"]], "checks": sum(r["checks"] for r in data["runs"])})
    common = set.intersection(*(set(s) for s in sources))
    assert all(len({s[k] for s in sources}) == 1 for k in common)
    for relative in AUDITS:
        path = OUT/relative;data = read(path);assert data["pass"]
        audits.append({**identity(path), "checks": len(data.get("checks", [])), "raw_cases": len(data.get("records", []))})
    configuration_path = OUT/"g6_restore_configuration02/run-manifest.json"
    configuration = read(configuration_path)
    assert configuration["pass"] and not configuration["drift"] and configuration["checks"] == 87
    check_sources(configuration["sources"])
    runtime_path = OUT/"g6_runtime_configuration02/probe.json"
    runtime = read(runtime_path)
    assert runtime["pass"] and len(runtime["checks"]) == 22
    check_sources(runtime["sources"])
    for label in [r[0] for r in RUNS]+["configuration"]:
        archive_path = OUT/"g6_restore_final_sources07"/(label+".zip")
        with zipfile.ZipFile(archive_path) as archive:
            assert archive.testzip() is None
            index = json.loads(archive.read("evidence/source-index.json"))
            assert all(hashlib.sha256(archive.read(p)).hexdigest() == h for p, h in index.items())
            manifest = configuration_path if label == "configuration" else next(OUT/d/"run-manifest.json" for k, d in RUNS if k == label)
            assert hashlib.sha256(archive.read("evidence/run-manifest.json")).hexdigest() == sha(manifest)
        archives.append({**identity(archive_path), "source_files": len(index), "members_verified": True})
    history = []
    for directory in ["g6_restore_gpu02", "g6_restore_diagnose03"]:
        path = OUT/directory/"run-manifest.json";data = read(path);assert not data["pass"]
        history.append({"manifest": identity(path), "status": "failed_preserved", "reason": "Idle dispatch/readback inside RD callback observed an old zero proof; second explicit main-to-render retry read serial 2. Original-domain fields stayed unchanged."})
    record = {"role": "partial_T06_native_candidate_component", "component_pass": True, "G6_pass": False, "completed_objectives": 24, "total_objectives": 36, "T06_completed": 0, "runs": runs, "GPU_cases": sum(len(r["cases"]) for r in runs), "GPU_probe_checks": sum(r["checks"] for r in runs), "common_runtime_sources": len(common), "common_runtime_source_hashes": {p: sources[0][p] for p in sorted(common)}, "independent_audits": audits, "configuration_data_regression": identity(configuration_path), "runtime_configuration_cpu": identity(runtime_path), "source_archives": archives, "history": history, "builder": identity(Path(__file__)), "verified_scope": ["Real GPU fields captured after two volume edits and one coupled water tick, real native container save/load, new-generation candidate initialization with 35 exact readbacks", "All current/spare physical fields, material support, actual control/time, published fields/stamp and read-only views verified; no legacy writer/query/rollback resources created", "Native half subnormals/signed zero and distinct spare f32 signed zero/subnormal fixture preserved", "Saved state_seq/tick/revision/clock and command highwater survive; four successful candidate cases build 64 same-version physical height chunks and complete a second edit/water tick", "Ordinary cohesion is frozen in environment, type/range checked and bound at actual push offset 28 separately from molded cohesion at offset 32; nondefault .025 steep-bed case matches uninterrupted continuation", "Held/duplicate/late callbacks cannot complete early; cancellation, corrupt/failed registration and unavailable cleanup proof preserve the current GPU domain", "Cleanup is scheduled through the main owner before render recording, all eight resource owners return to zero, early release/cancel cannot reopen via late initialize", "Related initialization, spine, coupled 1/64-step, native half and genuine old-format data regressions pass under pinned sources"], "pending": ["Production complete checkpoint capture/ledger settlement/stroke ending and formal save/restore APIs", "Atomic active-domain handoff to actual materials, preview/UI and physical consumers", "Enabled local-front, foam, gravel and prescribed boundary/wave restore; current unsupported capabilities remain explicit rejections", "Remaining simulation/environment coefficients and actual test1_geometry tide_mode3 geometry boundary mapping", "Queued/recorded/completed-unconsumed/physics-pending save-close boundaries, ten complete scene lifecycle loops and continuously advancing realtime preview readiness", "Formal three-entry cutover, retirement of legacy reachable writers/fallbacks, G7 extension audit and G8 full visible-load cost/long stability"], "formal_entries_changed": False, "performance_pass": False}
    TARGET.write_text(json.dumps(record, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"component_pass": True, "G6_pass": False, "GPU_cases": record["GPU_cases"], "GPU_checks": record["GPU_probe_checks"], "common_sources": len(common), "report": str(TARGET.resolve())}))


if __name__ == "__main__":
    main()
