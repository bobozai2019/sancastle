"""Strict versioned interface for the independently owned visual candidate."""
import hashlib
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

def resource(path, expected_hash):
    if not isinstance(path, str) or not path.startswith('res://') or '..' in path:
        raise ValueError('invalid_resource_path')
    resolved = (ROOT/path[6:]).resolve()
    if not resolved.is_relative_to(ROOT) or not resolved.is_file():
        raise ValueError('missing_resource')
    if hashlib.sha256(resolved.read_bytes()).hexdigest() != expected_hash:
        raise ValueError('resource_hash_mismatch')

def number(value, low, high):
    return type(value) in (int,float) and math.isfinite(value) and low <= value <= high

def validate(p):
    if p.get('candidate_schema_version') != 1 or p.get('profile_id') != 'water_material_natural_v1':
        raise ValueError('invalid_candidate_profile')
    if set(p) != {'candidate_schema_version','profile_id','base_profile','base_profile_sha256',
                  'normal_detail','cost_budget','deferred_interfaces'}:
        raise ValueError('invalid_candidate_fields')
    resource(p['base_profile'],p['base_profile_sha256'])
    n = p['normal_detail']
    if set(n) != {'mode','texture','texture_sha256','layers','channels','sampler'}:
        raise ValueError('invalid_normal_fields')
    if n['mode'] not in ('off','legacy_sine','texture_layers'):
        raise ValueError('invalid_normal_mode')
    if n['mode']=='texture_layers':
        resource(n['texture'],n['texture_sha256'])
    if n['channels'] != 'raw_rg_signed_xz' or n['sampler'] != 'linear_mipmap_repeat_no_srgb':
        raise ValueError('invalid_normal_decode')
    if not isinstance(n['layers'],list) or len(n['layers']) != 2:
        raise ValueError('invalid_normal_layers')
    for layer in n['layers']:
        if set(layer) != {'scale_per_m','direction_xz','speed_m_s','gain'}:
            raise ValueError('invalid_normal_layer_fields')
        if not number(layer['scale_per_m'],.001,4) or not number(layer['speed_m_s'],-2,2) or not number(layer['gain'],0,.5):
            raise ValueError('invalid_normal_layer_range')
        d=layer['direction_xz']
        if not isinstance(d,list) or len(d)!=2 or not all(number(x,-1,1) for x in d) or abs(sum(x*x for x in d)-1)>1e-4:
            raise ValueError('invalid_normal_direction')
    if p['cost_budget'] != {'median_frame_relative_max':1.10,'p95_frame_relative_max':1.15,'window_s':60,'viewport_px':[1920,1080]}:
        raise ValueError('invalid_cost_budget')
    if p['deferred_interfaces'] != ['lighting','optics','foam','reflection','caustics']:
        raise ValueError('unimplemented_interface')
    return {'ok':True,'schema':1}

if __name__ == '__main__':
    import sys
    print(json.dumps(validate(json.loads(Path(sys.argv[1]).read_text(encoding='utf-8')))))
