"""Create pre-candidate interface values from checked release and runtime normal."""
import hashlib
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
out=ROOT/'test_output/water_material_natural/t00_interface'
out.mkdir(parents=True,exist_ok=True)
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
normal=ROOT/'test_output/water_material_natural/t00_normal_recovery/normal_681_mip0.png'
base=ROOT/'assets/test1_beach/test1_beach_release.json'
profile={'candidate_schema_version':1,'profile_id':'water_material_natural_v1',
         'base_profile':'res://assets/test1_beach/test1_beach_release.json','base_profile_sha256':sha(base),
         'normal_detail':{'mode':'legacy_sine','texture':'res://test_output/water_material_natural/t00_normal_recovery/normal_681_mip0.png',
                          'texture_sha256':sha(normal),'channels':'raw_rg_signed_xz','sampler':'linear_mipmap_repeat_no_srgb',
                          'layers':[{'scale_per_m':.18,'direction_xz':[1.,0.],'speed_m_s':.035,'gain':.06},
                                    {'scale_per_m':.47,'direction_xz':[.6,.8],'speed_m_s':-.022,'gain':.025}]},
         'cost_budget':{'median_frame_relative_max':1.10,'p95_frame_relative_max':1.15,'window_s':60,'viewport_px':[1920,1080]},
         'deferred_interfaces':['lighting','optics','foam','reflection','caustics']}
(out/'candidate_interface_v1.json').write_text(json.dumps(profile,indent=2),encoding='utf-8')
from validate_candidate import validate
negative=[]
for name,modify in [('bad_version',lambda p:p.update(candidate_schema_version=99)),
                    ('bad_hash',lambda p:p.update(base_profile_sha256='0'*64)),
                    ('bad_mode',lambda p:p['normal_detail'].update(mode='placeholder')),
                    ('bad_range',lambda p:p['normal_detail']['layers'][0].update(gain=-1)),
                    ('bad_direction',lambda p:p['normal_detail']['layers'][0].update(direction_xz=[0,0]))]:
    test=json.loads(json.dumps(profile));modify(test)
    try: validate(test);negative.append({'case':name,'rejected':False})
    except ValueError as error: negative.append({'case':name,'rejected':True,'code':str(error)})
result={'pass':validate(profile)['ok'] and all(n['rejected'] for n in negative),'negative_cases':negative,
        'profile_sha256':sha(out/'candidate_interface_v1.json'),
        'status':'interface only; no candidate runtime or visual gate claimed',
        'normal_decode':'Godot adaptation: RG mapped to signed world XZ slope, not asserted original formula',
        'normal_coordinates':'cycles per metre in local XZ, rotation via unit direction; advection metres per second; time=completed_tick/30',
        'cost_budget_basis':'pre-candidate acceptance cap: median +10%, p95 +15%; same hardware/full load, 60s each; cold compile separate'}
(out/'validation.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps(result))
