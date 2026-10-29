"""Strengthen only the grazing caster coverage; retain the insufficient 4-pixel probe."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
scenes=ROOT/'scenes/water_material_natural_candidate'
text=(scenes/'lighting_shadow_fixture.tscn').read_text()
text=text.replace('load_steps=5','load_steps=6')
text=text.replace('[sub_resource type="StandardMaterial3D"', '[sub_resource type="BoxMesh" id="FoamShadowWideMesh"]\nsize = Vector3(2.2, 5, 1.8)\n\n[sub_resource type="StandardMaterial3D"')
index=text.index('[node name="FoamShadowOccluder"')
text=text[:index]+text[index:].replace('mesh = SubResource("ShadowBoxMesh")','mesh = SubResource("FoamShadowWideMesh")')
(scenes/'lighting_grazing_shadow_fixture.tscn').write_text(text,encoding='utf-8')
print('Only fine-foam caster width/depth strengthened for grazing diagnostic')
