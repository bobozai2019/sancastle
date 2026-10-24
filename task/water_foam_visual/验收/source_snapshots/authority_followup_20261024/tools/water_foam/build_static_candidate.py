"""Reproducible periodic cellular foam and an isolated static-shape candidate."""
import hashlib
import argparse
import json
from pathlib import Path
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser()
parser.add_argument('--base-shader',type=Path)
args=parser.parse_args()
OUT=ROOT/'assets/water_foam'
OUT.mkdir(parents=True,exist_ok=True)
rng=np.random.default_rng(241024)
size=512
cells=6
yy,xx=np.mgrid[:size,:size].astype(np.float32)/size
nearest=np.full((size,size),np.inf)
second=nearest.copy()
for y in range(cells):
    for x in range(cells):
        cx=(x+0.18+0.64*rng.random())/cells
        cy=(y+0.18+0.64*rng.random())/cells
        dx=(xx-cx+0.5)%1.0-0.5
        dy=(yy-cy+0.5)%1.0-0.5
        distance=np.sqrt(dx*dx+dy*dy)*cells
        second=np.minimum(second,np.maximum(nearest,distance))
        nearest=np.minimum(nearest,distance)
ridge=np.exp(-np.square((second-nearest)/0.23))
noise=np.zeros_like(xx)
for frequency,weight in [(2,0.48),(5,0.27),(11,0.16),(23,0.09)]:
    noise+=weight*np.sin(2*np.pi*(frequency*xx+rng.random()))*np.cos(2*np.pi*(frequency*yy+rng.random()))
red=np.clip(0.16+ridge*0.64+noise*0.22,0,1)
green=np.clip(0.5+noise*0.48,0,1)
rgba=np.stack([red,green,np.zeros_like(red),np.ones_like(red)],axis=-1)
Image.fromarray(np.uint8(np.rint(rgba*255))).save(OUT/'foam_cells.png')
resource='res://assets/water_foam/foam_cells.png'
cache='res://.godot/imported/foam_cells.png-'+hashlib.md5(resource.encode()).hexdigest()+'.ctex'
(OUT/'foam_cells.png.import').write_text(f'''[remap]
importer="texture"
type="CompressedTexture2D"
path="{cache}"
metadata={{"vram_texture": false}}
[deps]
source_file="{resource}"
dest_files=["{cache}"]
[params]
compress/mode=0
compress/normal_map=2
mipmaps/generate=true
mipmaps/limit=-1
process/fix_alpha_border=false
process/premult_alpha=false
process/hdr_as_srgb=false
detect_3d/compress_to=0
''',encoding='utf-8')
base=ROOT/'assets/water_material_natural_candidate/async_rdc_water.gdshader'
if args.base_shader:base=args.base_shader.resolve()
elif 'uniform int foam_detail_mode' in base.read_text(encoding='utf-8'):
    base=ROOT/'task/water_foam_visual/验收/G4/before_integration/assets/water_material_natural_candidate/async_rdc_water.gdshader'
    assert base.is_file(),'Original shader snapshot missing; provide --base-shader'
shader=base.read_text(encoding='utf-8')
uniforms='''uniform int foam_detail_mode = 0;
uniform sampler2D foam_detail_texture : filter_linear_mipmap, repeat_enable;
uniform float foam_detail_scale_per_m = 1.0;
uniform float foam_hole_strength = 1.0;
'''
shader=shader.replace('uniform float natural_main_foam_gain = 1.0;', 'uniform float natural_main_foam_gain = 1.0;\n'+uniforms)
anchor='''    float coverage = clamp(texture(foam_state, uv).r, 0.0, 1.0);'''
assert shader.count(anchor)==1
shader=shader.replace(anchor,anchor+'''
    if (foam_detail_mode == 1) {
        // History defines existence. The texture opens holes as history fades.
        float detail = texture(foam_detail_texture, uv_m * foam_detail_scale_per_m).r;
        float threshold = mix(0.96, 0.22, pow(coverage, 0.65));
        float edge = max(fwidth(detail), 0.025);
        float broken = smoothstep(threshold - edge, threshold + edge, detail);
        float shape = mix(smoothstep(0.13, 0.62, coverage), broken,
            clamp(foam_hole_strength, 0.0, 1.0));
        return shape * smoothstep(0.0, 0.04, coverage) *
            smoothstep(wet_epsilon_m, 0.012, depth);
    }
''')
old='''            float white_fraction = prototype_whitewater(UV, uv_m, depth, t,
                prototype_crest_lift_v) * (test1_whitewater_gain * natural_main_foam_gain) *
                (prototype_crest_white_face ? 0.94 : 0.78);'''
new='''            float foam_coverage = prototype_whitewater(UV, uv_m, depth, t,
                prototype_crest_lift_v);
            float white_fraction = foam_coverage *
                (test1_whitewater_gain * natural_main_foam_gain) *
                (prototype_crest_white_face ? 0.94 : 0.78);'''
assert old in shader
shader=shader.replace(old,new)
old='''            prototype_apply_whitewater(ALBEDO, ALPHA, UV, uv_m, depth, t,
                prototype_crest_lift_v, SCREEN_UV, INV_PROJECTION_MATRIX, VERTEX.z);'''
assert shader.count(old)==1
shader=shader.replace(old,'''            if (foam_detail_mode == 1) {
                float foam_mix = clamp(white_fraction, 0.0, 1.0);
                ALBEDO = mix(ALBEDO, foam_tint, foam_mix);
                ALPHA = mix(ALPHA, 0.93, clamp(foam_coverage *
                    test1_whitewater_gain * natural_main_foam_gain, 0.0, 1.0));
                natural_glint_depth_gate *= 1.0 - foam_mix;
            } else {
'''+old+'''
            }''')
(OUT/'static_candidate.gdshader').write_text(shader,encoding='utf-8')
identity=dict(source_shader=base.relative_to(ROOT).as_posix(),source_sha256=hashlib.sha256(base.read_bytes()).hexdigest(),texture_sha256=hashlib.sha256((OUT/'foam_cells.png').read_bytes()).hexdigest(),seed=241024,size=[512,512],channels={'R':'periodic cellular edge threshold','G':'periodic multiscale variation','B':'unused','A':'opaque'},source='Self-generated numerical texture; no external image assets',max_rgba8_mip_bytes=1398100,stage='T01 static shape candidate; not a performance result')
(OUT/'generation.json').write_text(json.dumps(identity,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(identity,indent=2))
