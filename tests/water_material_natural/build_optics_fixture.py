"""Save the existing visual-only caster fixture with the optics entry."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
s=ROOT/'scenes/water_material_natural_candidate'
scene=(s/'lighting_shadow_fixture.tscn').read_text().replace('lighting_entry.gd','optics_entry.gd').replace(
    'lighting_profile_path = "res://assets/water_material_natural_candidate/lighting_engine.json"',
    'optics_profile_path = "res://assets/water_material_natural_candidate/optics_reconstructed.json"')
(s/'optics_depth_fixture.tscn').write_text(scene,encoding='utf-8')
