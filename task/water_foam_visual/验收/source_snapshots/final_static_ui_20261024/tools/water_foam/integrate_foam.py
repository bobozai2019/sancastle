"""Bake the verified profile into formal scenes; preserve exact pre-change sources."""
import argparse
import hashlib
import json
import re
import shutil
import subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
PROFILE=ROOT/'task/water_foam_visual/验收/G3/selected_profile.json'
parser=argparse.ArgumentParser()
parser.add_argument('--apply',action='store_true')
args=parser.parse_args()
if not PROFILE.is_file():raise SystemExit('G3 selected profile has not been frozen')
profile=json.loads(PROFILE.read_text(encoding='utf-8'))
if profile.get('validation_status')!='pass':raise SystemExit('G3 is not passed')
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
water=ROOT/'assets/water_material_natural_candidate/async_rdc_water.gdshader'
candidate=ROOT/'assets/water_foam/flow_candidate.gdshader'
texture=ROOT/'assets/water_foam/foam_cells_organic.png'
assert digest(water)==profile['base_water_sha256'],'Formal water changed; review before integration'
assert digest(candidate)==profile['candidate_sha256']
assert digest(texture)==profile['texture_sha256']
subprocess.run(['python','tools/validate_main_presentation_hash.py','--all'],cwd=ROOT,check=True)
scenes=[ROOT/f'scenes/unified_edit/presentation/{key}.tscn' for key in ['main','test1_geometry']]
manifests=[ROOT/f'assets/unified_edit/presentation/{key}.json' for key in ['main','test1_geometry']]
changes={}
def node_material(text,node):
    block=re.search(r'\[node name="'+node+r'"[^\n]*\]\r?\n(.*?)(?=\r?\n\[|\Z)',text,re.S)
    assert block,node
    return re.search(r'material_override = SubResource\("([^"]+)"\)',block[1])[1]
def update_material(text,identifier,values,eol):
    pattern=r'(\[sub_resource type="ShaderMaterial" id="'+re.escape(identifier)+r'"\]\r?\n)(.*?)(?=\r?\n\[|\Z)'
    match=re.search(pattern,text,re.S);assert match,identifier
    body=match[2]
    for name,value in values.items():
        key='shader_parameter/'+name
        body=re.sub(r'^'+re.escape(key)+r' = [^\r\n]*\r?\n?','',body,flags=re.M)
        body=body.rstrip()+eol+key+' = '+value+eol
    return text[:match.start()]+match[1]+body+text[match.end():]
for scene in scenes:
    text=scene.read_bytes().decode('utf-8')
    eol='\r\n' if '\r\n' in text else '\n'
    assert 'id="water_foam_detail"' not in text
    water_id=node_material(text,'GpuWaterSurface')
    contact_id=node_material(text,'ShoreContactOverlay')
    insertion=min(i for i in [text.find('[sub_resource'),text.find('[node')] if i>=0)
    ext='[ext_resource type="Texture2D" path="res://assets/water_foam/foam_detail.png" id="water_foam_detail"]'+eol+eol
    text=text[:insertion]+ext+text[insertion:]
    text=re.sub(r'load_steps=(\d+)',lambda m:'load_steps='+str(int(m[1])+1),text,count=1)
    text=update_material(text,water_id,{'foam_detail_mode':'1','foam_detail_texture':'ExtResource("water_foam_detail")','foam_detail_scale_per_m':'1.0','foam_hole_strength':'1.0','foam_flow_cycle_s':'4.0','foam_flow_gain':'1.0','foam_flow_speed_cap_m_s':'2.0','foam_flow_debug':'false'},eol)
    text=update_material(text,contact_id,{'natural_contact_gain':'0.55'},eol)
    changes[scene]=text.encode('utf-8')
print('Prepared static binding for:',*[p.relative_to(ROOT).as_posix() for p in changes])
if not args.apply:raise SystemExit(0)
final_texture=ROOT/'assets/water_foam/foam_detail.png'
assert not final_texture.exists(),'Final texture already exists; review before overwriting'
backup=ROOT/'task/water_foam_visual/验收/G4/before_integration'
if backup.exists():raise SystemExit('Existing integration backup; inspect instead of overwriting')
backup.mkdir(parents=True);(backup/'.gdignore').touch()
paths=[water,*scenes,*manifests,ROOT/'assets/parameters/catalog.json',ROOT/'scripts/simulation/unified_edit/presentation.gd',ROOT/'scripts/parameters/parameter_service.gd',ROOT/'assets/water_sides/water_sides.gdshader',ROOT/'assets/water_sides/geometry_manifest.json']
before={}
for path in paths:
    dest=backup/path.relative_to(ROOT);dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(path,dest)
    before[path.relative_to(ROOT).as_posix()]=digest(path)
(backup/'identity.json').write_text(json.dumps(before,indent=2),encoding='utf-8')
water.write_bytes(candidate.read_bytes())
shutil.copy2(texture,final_texture)
source_resource='res://assets/water_foam/foam_detail.png'
cache='res://.godot/imported/foam_detail.png-'+hashlib.md5(source_resource.encode()).hexdigest()+'.ctex'
import_text=texture.with_suffix('.png.import').read_text(encoding='utf-8')
import_text=re.sub(r'^uid=.*\n','',import_text,flags=re.M)
import_text=re.sub(r'res://\.godot/imported/foam_cells_organic\.png-[a-f0-9]+\.ctex',cache,import_text)
import_text=import_text.replace('res://assets/water_foam/foam_cells_organic.png',source_resource)
final_texture.with_suffix('.png.import').write_text(import_text,encoding='utf-8')
for path,data in changes.items():path.write_bytes(data)
subprocess.run(['python','tools/water_sides/build_shader.py'],cwd=ROOT,check=True)
for manifest in manifests:
    document=json.loads(manifest.read_text(encoding='utf-8-sig'))
    metadata=document['metadata']
    scene=ROOT/metadata['scene']['path'].removeprefix('res://')
    metadata['scene']['sha256']=digest(scene)
    for material in metadata['materials']:
        material['shader_sha256']=digest(ROOT/material['shader'].removeprefix('res://'))
    manifest.write_text(json.dumps(document,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
subprocess.run(['python','tools/validate_main_presentation_hash.py','--all'],cwd=ROOT,check=True)
print('Formal resources baked; import and lifecycle validation still required.')
