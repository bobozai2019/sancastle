"""Author the fixed GPU splash pool/scene and reviewable material bindings offline."""
from pathlib import Path
import hashlib, json

ROOT=Path(__file__).resolve().parents[2]
SHADER='res://shaders/visual/shore_splash.gdshader'

def main():
    folder=ROOT/'assets/water_splash';folder.mkdir(exist_ok=True)
    transforms=', '.join(['1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0']*1024)
    (folder/'instances.tres').write_text('[gd_resource type="MultiMesh" load_steps=2 format=3]\n\n[sub_resource type="QuadMesh" id="drop"]\nsize = Vector2(1, 1)\n\n[resource]\ntransform_format = 1\nmesh = SubResource("drop")\ninstance_count = 1024\ncustom_aabb = AABB(-16, -2, -16, 32, 20, 32)\nbuffer = PackedFloat32Array('+transforms+')\n',encoding='utf-8')
    (ROOT/'scenes/components/shore_splash.tscn').write_text('[gd_scene load_steps=4 format=3]\n\n[ext_resource type="MultiMesh" path="res://assets/water_splash/instances.tres" id="pool"]\n[ext_resource type="Shader" path="'+SHADER+'" id="shader"]\n\n[sub_resource type="ShaderMaterial" id="material"]\nresource_local_to_scene = true\nrender_priority = 2\nshader = ExtResource("shader")\nshader_parameter/splash_visible = true\nshader_parameter/splash_size = 1.0\n\n[node name="ShoreSplash" type="MultiMeshInstance3D"]\nlayers = 5\ncast_shadow = 0\nmaterial_override = SubResource("material")\nmultimesh = ExtResource("pool")\n',encoding='utf-8')
    for key in ['main','test1_geometry']:
        p=ROOT/f'scenes/unified_edit/presentation/{key}.tscn'
        text=p.read_text('utf-8')
        if '[node name="ShoreSplash"' not in text:
            at=text.index('[sub_resource')
            text=text[:at]+'[ext_resource type="PackedScene" path="res://scenes/components/shore_splash.tscn" id="shore_splash"]\n\n'+text[at:]
            text+='\n[node name="ShoreSplash" parent="." instance=ExtResource("shore_splash")]\n'
            p.write_text(text,encoding='utf-8')
        mp=ROOT/f'assets/unified_edit/presentation/{key}.json'
        doc=json.loads(mp.read_text('utf-8'));meta=doc['metadata']
        if not any(m['shader']==SHADER for m in meta['materials']):
            i=len(meta['materials'])
            meta['materials'].append({'id':i,'shader':SHADER,'shader_sha256':'','fields':{'splash_position':'splash_position','splash_velocity':'splash_velocity'}})
            meta['bindings'].append({'path':'ShoreSplash:material_override','material_id':i})
        meta['scene']['sha256']=hashlib.sha256(p.read_bytes()).hexdigest()
        for material in meta['materials']:
            if material['shader']==SHADER:material['shader_sha256']=hashlib.sha256((ROOT/SHADER[6:]).read_bytes()).hexdigest()
        mp.write_text(json.dumps(doc,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        print(key,'authored shore splash binding')

if __name__=='__main__':main()
