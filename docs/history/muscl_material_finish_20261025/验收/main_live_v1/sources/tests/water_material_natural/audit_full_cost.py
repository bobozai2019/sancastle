import json,sys
from pathlib import Path
import numpy as np

def read(path):
    p=Path(path).resolve()
    r=json.loads((p/'process_result.json').read_text())
    m=json.loads((p/'manifest.json').read_text())
    d=json.loads((p/'full_cost.json').read_text())
    valid=(r['exit_code']==0 and r['engine_error_free'] and r['sources_unchanged_during_run']
           and r['exclusive_requested'] and not r['concurrent_godot_detected']
           and d['sampling_elapsed_us']>=60000000 and d['window_visible']
           and m['cameras']['close']['viewport_px']==[1920,1080]
           and d['vsync']==0 and d['render_scale']==1)
    assert valid, str(p)+' invalid full cost window'
    frames=np.asarray(d['frame_ms'])
    assert len(frames)==len(d['ticks']) and len(frames)>0
    stats={'samples':len(frames),'elapsed_s':d['sampling_elapsed_us']/1e6,
           'median_ms':float(np.median(frames)),'p95_ms':float(np.percentile(frames,95)),
           'max_ms':float(frames.max()),'completed_ticks':d['endpoint_tick']-d['start_tick'],
           'start_tick':d['start_tick'],'endpoint_tick':d['endpoint_tick'],
           'completed_ticks_per_wall_s':(d['endpoint_tick']-d['start_tick'])/(d['sampling_elapsed_us']/1e6),
           'gpu_render_median_ms':float(np.median(d['gpu_render_ms'])),
           'cpu_render_median_ms':float(np.median(d['cpu_render_ms']))}
    return p,d,stats

b,bd,bs=read(sys.argv[1]);c,cd,cs=read(sys.argv[2])
initial={k:bd['initial_fields'][k]['sha256']==cd['initial_fields'][k]['sha256'] for k in bd['initial_fields']}
input_keys=['start_tick','wave_workload','enable_erosion','edit_commands','render_scale','msaa','screen_aa','taa','vsync','adapter','driver']
inputs={k:bd[k]==cd[k] for k in input_keys}
# Requests include the same generation/domain identity for these fresh fixtures; record exact comparison.
inputs['wave_requests']=bd['wave_requests']==cd['wave_requests']
assert all(initial.values()) and all(inputs.values()), 'Initial authority or workload mismatch'
common={}
if (b/'common_restore_setup.json').exists() or (c/'common_restore_setup.json').exists():
    br=json.loads((b/'common_restore_setup.json').read_text());cr=json.loads((c/'common_restore_setup.json').read_text())
    common={'checkpoint_sha256_equal':br['checkpoint_sha256']==cr['checkpoint_sha256'],
            'physical_variant_unchanged_equal':br['physical_variant_hash_before']==br['physical_variant_hash_after']==cr['physical_variant_hash_before']==cr['physical_variant_hash_after']}
    assert all(common.values()), 'Common checkpoint physical input mismatch'
median=cs['median_ms']/bs['median_ms'];p95=cs['p95_ms']/bs['p95_ms']
result={'baseline':bs,'candidate':cs,'initial_authority_pairs':initial,'input_pairs':inputs,
        'common_checkpoint_pairs':common,'median_ratio':median,'p95_ratio':p95,'budget':{'median':1.10,'p95':1.15},
        'cost_budget_pass':median<=1.10 and p95<=1.15,
        'scope':'60 wall seconds each, full visible coupled scene with active simulation/repeated waves and no edit commands. Tick completion differences recorded; this is not equal endpoint-state or edit/restore acceptance. Formal artifact identity, interaction and final gate remain separate.'}
(c/'cost_pair_audit.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps(result))
