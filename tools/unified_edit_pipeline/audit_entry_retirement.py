"""Formal bootstrap/old execution retirement certificate with fail-closed checks.

Checks the selected entry/controller construction boundary, not every possible
GDScript method or numerical writer. G7 retains its broader writer audit.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import zipfile

ROOT = Path(__file__).resolve().parents[2]
FILES = {
    "entry": "scripts/beach/unified_playable_entry.gd",
    "service": "scripts/beach/beach_scene_service.gd",
    "routes": "scripts/beach/unified_scene_routes.gd",
    "input": "scripts/simulation/unified_edit/player_input.gd",
    "runtime": "scripts/simulation/unified_edit/domain_runtime.gd",
    "pipeline": "scripts/simulation/unified_edit/pipeline.gd",
    "router": "scripts/simulation/unified_edit/checkpoint_router.gd",
    "legacy": "scripts/simulation/unified_edit/legacy_sources.gd",
    "adapter": "scripts/simulation/unified_edit/api_adapter.gd",
}


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def without_comments(text):
    # Keep string literals (paths/legacy selector names are relevant evidence).
    return "\n".join(line.split("#", 1)[0] for line in text.splitlines())


def rules(source):
    s = {k: without_comments(v) for k, v in source.items()}
    ctors = lambda value: re.findall(r"\b([A-Za-z_]\w*)\.new\s*\(", value)
    return {
        "entry_direct_node3d": s["entry"].startswith("extends Node3D"),
        "runtime_direct_node3d": s["runtime"].startswith("extends Node3D"),
        "entry_only_declaration_adapter_constructor": ctors(s["entry"]) == ["PlayerInput"],
        "runtime_only_two_unified_pipeline_constructors": ctors(s["runtime"]) == ["Pipeline", "Pipeline"],
        "input_no_executor_constructors": not ctors(s["input"]),
        "service_no_executor_constructors": not ctors(s["service"]),
        "router_only_data_inspector_constructor": ctors(s["router"]) == ["Legacy"],
        "legacy_reader_no_runtime_constructor": not ctors(s["legacy"]),
        "legacy_api_adapter_no_runtime_constructor": not ctors(s["adapter"]),
        "root_and_service_no_old_execution_switch": all("async_pipeline_enabled" not in s[k] and "edit_frame_pipeline_enabled" not in s[k] for k in ["entry", "service"]),
        "root_input_service_do_not_record_gpu": all("call_on_render_thread" not in s[k] and "RenderingDevice" not in s[k] for k in ["entry", "input", "service"]),
        "controllers_do_not_replace_script": all(not re.search(r"\bset_script\s*\(|\bGDScript\s*\.", s[k]) for k in ["entry", "runtime", "input", "service", "router", "legacy"]),
        "service_no_old_release_or_path_fallback": all(x not in s["service"] for x in ["_async_", "scene.solver", "collision_proxy", "else SCENES["]),
        "service_factory_gate": "scene.get_script().resource_path==ENTRY" in s["service"] and "not _unified_factory(scene)" in s["service"],
        "service_routes_through_current_family": "old.playable_scene_path(key)" in s["service"] and "old.playable_scene_path(old.scene_key)" in s["service"],
        "service_cache_is_family_scoped": 'scene.playable_scene_family()+":"+key' in s["service"],
        "runtime_pump_only_owned_unified_instances": all(x in s["runtime"] for x in ["current.pump()", "candidate.pump()", "pipeline.pump()"]),
        "pipeline_single_work_dispatch": all(x in s["pipeline"] for x in ["executor.record(input,control,output,count,commands)", "visuals.record_display(input,commands[0])", "water.record_tick(input,control,output,count,dt)"]),
        "legacy_api_converts_to_common_intent": "return submit_intent(adapted.request)" in s["pipeline"],
        "checkpoint_returns_data_projection": "return Codec.project_validated_legacy(inspected,configuration)" in s["router"],
        "old_recovery_only_static_validation": "Recovery.validate_gpu_checkpoint" in s["legacy"] and "Recovery.new" not in s["legacy"],
        "legacy_replay_not_invoked": all(x not in s[k] for k in ["router", "legacy"] for x in [".replay(", ".restore_gpu_checkpoint(", ".initialize_render("]),
        "unknown_family_has_no_route": 'if group=="formal"' in s["routes"] and 'if group=="candidate"' in s["routes"] and s["routes"].rstrip().endswith('return ""'),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--static", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args();folder = args.output.resolve();folder.mkdir(exist_ok=False)
    source = {key: (ROOT / name).read_text("utf-8-sig") for key, name in FILES.items()}
    checks = [{"name": k, "pass": bool(v)} for k, v in rules(source).items()]
    mutants = [
        ("legacy_root_base", "entry", lambda s: s.replace("extends Node3D", 'extends "res://scripts/beach/async_pipeline_entry.gd"', 1)),
        ("old_mode_switch", "service", lambda s: s + "\nvar async_pipeline_enabled=true\n"),
        ("second_writer", "runtime", lambda s: s + "\nvar extra=Legacy.new()\n"),
        ("ui_gpu_recording", "input", lambda s: s + "\nfunc bad():RenderingServer.call_on_render_thread(record)\n"),
        ("legacy_path_fallback", "service", lambda s: s + "\nfunc bad():return route if route else SCENES[key]\n"),
    ]
    for name, key, mutate in mutants:
        changed = source.copy();changed[key] = mutate(changed[key])
        checks.append({"name": "reject_mutant_" + name, "pass": not all(rules(changed).values())})
    static = json.loads((args.static / "audit.json").read_text("utf-8"))
    checks.append({"name": "actual_formal_nodes_audited", "pass": static["pass"] and len(static["entries"]) == 4})
    sources = {"res://" + name: sha(ROOT / name) for name in FILES.values()}
    # These are transitively used numerical owners or pure data boundaries;
    # preserve their actual identities rather than classify by old file names.
    for path in ["scripts/simulation/unified_edit/state.gd", "scripts/simulation/unified_edit/executor.gd",
                 "scripts/simulation/unified_edit/water.gd", "scripts/simulation/unified_edit/coupled.gd",
                 "scripts/simulation/unified_edit/height.gd", "scripts/simulation/unified_edit/views.gd",
                 "scripts/simulation/unified_edit/visuals.gd", "scripts/simulation/unified_edit/checkpoint_codec.gd",
                 "scripts/beach/beach_recovery_entry.gd", "scripts/simulation/brushes/brush_checkpoint_codec.gd",
                 "scripts/simulation/edit_validation/frame_pipeline/async_checkpoint_codec.gd",
                 "scripts/simulation/checkpoint_store.gd", "project.godot",
                 "addons/godotiq/godotiq_runtime.gd", "addons/godotiq/godotiq_runtime.gd.uid",
                 "tools/unified_edit_pipeline/audit_entry_retirement.py"]:
        sources["res://" + path] = sha(ROOT / path)
    result = {"pass": all(x["pass"] for x in checks), "checks": checks, "sources": sources,
              "scope": "Formal entry/controller construction and removed legacy execution selectors/fallback; bounded structural certificate plus actual nodes, not a general GDScript call-graph proof or the broader G7 writer audit",
              "data_only_legacy_references": ["async_checkpoint_codec.load/validate", "checkpoint_store.load/_validate", "beach_recovery_entry.validate_gpu_checkpoint", "gravel_checkpoint_codec.validate"],
              "tooling_boundary": "GodotIQ is the existing debugger autoload from the managed hub junction. Its debugger-message actions are development tools, not a gameplay fallback; no addon was changed.",
              "static_evidence_sha256": sha(args.static / "audit.json")}
    with zipfile.ZipFile(folder / "sources.zip", "x", zipfile.ZIP_DEFLATED) as z:
        for path, digest in sorted(sources.items()):z.write(ROOT / path.removeprefix("res://"), path.removeprefix("res://"))
        z.writestr("source-index.json", json.dumps(sources, indent=2))
    with zipfile.ZipFile(folder / "sources.zip") as z:
        assert z.testzip() is None
        assert all(hashlib.sha256(z.read(k.removeprefix("res://"))).hexdigest() == h for k, h in sources.items())
    result["source_zip_sha256"] = sha(folder / "sources.zip")
    (folder / "report.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    print("RETIREMENT_AUDIT", result["pass"], "checks", len(checks))
    raise SystemExit(0 if result["pass"] else 1)


if __name__ == "__main__":main()
