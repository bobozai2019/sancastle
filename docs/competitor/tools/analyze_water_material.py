"""Audit replay exports and evaluate the traced captured water formula, without changing Godot."""
import hashlib,json,math,re,shutil
from pathlib import Path
import numpy as np
import PIL
from PIL import Image,ImageDraw

ROOT=Path(__file__).resolve().parents[3]
BASE=ROOT/'test_output/competitor_water_material_20261011'
OUT=BASE/'analysis_v1';OUT.mkdir(parents=True,exist_ok=True)
manifest_path=BASE/'replay_v5/manifest.json'
m=json.loads(manifest_path.read_text())
assert m['pass']
expected={
 'event_5006_ps.bin':'b7f1ac50d5312f20e829e8788a7256d4cc84266880fca4fdedc7d39f98148aa2',
 'event_6083_ps.bin':'6b7870c1b83924ba8a7319d3bae374933ecff0873caa5109f3c2e7d8338e9961',
 'event_6083_vs.bin':'19c2bc50402c753bc2a21061dd82d417edc5b450a1fe047018f20d67ecd8d45e',
 'event_5006_ps_cb0.bin':'862ce1a62c530cc861e838a0d49b98d8483b703b6a656c6057d785ca627cb270',
 'event_6083_ps_cb0.bin':'5b63864b00b7d71c4a73eba3fb246fb310ca0750b9b088e4474dc18ecf13a4a5',
 'event_6083_ps_cb1.bin':'363a0ee6883021561a7891f63b03a5c8f0715a9ff81804456f2019cb6b8a8401',
 'event_5006_ps_texture_1105_mip0.bin':'e5355399d7e4931291032ebd78d7b50dfe89cb7565dbda422f74e469769d3b0c',
 'event_6083_ps_texture_681_mip0.bin':'4ede635c60b57481df6fcfb08d1509868b3b1387116fbf864318eafb2716bb57'}
checks=[]
for e in m['exports']:
 p=Path(e['path']);h=hashlib.sha256(p.read_bytes()).hexdigest()
 checks.append({'path':e['path'],'index_hash_matches':h==e['sha256'],'historical_expected':expected.get(p.name),
                'historical_hash_matches':h==expected[p.name] if p.name in expected else None})
assert all(x['index_hash_matches'] and x['historical_hash_matches'] is not False for x in checks)
water=m['events'][1]['stages']['ps'];cb=water['constants'][0]['registers_float4']
tint=np.array(cb[131][:3]);sigma=np.array(cb[132][:3])*8.656170*math.log(2)
constants={str(i):cb[i][:3] for i in (121,123,125,131,132)}
constants['refraction']=water['constants'][1]['registers_float4'][0][0]
curpaths=['scenes/main.tscn','assets/water_material_natural_candidate/style_reference_v1.json',
 'assets/water_material_natural_candidate/reference_v1_bundle.json','assets/water_material_natural_candidate/water_route_specialized.gdshader',
 'assets/water_material_natural_candidate/bed_geometry_specialized.gdshader','assets/water_material_natural_candidate/optics_selected.json',
 'assets/water_material_natural_candidate/texture_layers.json','assets/water_material_natural_candidate/reflection_compiled_v1.json',
 'tests/visual_water_alignment/prototypes/caustic_fold_v1.png']
current=[]
for rel in curpaths:
 p=ROOT/rel;q=OUT/'current_source_snapshot'/(rel+'.source');q.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(p,q)
 current.append({'path':str(p),'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'snapshot':str(q)})
transmission=[{'formula_input_length':L,'competitor_multiplicative_rgb':(tint*np.exp(-sigma*L)).tolist(),
              'godot_exp_only_extinction_0_4':math.exp(-L/.4),
              'scope':'Equal numeric formula input only. Competitor units not calibrated to Godot meters; Godot shallow-preserve, lighting and reflection excluded.'}
             for L in (.05,.1,.2,.5,1.)]
fresnel=[{'cosine':c,'competitor_full_sun':.75*(1-c)**5,'competitor_shadow0':.1875*(1-c)**5,
          'current_godot':.025+.42*(1-c)**5} for c in (1.,.75,.5,.25,.1,0.)]
halfwidth={str(p):math.degrees(math.acos(.5**(1./p))) for p in (42,192,1500)}
pixels=json.loads((BASE/'pixel_v2/manifest.json').read_text());summaries=[]
for p in pixels['events'][1]['pixels']:
 regs={};at={}
 for s in p.get('states',[]):
  for change in s['changes']:
   a=change['after'];regs[a['name']]=a['f32'][:4]
  at[s['next_instruction']]={k:list(v) for k,v in regs.items()}
 if 118 not in at:continue
 def reg(after_instruction,name):return at[after_instruction+1][name]
 inputs={v['name']:v['f32'][:4] for v in p['inputs']}
 L=reg(70,'r0')[3];c=reg(81,'r0')[3];shadow=reg(101,'r1')[3];F=reg(105,'r0')[3]
 bed=np.array(reg(64,'r1')[:3]);T=np.array(reg(74,'r2')[:3]);H=reg(111,'r0')[0]
 output=np.array(reg(116,'o0')[:3]);alpha=reg(117,'o0')[3]
 normal=np.array(reg(41,'r0')[:3]);V=np.array(cb[6][:3])-np.array(inputs['v1'][:3]);V/=np.linalg.norm(V)
 predicted_F=.75*(1-c)**5*min(shadow+.25,1.)
 predicted=bed*(tint*np.exp(-sigma*L))*(.9+.2*c**6)*(1-predicted_F)+np.array(cb[121][:3])*predicted_F+np.array(cb[125][:3])*shadow*H**1500
 summaries.append({'pixel':[p['x'],p['y']],'inputs':inputs,'normal':normal.tolist(),'path_length':L,'scene_rgb':bed.tolist(),
                   'transmission_rgb':T.tolist(),'view_cosine':c,'shadow':shadow,'fresnel_weight':F,'half_vector_dot':H,
                   'sun_specular_scalar':H**1500,'output_rgb':output.tolist(),'alpha':alpha,
                   'reconstructed_rgb':predicted.tolist(),'max_formula_error':float(np.max(np.abs(predicted-output))),
                   'formula_F_error':abs(F-predicted_F)})
assert len(summaries)==3 and max(p['max_formula_error'] for p in summaries)<2e-6
raw=BASE/'replay_v5/event_5006_ps_texture_1105_mip0.bin'
volume=np.frombuffer(raw.read_bytes(),dtype=np.uint8).reshape(64,256,256)
board=Image.new('RGB',(3*276,2*292),(20,24,28));draw=ImageDraw.Draw(board)
for j,z in enumerate((0,8,16,24,32,48)):
 x=(j%3)*276+10;y=(j//3)*292+26
 board.paste(Image.fromarray(volume[z]).convert('RGB'),(x,y));draw.text((x,y-20),'R1105 mip0 / z='+str(z),fill='white')
board.save(OUT/'caustic_volume_slices.png')
caustic={'shape':[64,256,256],'raw_sha256':hashlib.sha256(raw.read_bytes()).hexdigest(),
 'adjacent_slice_correlation_mean':float(np.mean([np.corrcoef(volume[i].ravel(),volume[i+1].ravel())[0,1] for i in range(63)])),
 'first_last_slice_correlation':float(np.corrcoef(volume[0].ravel(),volume[-1].ravel())[0,1]),
 'scope':'Derived mip0 slices; not a time-stamped playback or ray-traced caustic generation proof.'}
result={'pass':True,'capture':m['sources'][0],'tool_version':m['tool']['version'],'export_checks':checks,
 'analysis_tool':{'script':str(Path(__file__).resolve()),'script_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                  'command':'C:/Python313/python.exe -X utf8 D:/godot/project/sandcastle/docs/competitor/tools/analyze_water_material.py',
                  'numpy':np.__version__,'pillow':PIL.__version__},
 'effective_constants':constants,'effective_sigma':sigma.tolist(),'transmission_examples':transmission,
 'fresnel_examples':fresnel,'specular_half_power_degrees':halfwidth,'pixel_formula_revalidation':summaries,
 'caustic_volume':caustic,'current_godot_sources':current,
 'failures':[{'run':'replay_v1','reason':'embedded Python has no __file__'},
 {'run':'replay_v2','reason':'capture backend D3D12, D3D11 state unavailable'},
 {'run':'replay_v3','reason':'generic enum traversal excessive; owned process terminated, partials retained, oversized cbuffer dump'},
 {'run':'pixel_v1','reason':'three requested pixels outside E6083 draw; empty traces do not validate values'}],
 'limits':['Single capture; no scene meters/time calibration.', 'Pixel samples belong to one E6083 patch and do not measure full-frame water appearance.',
           'No changes to runtime shaders, profiles, physics or task gates.']}
(OUT/'analysis.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps({'pass':True,'sigma':sigma.tolist(),'pixels':summaries,'caustic_volume':caustic,'halfwidth':halfwidth},indent=2))
