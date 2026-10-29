"""Owned engine shadow proxy variants; no production geometry modifications."""
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
assets=ROOT/'assets/water_material_natural_candidate'
scenes=ROOT/'scenes/water_material_natural_candidate'
p=json.loads((assets/'lighting_engine.json').read_text())
p.update(lighting_schema_version=3,shadow_proxy_mesh='res://assets/water_material_natural_candidate/shadow_grid257.res',
         shadow_proxy_enabled=True)
(assets/'lighting_proxy.json').write_text(json.dumps(p,indent=2),encoding='utf-8')
for name in ['lighting_engine','lighting_shadow_fixture']:
    text=(scenes/(name+'.tscn')).read_text()
    text=text.replace('load_steps=3','load_steps=4').replace('load_steps=5','load_steps=6')
    text=text.replace('[ext_resource type="Script"', '[ext_resource type="ArrayMesh" path="res://assets/water_material_natural_candidate/shadow_grid257.res" id="3_proxy"]\n[ext_resource type="Script"')
    text=text.replace('lighting_engine.json','lighting_proxy.json')
    text+='''

[node name="TerrainShadowProxy" type="MeshInstance3D" parent="."]
mesh = ExtResource("3_proxy")
cast_shadow = 3
custom_aabb = AABB(-16.1, -1, -16.1, 32.2, 3, 32.2)
'''
    (scenes/(name+'_proxy.tscn')).write_text(text,encoding='utf-8')
print('Proxy scenes/profile schema3 generated; adoption requires shadow and cost comparison')
