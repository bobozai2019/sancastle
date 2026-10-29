"""Aggregate immutable G4 evidence without rewriting component results."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT/"test_output/unified_edit_pipeline"
OUT = ROOT/"task/sandcastle_unified_edit_pipeline/验收/G4_联合门.json"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def main():
    artifacts = ["g3_profiles_delivery08/run-manifest.json", "g3_profiles_regression08/run-manifest.json", "g3_profiles_suspended08/run-manifest.json", "g3_profiles_basic08/run-manifest.json", "g3_profiles_independent09/result.json", "g3_profiles_target_reference08/result.json", "g3_profiles_transfer_reference08/result.json", "g3_profiles_local_reference08/result.json", "g3_profiles_suspended_reference08/result.json", "g4_response_independent09/result.json", "g4_edges_attempt01/run-manifest.json", "g4_edges_independent02/result.json", "g4_audit_cost_delivery02/run-manifest.json", "g4_audit_cost_independent02/result.json"]
    records = {name: read(RAW/name) for name in artifacts}
    assert all(record["pass"] for record in records.values())
    manifests = [r for r in records.values() if "sources" in r]
    normalized = [{str(k).replace("\\", "/").removeprefix("res://"): v.lower() for k, v in m["sources"].items()} for m in manifests]
    common = set.intersection(*(set(m) for m in normalized))
    runtime = sorted(p for p in common if p.startswith(("scripts/", "shaders/", "assets/")))
    assert runtime
    drift = [p for p in runtime if len({m[p] for m in normalized}) != 1 or digest(ROOT/p) != normalized[0][p]]
    assert not drift, drift
    for manifest in manifests:
        assert not manifest["drift"]
        if "runs" in manifest:
            for run in manifest["runs"]:
                assert run["pass"] and digest(Path(run["result"])) == run["result_sha256"].lower()
        else:
            assert digest(Path(manifest["result"])) == manifest["result_sha256"].lower()
    edge = records["g4_edges_attempt01/run-manifest.json"]
    cost = records["g4_audit_cost_independent02/result.json"]
    result = {"role": "G4 shared material/water/validation/conditional-commit gate; candidate backend only", "pass": True, "T04_complete": True, "objectives": ["T04.1", "T04.2", "T04.3", "T04.4"], "total_completed": 20, "total_objectives": 36, "functional": {"initial_water_cases": 11, "initial_water_gpu_checks": 385, "edge_cases": len(edge["runs"]), "edge_gpu_checks": sum(r["checks"] for r in edge["runs"]), "independent_initial_checks": len(records["g4_response_independent09/result.json"]["checks"]), "independent_edge_checks": len(records["g4_edges_independent02/result.json"]["checks"]), "coverage": ["policies0/1/2/3", "volume add/remove and target/transfer mixed bed changes", "dry/partial/split/obstacle/sealed/capacity/packed fallback", "plain/molded/preserve/material-reference/NaN/unused fields", "native water/sediment conservation with frozen budgets", "actual union fields/count/dirty/bounds", "atomic known rejection and successful successor", "momentum-only revision and INT64_MAX actual fatal without authority writes"]}, "stage_cost": {"run": "g4_audit_cost_delivery02", "independent_checks": len(cost["checks"]), "fixtures": 6, "warmup_pairs": 24, "measured_pairs": 144, "statistics": cost["statistics"], "scope": cost["scope"], "runtime": cost["runtime"]}, "common_pinned_runtime_sources": len(runtime), "runtime_sources": {p: normalized[0][p] for p in runtime}, "source_drift": drift, "reports": {name: {"path": str(RAW/name), "sha256": digest(RAW/name)} for name in artifacts}, "authority_writers": [{"source": "scripts/simulation/unified_edit/edit.glsl", "mode": 7, "fields": "bed/suspended/material/baseline/coverage", "guard": "decision/control validated before write"}, {"source": "scripts/simulation/unified_edit/water_response.glsl", "mode": 4, "fields": "water/suspended/qx/qz twin images", "guard": "same decision/control and actual nonzero union change"}, {"source": "scripts/simulation/unified_edit/edit.glsl", "mode": 8, "fields": "public result and authority revision", "guard": "APPLIED actual change, verified counter headroom"}], "preserved_failures": ["g4_audit_cost_attempt01: stage samples present but cross-owner uniform-set cleanup error; run rejected", "g4_edges_independent01: verifier used incorrect result key and exited; no report", "G4 initial numerical/reference failures remain documented in G4_结果.md"], "pending": ["G5 batch/dirty/asynchronous consumers", "G6 lifecycle/restore/formal entries/old path retirement", "G7 config-only expansion and reachability audit", "G8 full functional/lifecycle/long-run/end-to-end visible cost"], "tool_sha256": digest(Path(__file__))}
    OUT.write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding="utf-8")
    print(json.dumps({"pass": True, "completed": "20/36", "common_pinned_runtime_sources": len(runtime), "edge_gpu_checks": result["functional"]["edge_gpu_checks"], "independent_checks": 1013+455+len(cost["checks"])}))


if __name__ == "__main__":
    main()
