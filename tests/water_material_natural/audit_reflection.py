import json,sys
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw
p=Path(sys.argv[1]).resolve();d=json.loads((p/'reflection_cases.json').read_text());r=json.loads((p/'process_result.json').read_text())
assert r['exit_code']==0 and r['engine_error_free'] and r['sources_unchanged_during_run']
assert all(d['fields_unchanged'].values())
rows={}
for cam in ['close','oblique','grazing']:
    get=lambda c,n:np.asarray(Image.open(d['cases'][c]['images'][f'{n}_{cam}']['path']).convert('RGB')).astype(int)
    old=np.asarray(Image.open(p.parent/'t04_combination_v1'/f'all_on_{cam}.png').convert('RGB')).astype(int)
    labels=np.asarray(Image.open(p.parent/'t04_combination_v1'/f'depth_labels_{cam}.png').convert('RGB')).astype(int)
    water=(labels.max(2)>200)&(np.sort(labels,axis=2)[:,:,1]<20)
    flags=get('guarded',3);pert_flags=get('perturbed',3)
    protected_region=(flags[:,:,0]>200)|(flags[:,:,2]>1)
    guard_delta=np.abs(get('guarded',0)-get('legacy',0)).max(2)
    rows[cam]={'legacy_baseline_max_delta':int(np.abs(old-get('legacy',0)).max()),
        'zero_shift_max_delta':int(np.abs(get('guarded',0)-get('zero_shift',0)).max()),
        'zero_limit_max_delta':int(np.abs(get('guarded',0)-get('zero_limit',0)).max()),
        'guard_changed_pixels':int((guard_delta>1).sum()),
        'guard_changed_pixels_outside_flags':int(((guard_delta>1)&~protected_region).sum()),
        'base_invalid_pixels':int((water&(flags[:,:,0]>200)).sum()),
        'edge_fade_pixels':int((water&(flags[:,:,2]>1)).sum()),
        'perturb_reverted_pixels':int((water&(pert_flags[:,:,1]>200)).sum()),
        'perturb_production_changed_pixels':int((np.abs(get('guarded',0)-get('perturbed',0)).max(2)>1).sum()),
        'perturb_reflection_changed_pixels':int((water&(np.abs(get('guarded',4)-get('perturbed',4)).max(2)>1)).sum()),
        'detail_reflection_changed_pixels':int((water&(np.abs(get('detail_off',4)-get('perturbed',4)).max(2)>1)).sum()),
        'perturb_amplitude_nonzero_pixels':int((water&(get('perturbed',2).max(2)>1)).sum()),
        'zero_shift_amplitude_nonzero_pixels':int((water&(get('zero_shift',2).max(2)>1)).sum()),
        'zero_gain_production_changed_pixels':int((np.abs(get('zero_gain',0)-get('perturbed',0)).max(2)>1).sum())}
    board=Image.new('RGB',(1920,930),(24,24,24));draw=ImageDraw.Draw(board)
    for i,(case,debug) in enumerate([('legacy',0),('guarded',0),('perturbed',0),('zero_gain',0),
            ('guarded',4),('perturbed',4),('detail_off',4),('perturbed',2),
            ('guarded',3),('perturbed',3),('guarded',5),('perturbed',5)]):
        x=i%4*480;y=i//4*310
        board.paste(Image.fromarray(get(case,debug).astype(np.uint8)).resize((480,270)),(x,y+25))
        draw.text((x+5,y+5),f'{cam} {case} debug{debug}',fill='white')
    board.save(p/f'reflection_{cam}.png')
result={'cameras':rows,'baseline_equivalent':all(v['legacy_baseline_max_delta']<=1 for v in rows.values()),
    'zero_controls_equivalent':all(v['zero_shift_max_delta']<=1 and v['zero_limit_max_delta']<=1 and v['zero_shift_amplitude_nonzero_pixels']==0 for v in rows.values()),
    'guard_changes_localized':all(v['guard_changed_pixels_outside_flags']==0 for v in rows.values()),
    'guard_engaged':any(v['base_invalid_pixels']+v['edge_fade_pixels']>0 for v in rows.values()),
    'perturbation_engaged':all(v['perturb_reflection_changed_pixels']>0 and v['perturb_amplitude_nonzero_pixels']>0 for v in rows.values()),
    'detail_normals_consumed':all(v['detail_reflection_changed_pixels']>0 for v in rows.values()),
    'perturb_revert_engaged':any(v['perturb_reverted_pixels']>0 for v in rows.values()),
    'fields_unchanged':d['fields_unchanged'],'effective_reflection':d['effective_reflection'],
    'limits':'Fixed completed state and existing main cameras; foreground opaque fixture and final temporal/cost gates remain separate.'}
(p/'reflection_audit.json').write_text(json.dumps(result,indent=2));print(json.dumps({k:v for k,v in result.items() if k!='effective_reflection'}))
