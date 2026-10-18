"""Promote a verified extraction to fixed candidate assets; no formal cutover."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("evidence", type=Path)
    args = parser.parse_args()
    evidence = args.evidence.resolve()
    report = json.loads((evidence / "report.json").read_text("utf-8"))
    audit = json.loads((evidence / "audit.json").read_text("utf-8"))
    assert report["pass"] and audit["pass"]
    for key in ["main", "test1_capture", "test1_backwash", "test1_geometry"]:
        raw = evidence / (key + "_bake") / "bake.json"
        manifest = json.loads(raw.read_text("utf-8"))
        data = manifest["metadata"]
        for name, destination in [("scene", ROOT / f"scenes/unified_edit/presentation/{key}.tscn"),
                                  ("seed", ROOT / f"assets/unified_edit/presentation/{key}.variant")]:
            source = Path(data[name]["path"])
            assert sha(source) == data[name]["sha256"]
            if destination.exists():
                assert destination.read_bytes() == source.read_bytes(), destination
            else:
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source, destination)
            data[name]["path"] = "res://" + destination.relative_to(ROOT).as_posix()
        manifest["promotion"] = {"source_manifest": str(raw), "source_manifest_sha256": sha(raw),
                                 "source_report_sha256": sha(evidence / "report.json"),
                                 "scope": "Fixed candidate; UI and final cutover require separate validation"}
        target = ROOT / f"assets/unified_edit/presentation/{key}.json"
        payload = json.dumps(manifest, ensure_ascii=False, indent=2)
        if target.exists():
            assert target.read_text("utf-8") == payload, target
        else:
            target.write_text(payload, encoding="utf-8")
        lines = ['[gd_scene load_steps=4 format=3]',
                 f'[ext_resource type="PackedScene" path="res://scenes/unified_edit/presentation/{key}.tscn" id="1"]',
                 '[ext_resource type="Script" path="res://scripts/beach/unified_playable_entry.gd" id="2"]',
                 '[ext_resource type="Script" path="res://scripts/beach/unified_performance_panel.gd" id="3"]',
                 '[node name="UnifiedBeach" instance=ExtResource("1")]',
                 'script = ExtResource("2")', f'scene_key = "{key}"',
                 f'presentation_manifest = "res://assets/unified_edit/presentation/{key}.json"',
                 '[node name="PerformancePanel" parent="Interface"]', 'script = ExtResource("3")']
        connections = [("GpuPlayerCamera", "look_started", ".", "_on_camera_look_started"),
                       ("Interface/ShapeBrushPanel", "tool_changed", ".", "_on_tool_changed"),
                       ("Interface/ShapeBrushPanel", "parameters_changed", ".", "_on_parameters_changed"),
                       ("Interface/PerformancePanel/Margin/Rows/Header/Sampling", "toggled", "Interface/PerformancePanel", "_on_sampling_toggled")]
        controls = "Interface/EditPanel/Margin/Controls/"
        connections.extend((controls + node, signal, ".", method) for node, signal, method in [
            ("Tools/DigTool", "pressed", "_on_dig_tool_pressed"), ("Tools/FillTool", "pressed", "_on_fill_tool_pressed"),
            ("DigAmount", "value_changed", "_on_dig_amount_changed"), ("FillAmount", "value_changed", "_on_fill_amount_changed"),
            ("WaveAmount", "value_changed", "_on_wave_amount_changed"), ("TriggerWave", "pressed", "_on_trigger_wave_pressed")])
        lines.extend(f'[connection signal="{signal}" from="{node}" to="{target_node}" method="{method}"]'
                     for node, signal, target_node, method in connections)
        target = ROOT / f"scenes/unified_edit/playable/{key}.tscn"
        target.parent.mkdir(parents=True, exist_ok=True)
        text = "\n\n".join(lines) + "\n"
        if target.exists():
            assert target.read_text("utf-8") == text, target
        else:
            target.write_text(text, encoding="utf-8")
        print(key, "promoted", flush=True)


if __name__ == "__main__":
    main()
