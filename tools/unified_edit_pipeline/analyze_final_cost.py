"""Independent paired cost integrity and frozen-guard judgment.

Integrity pass and performance acceptance are separate. Untagged old dispatches
are not fabricated as measured spans; tagged old edit sums are a lower bound.
"""
import argparse
from collections import defaultdict
import hashlib
import json
import math
from pathlib import Path
import re
import statistics
ROOT=Path(__file__).resolve().parents[2]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def summary(values):
    values=sorted(values)
    if not values:return {'n':0}
    return {'n':len(values),'p50':statistics.median(values),'p95':values[math.ceil(len(values)*.95)-1],'max':values[-1],'p99':values[math.ceil(len(values)*.99)-1] if len(values)>=1000 else None,'p99_reason':None if len(values)>=1000 else 'insufficient_input_frames'}
def normalized_command(value):
    return {k:v for k,v in value.items() if k not in {'command_id','generation','stroke_id','baseline_token','sim_tick'}}
def main():
    parser=argparse.ArgumentParser();parser.add_argument('run',type=Path);parser.add_argument('--pilot',action='store_true');parser.add_argument('--output',default='audit.json');args=parser.parse_args();folder=args.run.resolve();output=folder/args.output;assert not output.exists(),'Fresh audit required'
    checks=[];runs={};details={};pairs=[]
    def check(name,value):checks.append({'name':name,'pass':bool(value)})
    report=json.loads((folder/'report.json').read_text('utf-8'));check('runner_pass',report['pass'])
    guards=json.loads((ROOT/'task/sandcastle_unified_edit_pipeline/验收/G0_基线噪声与比较门.json').read_text('utf-8'))
    check('frozen_g0_guards',guards['pass'])
    for row in report['runs']:
        name=row['name'];path=Path(row['evidence']);d=json.loads(path.read_text('utf-8'));runs[(row['mode'],row['tool'],row['repeat'],row['family'])]=d
        check(name+':actual_exit',row['exit_code']==0 and row['clean_logs'] and d['pass'] and sha(path)==row['evidence_sha256'])
        initial=d['runtime']['initial_state'];check(name+':eleven_initial_fields',set(initial)=={'rock','obstacle','sand','water','sediment','momentum_x','momentum_z','wetness','compaction','mold_support','clock'})
        for field,item in initial.items():
            p=Path(item['path']);check(name+':initial:'+field,p.stat().st_size==item['bytes'] and sha(p)==item['sha256'])
        check(name+':twenty_four_declarations',len(d['commands'])==24)
        expected_ids={x['command']['command_id'] for x in d['commands']}
        actual_ids=[x['command']['command_id'] if row['family']=='old' else x['id'] for x in d['terminals']]
        check(name+':twenty_four_real_sample_terminals',sum(x in expected_ids for x in actual_ids)==24 and expected_ids<=set(actual_ids))
        completion_bounds=[]
        for terminal,identity in zip(d['terminals'],actual_ids):
            if identity in expected_ids:
                completion_bounds.append((terminal['observed_at_us']-terminal['admitted_at_us'])/1000)
                result=terminal['result']
                if row['family']=='current':
                    check(name+':real_gpu_result:'+str(identity),result.get('completion_phase')==1 and result.get('outcome') in [1,2] and result.get('invalid_flags')==0 and result.get('error_code')==0)
                else:
                    valid=result.get('gpu_complete') is True
                    if row['tool'] in ['wall','shovel']:valid=valid and result.get('status') in [1,2] and result.get('invalid_flags')==0 and result.get('error_code')==0
                    check(name+':real_gpu_result:'+str(identity),valid)
        if row['family']=='old' and row['tool'] in ['dig','fill']:check(name+':ordinary_gpu_aggregate_no_skips',d['witnesses']['accepted']==24 and d['witnesses']['rejected']==0)
        if row['family']=='current':
            for field,item in d['observations']['final_fields'].items():
                p=Path(item['path']);expected_bytes=4 if field=='clock' else (131072 if field in ['compaction','wetness'] else (524288 if field=='mold_support' else 262144))
                check(name+':complete_final_field:'+field,item['bytes']==expected_bytes and p.stat().st_size==expected_bytes and sha(p)==item['sha256'])
        check(name+':paused_actual_clock',d['input_open']['start_tick']==d['input_open']['end_tick']==0 and d['input_open']['start_time_s']==d['input_open']['end_time_s']==0)
        window=d['input_open'];frames=[x for x in d['frames'] if window['start_at_us']<=x['at_us']<=window['end_at_us']]
        frame_ms=[(b['at_us']-a['at_us'])/1000 for a,b in zip(frames,frames[1:])]
        check(name+':enough_complete_input_intervals',len(frame_ms)>=22)
        focus=sorted(set(x['window_focused'] for x in frames));maxfps=sorted(set(x['max_fps'] for x in frames));low=sorted(set(x['low_processor_usage'] for x in frames));sleep=sorted(set(x['low_processor_sleep_us'] for x in frames))
        gpu_by_label=defaultdict(list);tagged_total=0;tagged_count=0
        for frame in d['gpu_samples']:
            for span in frame['spans']:
                check(name+':nonnegative_timestamp:'+str(tagged_count),span['gpu_ns']>=0)
                label=span['label'];gpu_by_label[re.sub(r'\d+','N',label)].append(span['gpu_ns']/1e6)
                selected=label.startswith('uep_cost_edit_') if row['family']=='current' else span.get('group')=='edit'
                if selected:tagged_total+=span['gpu_ns'];tagged_count+=1
        if row['mode']=='detailed':check(name+':real_gpu_edit_markers',tagged_count>0)
        drained_at=d.get('witnesses',{}).get('drained_at_us',d['frames'][-1]['at_us'])
        details[name]={'input_frame_ms':summary(frame_ms),'input_window_ms':(window['end_at_us']-window['start_at_us'])/1000,'input_to_gpu_notification_upper_bound_ms':summary(completion_bounds),'input_end_to_all_consumers_drained_ms':(drained_at-window['end_at_us'])/1000,'drain_us':d.get('observations',{}).get('tail_us',d.get('witnesses',{}).get('tail_us')),'focus':focus,'max_fps':maxfps,'low_processor':low,'low_processor_sleep_us':sleep,'render_objects':sorted(set(x['render_objects'] for x in frames)),'render_primitives':sorted(set(x['render_primitives'] for x in frames)),'render_draw_calls':sorted(set(x['render_draw_calls'] for x in frames)),'gpu_markers_ms':{k:summary(v) for k,v in gpu_by_label.items()},'tagged_edit_gpu_total_ms':tagged_total/1e6,'tagged_edit_marker_count':tagged_count,'tagged_edit_gpu_ms_per_offered_command':tagged_total/1e6/24 if tagged_count else None,'note':'Old tagged edit sum omits untagged selection/capture work; current decorator measures the unchanged complete executor.record. Notification times are frame-quantized CPU upper bounds, not GPU durations or display scanout. New CPU records include observer metadata overhead; no total CPU gain is asserted.'}
    groups=sorted({key[:3] for key in runs})
    for mode,tool,repeat in groups:
        old=runs[(mode,tool,repeat,'old')];current=runs[(mode,tool,repeat,'current')];name=f'{mode}_{tool}_{repeat}'
        a=old['runtime'];b=current['runtime']
        check(name+':actual_inputs_equal',all(a['initial_state'][f]['sha256']==b['initial_state'][f]['sha256'] and Path(a['initial_state'][f]['path']).read_bytes()==Path(b['initial_state'][f]['path']).read_bytes() for f in a['initial_state']))
        check(name+':camera_equal',a['camera_transform']==b['camera_transform'])
        for field in ['adapter','driver','window','viewport','vsync','engine']:check(name+':same_'+field,a[field]==b[field])
        check(name+':same_grid_and_cell_size',a['effective_profile']['grid_size']==b['configuration']['grid_size'] and a['effective_profile']['cell_size_m']==b['configuration']['cell_size_m'])
        check(name+':semantic_commands_equal',[normalized_command(x['command']) for x in old['commands']]==[normalized_command(x['command']) for x in current['commands']])
        if tool in ['dig','fill']:check(name+':same_implicit_ordinary_water_and_speed',a['ordinary_request_policy']==b['presentation_settings']['water_policy'] and a['ordinary_request_speed_m_s']==b['presentation_settings']['signed_speed_m_s'])
        check(name+':actual_target_equal',old['target']==current['target'])
        flat=b['presentation_effective_profile'];visual=a['effective_profile']['visual']
        check(name+':all_common_visual_settings_equal',all(flat.get(k)==v for k,v in visual.items()))
        overlay=a.get('reference_render_overlay',{})
        # Packed current presentation flattens the authoring .tscn instance;
        # its actual mesh/shader/script/manifest remain consumed and hash-pinned.
        authoring='res://scenes/components/water_boundary_sides.tscn'
        check(name+':same_current_water_sides_overlay',len(overlay)==5 and authoring in overlay and sha(ROOT/authoring.removeprefix('res://'))==overlay[authoring] and all(b['configuration']['sources'].get(path)==digest for path,digest in overlay.items() if path!=authoring))
        left=details[f'{name}_old'];right=details[f'{name}_current']
        matched=all(left[k]==right[k] for k in ['focus','max_fps','low_processor','low_processor_sleep_us']) and left['focus']==[True]
        guard=guards['cases'][tool]['coarse_input_frame_p50' if mode=='coarse' else 'detailed_input_frame_p50']['guard_ms']
        delta=right['input_frame_ms']['p50']-left['input_frame_ms']['p50']
        pairs.append({'mode':mode,'tool':tool,'repeat':repeat,'conditions_matched':matched,'old_input_frame_p50_ms':left['input_frame_ms']['p50'],'current_input_frame_p50_ms':right['input_frame_ms']['p50'],'current_minus_old_ms':delta,'frozen_guard_ms':guard,'beyond_gain_guard':delta < -guard,'beyond_regression_guard':delta>guard,'old_tagged_gpu_ms_per_command':left['tagged_edit_gpu_ms_per_offered_command'],'current_complete_executor_gpu_ms_per_command':right['tagged_edit_gpu_ms_per_offered_command'],'rendering_note':'Same camera, full initial physical fields, common visual settings and identical water-sides data. Product HUD layouts differ; actual draw/primitive counts are retained. No effects or simulation load was reduced.'})
    expected={(mode,tool,r,family) for mode in ['detailed','coarse'] for tool in ['dig','fill','wall','shovel'] for r in range(3) for family in ['old','current']}
    if not args.pilot:check('all_forty_eight_final_runs',set(runs)==expected)
    current_configs=[d['runtime']['configuration'] for key,d in runs.items() if key[3]=='current']
    check('all_current_full_frozen_configurations_equal',all(c==current_configs[0] for c in current_configs))
    judgments={}
    for tool in ['dig','fill','wall','shovel']:
        selected=[p for p in pairs if p['mode']=='coarse' and p['tool']==tool]
        if len(selected)!=3 or not all(p['conditions_matched'] for p in selected):verdict='unknown_unmatched_or_incomplete'
        elif tool in ['dig','fill']:verdict='no_beyond_guard_regression' if not any(p['beyond_regression_guard'] for p in selected) else 'regression_requires_attribution'
        else:verdict='consistent_beyond_guard_gain' if all(p['beyond_gain_guard'] for p in selected) else 'no_confirmed_beyond_guard_gain'
        judgments[tool]=verdict
    integrity=all(c['pass'] for c in checks)
    performance=(not args.pilot and integrity and all(v in ['no_beyond_guard_regression','consistent_beyond_guard_gain'] for v in judgments.values()))
    result={'pass':integrity,'performance_pass':performance,'pilot_only':args.pilot,'checks':checks,'pairs':pairs,'details':details,'judgments':judgments,'auditor_sha256':sha(Path(__file__)),'frozen_guard_sha256':sha(ROOT/'task/sandcastle_unified_edit_pipeline/验收/G0_基线噪声与比较门.json'),'scope':'Independent integrity and separate coarse-input-frame performance judgment against frozen guards. Stage timestamp sums and full-product HUD draw differences are explicit; P99 unknown with fewer than 1000 input intervals. Editor remains present, no isolated GPU claim.'}
    output.write_text(json.dumps(result,indent=2),'utf-8');print('COST_AUDIT',integrity,'performance',performance,'checks',len(checks),'judgments',judgments);print('FAILURES',[c['name'] for c in checks if not c['pass']]);raise SystemExit(0 if integrity else 1)
if __name__=='__main__':main()
