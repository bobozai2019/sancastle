"""Build float fields from indexed capture; all source bytes remain in capture_v1."""
import json,hashlib
from pathlib import Path
import numpy as np
from model import load_inputs,OUT,DX,DT

ROOT=Path(__file__).resolve().parents[3]
ASSET=ROOT/'assets/test1_water_motion'
ASSET.mkdir(exist_ok=True)
state=np.load(OUT/'e6083/decoded.npy').astype('<f4')
flags,air,obs=load_inputs()
aux=np.stack([flags[:,:,0],flags[:,:,1],air,obs],axis=-1).astype('<f4')
state.tofile(ASSET/'capture_state.rgba32f')
aux.tofile(ASSET/'capture_aux.rgba32f')
index={'capture_manifest':'test_output/test1_water_motion/capture_v1/manifest.json',
 'source_sha256':'761aa980c2426f75a1fa7364bf6d2655ff4dd20ea76566e630ee5b53ea0ec5b2',
 'state_selector':'test1 E6083 VS ResourceId::139573 offset0 bytes2097152',
 'aux_selectors':['E1537 ResourceId::139573 bits28..31 and bits24..27 of uint3','E1537 ResourceId::139590 bytes8192, 32x16 stride16','E1537 ResourceId::139724 mip0 RG16F G channel'],
 'dimensions':[512,256], 'fields':['velocity_x','velocity_z','amount_with_0.05_bias','water_floor'],
 'aux_fields':['boundary_weight_uint4','local_source_uint4','sampled_air_field','obstacle_height'],
 'domain_origin':[-15,0,-7.5],'domain_extent':[30,10,15],
 'coordinate_adaptation':'Unity (x,y,z) -> Godot (x,y,-z). Scene-unit length preserved; physical meter calibration unknown.',
 'integration_dt':float(DT),'source_dt':.025,'substeps_per_capture':3,
 'default_temporal_adaptation':{'hold_s':2,'fall_s':4,'override_start':1.6163164377212524,'override_end':0,'clock_origin':284.71783447265625},
 'temporal_scope':'Kernel coefficients confirmed in captured frame. Parameter fall duration and future clock progression are Godot experimental adaptations; not recovered original time series.',
 'artifacts':[]}
for name in ['capture_state.rgba32f','capture_aux.rgba32f']:
 p=ASSET/name;index['artifacts'].append({'path':str(p),'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
(ASSET/'capture_profile.json').write_text(json.dumps(index,indent=2))
print(json.dumps(index,indent=2))
