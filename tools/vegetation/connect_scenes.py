"""Attach authored vegetation to each presentation and refresh its reviewed identities."""
import hashlib
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
SHADER='res://shaders/visual/vegetation.gdshader'
FIELDS={'vegetation_roots':'vegetation_roots','vegetation_motion':'vegetation_motion',
        'async_clock':'clock','water_state':'water'}
KINDS=('seagrass','kelp','shore_grass','dune_grass','red_algae','switch_grass','wheat_grass','yarrow','goldenrod')


def main():
    for key in ('main','test1_geometry'):
        scene=ROOT/f'scenes/unified_edit/presentation/{key}.tscn'
        text=scene.read_text(encoding='utf8')
        if '[node name="VegetationLayer"' not in text:
            at=text.index('[sub_resource')
            text=text[:at]+'[ext_resource type="PackedScene" path="res://scenes/components/vegetation_layer.tscn" id="vegetation_layer"]\n\n'+text[at:]
            text+='\n[node name="VegetationLayer" parent="." instance=ExtResource("vegetation_layer")]\n'
            scene.write_text(text,encoding='utf8',newline='\n')
        manifest=ROOT/f'assets/unified_edit/presentation/{key}.json'
        document=json.loads(manifest.read_text(encoding='utf8'))
        meta=document['metadata']
        meta['materials']=[m for m in meta['materials'] if m['shader']!=SHADER]
        meta['bindings']=[b for b in meta['bindings'] if not b['path'].startswith('VegetationLayer/')]
        for kind in KINDS:
            material_id=len(meta['materials'])
            meta['materials'].append(dict(shader=SHADER,shader_sha256=hashlib.sha256((ROOT/SHADER[6:]).read_bytes()).hexdigest(),fields=FIELDS.copy()))
            meta['bindings'].append(dict(path=f'VegetationLayer/{kind}:material_override',material_id=material_id))
        meta['scene']['sha256']=hashlib.sha256(scene.read_bytes()).hexdigest()
        for material in meta['materials']:
            if material['shader']==SHADER:
                material['id']=meta['materials'].index(material)
                kind=material['id']-next(i for i,m in enumerate(meta['materials']) if m['shader']==SHADER)
                material['parameters']={'kind':kind,'seed':62143,'atlas_grid':json.loads((ROOT/f'assets/vegetation/competitor/{KINDS[kind]}_proxy.json').read_text())['atlas_grid'],
                                        'material_resource':'res://assets/vegetation/'+KINDS[kind]+'_material.tres'}
                material['shader_sha256']=hashlib.sha256((ROOT/SHADER[6:]).read_bytes()).hexdigest()
        manifest.write_text(json.dumps(document,ensure_ascii=False,indent=2)+'\n',encoding='utf8',newline='\n')
        print(key,'vegetation bindings',sum(m['shader']==SHADER for m in meta['materials']))


if __name__=='__main__':
    main()
