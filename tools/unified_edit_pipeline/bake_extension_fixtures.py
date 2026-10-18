"""Create-only original data fixtures. Does not change execution or product catalog."""
import hashlib
import json
from pathlib import Path
import math
import struct

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / "assets/unified_edit/extensions"


def main():
    DEST.mkdir(exist_ok=True)
    before = {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
              for p in (ROOT / "scripts/simulation/unified_edit").iterdir() if p.suffix in [".gd", ".glsl", ".glslinc"]}
    before["assets/unified_edit/default_catalog.tres"] = hashlib.sha256((ROOT / "assets/unified_edit/default_catalog.tres").read_bytes()).hexdigest()
    payload = bytearray()
    for z in range(65):
        for x in range(65):
            r = max(abs((x - 32) / 16), abs((z - 32) / 16))
            inside = r <= 1.7
            height = 0.2 + 0.8 * math.floor(max(0, 1 - r / 1.7) * 4) / 4 if inside else 0
            payload += struct.pack("<4f", height, float(inside), float(inside and r >= 1.3), 0)
    digest = hashlib.sha256(payload).hexdigest()
    files = {"stepped_mound_v1.rgba32f": bytes(payload)}
    files["stepped_mound_v1.tres"] = ('[gd_resource type="Resource" load_steps=2 format=3]\n'
        '[ext_resource type="Script" path="res://scripts/simulation/unified_edit/height_stamp.gd" id="1"]\n'
        '[resource]\nscript = ExtResource("1")\ntemplate_id = &"stepped_mound_v1"\n'
        'payload_path = "res://assets/unified_edit/extensions/stepped_mound_v1.rgba32f"\n'
        f'payload_sha256 = "{digest}"\n').encode()
    for old, new, replacements in [
        ("fill_v1", "wide_fill_v1", {'"amount_m3": 0.1': '"amount_m3": 0.16', '"radius_m": 0.75': '"radius_m": 1.5'}),
        ("castle_v1", "stepped_mound_tool_v1", {'res://assets/unified_edit/four_towers_v1.tres': 'res://assets/unified_edit/extensions/stepped_mound_v1.tres', '"height_m": 0.7': '"height_m": 0.85'}),
        ("shovel_v1", "wide_transfer_v1", {'"depth_m": 0.15': '"depth_m": 0.25', '"trench_width_m": 0.5': '"trench_width_m": 0.9', '"shoulder_width_m": 0.5': '"shoulder_width_m": 0.9', '"speed_m_s": 0.0': '"speed_m_s": 0.35'}),
    ]:
        text = (ROOT / f"assets/unified_edit/{old}.tres").read_text("utf-8")
        text = text.replace(f'profile_id = &"{old}"', f'profile_id = &"{new}"')
        for a, b in replacements.items():assert a in text;text = text.replace(a, b)
        files[new + ".tres"] = text.encode()
    catalog = (ROOT / "assets/unified_edit/default_catalog.tres").read_text("utf-8").replace('load_steps=13', 'load_steps=16')
    ext = ''.join(f'[ext_resource type="Resource" path="res://assets/unified_edit/extensions/{key}.tres" id="{i}"]\n' for i, key in enumerate(["wide_fill_v1", "stepped_mound_tool_v1", "wide_transfer_v1"], 13))
    catalog = catalog.replace('[resource]', ext + '[resource]').replace('ExtResource("12")])', 'ExtResource("12"), ExtResource("13"), ExtResource("14"), ExtResource("15")])')
    files["extension_catalog.tres"] = catalog.encode()
    files["fixture_identity.json"] = json.dumps({"schema": 1, "scope": "Original config-only G7 fixtures; fixed domain data defined by probe, no competitor resource", "core_before": before, "assets": {name: hashlib.sha256(data).hexdigest() for name, data in files.items()}, "template_algorithm": "65x65, spacing .0625m; square radius <=1.7m, 4-tier normalized mound; binary occupancy/rim and zero alpha"}, indent=2).encode()
    for name, data in files.items():
        path = DEST / name
        if path.exists():assert path.read_bytes() == data, "Existing fixture drift: " + name
        else:path.write_bytes(data)
    assert all(hashlib.sha256((ROOT / p).read_bytes()).hexdigest() == value for p, value in before.items())
    print("CONFIG_ONLY_FIXTURES", len(files), "core_unchanged", len(before))


if __name__ == "__main__":main()
