"""Seal the full candidate G5; formal entries/lifecycle and cost remain G6–G8."""
import hashlib
import json
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT/"test_output/unified_edit_pipeline"
OUT = ROOT/"task/sandcastle_unified_edit_pipeline/验收/G5_联合门.json"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def main():
    names = ["g5_views_delivery09/run-manifest.json", "g5_views_independent09/result.json", "g5_height_joint06/run-manifest.json", "g5_height_independent06/result.json", "g5_profiles_delivery06/run-manifest.json", "g5_profiles_independent06/result.json", "g5_water_independent06/result.json", "g5_spine_delivery06/run-manifest.json"]
    reports = {name: read(RAW/name) for name in names}
    assert all(r["pass"] for r in reports.values())
    manifests = {name: r for name, r in reports.items() if "sources" in r}
    sets = [{p.replace("\\", "/").removeprefix("res://"): h.lower() for p, h in m["sources"].items()} for m in manifests.values()]
    common = set.intersection(*(set(s) for s in sets))
    runtime = sorted(p for p in common if p.startswith(("scripts/", "shaders/", "assets/", "scenes/")))
    drift = [p for p in runtime if len({s[p] for s in sets}) != 1 or sha(ROOT/p) != sets[0][p]]
    assert runtime and not drift, drift
    sources = {}
    for mapping in sets:
        for p, h in mapping.items():
            assert sha(ROOT/p) == h, p
            sources[p] = h
    for name in ("build_g5_gate.py", "run_gpu_contract.ps1", "verify_views.py", "verify_height.py", "verify_profiles.py", "verify_water_response.py", "seal_run_sources.py"):
        p = "tools/unified_edit_pipeline/"+name
        sources[p] = sha(ROOT/p)
    for name, manifest in manifests.items():
        assert not manifest["drift"]
        for run in manifest["runs"]:
            assert run["pass"] and sha(Path(run["result"])) == run["result_sha256"].lower()
            parent = Path(run["result"]).parent
            log = (parent/"probe.log").read_text(encoding="utf-8-sig")+(parent/"stdout.txt").read_text(encoding="utf-8-sig")
            assert "SCRIPT ERROR:" not in log and "\nERROR:" not in log and "was leaked" not in log and "were leaked" not in log
    snapshot = RAW/"g5_final_sources09"
    snapshot.mkdir(exist_ok=True)
    archive = snapshot/"sources.zip"
    if archive.exists():
        raise SystemExit("Fresh source archive required")
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as z:
        for p in sorted(sources):z.write(ROOT/p, p)
        z.writestr("source-index.json", json.dumps(sources, indent=2))
    with zipfile.ZipFile(archive) as z:
        assert z.testzip() is None and all(hashlib.sha256(z.read(p)).hexdigest() == h for p, h in sources.items())
    views = read(RAW/"g5_views_delivery09/views_core/probe.json")
    half = views["observations"]["half_initialization"]
    assert half["godot_encode_half_bits"] == 0 and half["native_fixture_bits"] == 1
    result = {"role": "Complete candidate G5 batch/dirty/height/preview/presentation gate; not formal entry or final cost gate", "pass": True, "G5_complete": True, "complete_objectives": ["T05.1", "T05.2", "T05.3", "T05.4"], "total_completed": 24, "total_objectives": 36, "gpu_checks": {name.split('/')[0]: sum(r["checks"] for r in m["runs"]) for name, m in manifests.items()}, "independent_checks": {name.split('/')[0]: len(r["checks"]) for name, r in reports.items() if "checks" in r}, "common_pinned_runtime_sources": len(runtime), "runtime_sources": {p: sets[0][p] for p in runtime}, "source_drift": drift, "source_archive": {"path": str(archive), "sha256": sha(archive), "files": len(sources)}, "reports": {name: {"path": str(RAW/name), "sha256": sha(RAW/name)} for name in names}, "consumer_proof": ["Candidate height/worker/physics complete native maps and real ray under bounded slots and late/unknown/invalid delivery", "Cumulative coverage changes outside latest rectangle reach correct dirty chunks and physics", "300 default-water3 samples/12 requested ticks while stroke open and physics temporarily held; queue/completion/observed-physics boundaries recorded", "One shared read-only presentation publication: material/momentum/sediment/flux/baseline/stroke plus existing sealed sand/water/clock and int64 stamp", "Three real ShaderMaterial consumers and actual RGBA8 pixel/native input comparison", "Independent disk/capsule/template footprint statistics, fixed-world/stroke-baseline policy and completed time", "Query captured GPU version may be ahead of CPU consumption; no CPU prediction of source version", "Superseded/stale/foreign-generation/closing query protection, exact-output unknown retry, destroyed callback receiver, real render-detach proof", "Fatal preserves last complete public render/preview fields while retaining valid predecessor authority commit", "Native publication preserves raw half subnormals and signed zero on this D3D12 device"], "known_followup": [{"id": "UEP-INIT-HALF-001", "scope": "T06 native checkpoint restoration/initialization", "fact": "On this Godot4.7.2 host, PackedByteArray.encode_half(2^-24) produces bits0; native bits1 can exist and the new view publisher preserves them. State.initialize currently uses encode_half, so native restoration must avoid this loss.", "confidence": "C3 direct CPU bits and native source/view byte checks", "evidence": "g5_views_delivery09/views_core/probe.json observations.half_initialization and native_half_subnormal_inputs_present"}], "preserved_failures": ["g5_views_boot01: GLSL reserved word active caused real shader compile failure; no initialization gate, probe exited with partial resource leaks; partial-initialization cleanup remains explicit G6 obligation", "g5_views_delivery08: expected half subnormal source was already zero because initialization encode_half flushed it; excluded. Replaced with explicit native-byte fixture plus valid no-change work publication; no byte equality tolerance widened", "Earlier G5 component/fatal-publication/disk-full failures remain unchanged in G5_结果.md"], "pending": ["G6 partial-init/restore/close/scene switch/formal three-entry wiring and old-path retirement", "G6 real enabled local-front/foam/gravel capability/settings integration", "G7 configuration-only expansion and reachable writer audit", "G8 final current-source joint functions/10 lifecycle rounds/3-minute visible mixed interaction and end-to-end cost"], "performance_scope": "Only candidate functional scheduling and CPU/observed physics diagnostics. Explicit tick cadence is not real-time pacing; visible material probe is diagnostic, not full main-render cost. Existing long-stroke completion latency remains and no final performance PASS is claimed.", "tool_sha256": sha(Path(__file__))}
    OUT.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"pass": True, "completed": "24/36", "runtime_sources": len(runtime), "source_archive_files": len(sources), "gpu_checks": result["gpu_checks"], "independent_checks": result["independent_checks"]}))


if __name__ == "__main__":main()
