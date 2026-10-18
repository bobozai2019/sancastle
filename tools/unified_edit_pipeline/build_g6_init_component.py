"""Seal the partial T06 initialization/half component, never the complete G6 gate."""
import hashlib
import json
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT/"test_output/unified_edit_pipeline"
TARGET = ROOT/"task/sandcastle_unified_edit_pipeline/验收/G6_初始化与原生half组件.json"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def identity(path):
    return {"path": str(path.resolve()), "bytes": path.stat().st_size, "sha256": sha(path)}


def main():
    if TARGET.exists():
        raise SystemExit("Fresh component required; preserve prior reports")
    runs, source_maps, archives = [], [], []
    for directory, label in [("g6_init_gpu02", "initialization"), ("g6_half_gpu04", "half"), ("g6_init_spine02", "spine"), ("g6_init_coupled01", "coupled")]:
        manifest_path = OUT/directory/"run-manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
        assert manifest["pass"] and not manifest["drift"] and all(r["pass"] for r in manifest["runs"])
        source_maps.append({p.replace("\\", "/"): h.lower() for p, h in manifest["sources"].items()})
        runs.append({"label": label, "manifest": identity(manifest_path), "cases": [r["case"] for r in manifest["runs"]], "checks": sum(r["checks"] for r in manifest["runs"])})
        archive_path = OUT/"g6_stage_sources02"/(label+".zip")
        with zipfile.ZipFile(archive_path) as archive:
            assert archive.testzip() is None
            sources = json.loads(archive.read("evidence/source-index.json"))
            assert all(hashlib.sha256(archive.read(p)).hexdigest() == digest for p, digest in sources.items())
            assert hashlib.sha256(archive.read("evidence/run-manifest.json")).hexdigest() == sha(manifest_path)
        archives.append({**identity(archive_path), "sources": len(sources), "all_member_hashes_checked": True})
    common = set.intersection(*(set(s) for s in source_maps))
    assert all(len({s[path] for s in source_maps}) == 1 for path in common)
    assert all(sha(ROOT/path) == expected for s in source_maps for path, expected in s.items())
    reports = []
    for relative in ["g6_half_cpu03/probe.json", "g6_half_independent04.json", "g6_init_independent02.json", "g6_init_spine_independent02.json", "g6_init_coupled_independent01/result.json"]:
        path = OUT/relative
        data = json.loads(path.read_text(encoding="utf-8-sig"))
        assert data["pass"]
        reports.append({**identity(path), "checks": len(data.get("checks", [])), "cases": len(data.get("records", []))})
    record = {"role": "partial_T06_component", "component_pass": True, "G6_pass": False, "completed_objectives": 24, "total_objectives": 36, "T06_completed": 0, "common_source_count": len(common), "common_source_hashes": {p: source_maps[0][p] for p in sorted(common)}, "runs": runs, "reports": reports, "archives": archives, "builder": identity(Path(__file__)), "verified_scope": ["15362 legal finite unit half codes including signed zero round-trip exactly; NumPy IEEE decoder matches all f32 bits", "10000 normal encodings retain existing host positive RTZ behavior; subnormal encoding and signed zero no longer flush", "Real GPU dual-authority and read-only view uploads preserve every native code before and after a legitimate NO_CHANGE publication", "Seven real initialization stages, partial state-field input failure, null/wrong domain and actual GLSL compiler rejection clean all eight nested RID owner groups", "GPU idle receipt validated as magic/reserved/int64 serial; unavailable proof retains every owner, ordinary release cannot bypass it, explicit retry cleans only after actual proof", "Original fault is retained; no fabricated command/work completion; repeated initialize cannot reallocate", "Affected normal/water/unknown/fatal/CFL and retained coupled numerical regressions pass; all owned probe processes terminal"], "pending": ["Complete validated native GPU checkpoint capture/restore, candidate verification and atomic domain/consumer swap", "Queued/recorded/result/physics/preview save-close boundaries and ten lifecycle loops", "Formal three entry wiring and retirement of reachable legacy writers/fallbacks", "Enabled local-front/foam/gravel, actual simulation/environment coefficients and preserved test1_geometry tide_mode3 boundary mapping", "Realtime preview readiness under continuously advancing ticks", "G7 configuration extension/architecture audit and G8 visible full-load performance/long stability"], "history": [{"path": str(OUT/"g6_half_cpu01"), "status": "failed", "reason": "First codec fix still lost signed zero through host encode_half; retained unchanged"}, {"path": str(OUT/"g6_half_gpu02"), "status": "passed_at_earlier_source", "reason": "Initial native half test; superseded by gpu04 with final cleanup ownership and receipt instrumentation"}], "performance_claim": False, "formal_entry_modified": False}
    TARGET.write_text(json.dumps(record, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"component_pass": True, "G6_pass": False, "common_sources": len(common), "GPU_checks": sum(r["checks"] for r in runs), "report": str(TARGET.resolve())}))


if __name__ == "__main__":
    main()
