"""Report frozen G1 thresholds and raw identity differences without relaxing gates."""
import hashlib, json, sys
from pathlib import Path
from summarize_cost import summarize
from analyze_cost import analyze

NOISE={'idle_live':(113,7.931,None),'dig_paused':(131,6.146,104.170),
       'fill_paused':(762,6.794,148.570),'dig_live':(91,10.805,None)}
def read(path):return json.loads(path.read_text(encoding='utf-8'))
def delta(a,b,metric,quantile):
    x=a[metric].get(quantile);y=b[metric].get(quantile)
    return x-y if x is not None and y is not None else None
def compare(root,prefix='t04_formal'):
    root=Path(root);status=read(root/(prefix+'_status.json'));pairs=[]
    for number in range(1,4):
        runs={r['mode']:root/r['name'] for r in status['completed'] if r['pair']==number and r['load_clear']}
        if set(runs)!=set('AB'):continue
        summaries={m:summarize(f) for m,f in runs.items()}
        for folder in runs.values():analyze(folder)
        configs={m:{k:v for k,v in s['configuration'].items() if k not in ['prepare_policy','prepare_min_chunks']} for m,s in summaries.items()}
        initial={m:read(f/'initial/state.json') for m,f in runs.items()}
        identity={'initial_state_equal':initial['A']==initial['B'],'effective_config_equal_except_candidate':configs['A']==configs['B'],
                  'released':all(s['released'] for s in summaries.values()),
                  'exit_zero_unchanged':all(read(f/'exit.json')['exit']==0 and not read(f/'exit.json')['source_changes'] for f in runs.values())}
        cases=[]
        for ac,bc in zip(summaries['A']['cases'],summaries['B']['cases']):
            name=ac['name'];finals={m:read(f/(name+'_final/state.json')) for m,f in runs.items()}
            differences=[k for k in sorted(set(finals['A'])|set(finals['B'])) if finals['A'].get(k)!=finals['B'].get(k)]
            cases.append({'name':name,'A':ac,'B':bc,'final_state_equal':not differences,'final_state_differing_keys':differences,
                'prepare_p95_improvement_us':delta(ac,bc,'main_prepare_us','p95'),
                'frame_p99_improvement_ms':delta(ac,bc,'frame_ms','p99'),
                'feedback_p95_improvement_ms':delta(ac,bc,'admission_to_physics_two_ms','p95'),
                'tick_rate_change_B_minus_A':bc['tick_rate']-ac['tick_rate'],
                'acceptance_rate_change_B_minus_A':bc['acceptance_rate']-ac['acceptance_rate'] if ac['acceptance_rate'] is not None and bc['acceptance_rate'] is not None else None,
                'B_hard_gate':{'tick_rate_ge15':bc['tick_rate']>=15 if name in ['idle_live','dig_live'] else None,
                    'frame_p99_le63':bc['frame_ms'].get('p99',float('inf'))<=63,
                    'paused_collision_ack_max_le100':bc['admission_to_collision_ack_ms'].get('max',float('inf'))<=100 if name.endswith('_paused') else None}})
        pairs.append({'pair':number,'runs':{m:f.name for m,f in runs.items()},'identity':identity,'cases':cases})
    gates=[]
    for name,(prepare_noise,frame_noise,feedback_noise) in NOISE.items():
        values=[next(c for c in p['cases'] if c['name']==name) for p in pairs]
        def all_above(key,threshold):return len(values)==3 and threshold is not None and all(v[key] is not None and v[key]>threshold for v in values)
        gates.append({'case':name,'completed_pairs':len(values),'frozen_noise':NOISE[name],
            'prepare_three_pairs_over_noise':all_above('prepare_p95_improvement_us',prepare_noise),
            'frame_three_pairs_over_noise':all_above('frame_p99_improvement_ms',frame_noise),
            'feedback_three_pairs_over_noise':all_above('feedback_p95_improvement_ms',feedback_noise),
            'three_pairs_acceptance_declines':len(values)==3 and all(v['acceptance_rate_change_B_minus_A'] is not None and v['acceptance_rate_change_B_minus_A']<0 for v in values),
            'three_pairs_tick_rate_declines':len(values)==3 and name in ['idle_live','dig_live'] and all(v['tick_rate_change_B_minus_A']<0 for v in values)})
    output={'pairs':pairs,'gates':gates,'complete_three_pairs':len(pairs)==3,
        'tool_sha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in [Path(__file__),Path(__file__).with_name('summarize_cost.py'),Path(__file__).with_name('analyze_cost.py')]},
        'limits':['Each pair requires exact initial fields/ledger/prefix/tick and matching effective configuration',
                  'Final state and accepted command differences remain explicit; no claim of deterministic replay equality',
                  'Per-case comparisons do not automatically approve G4 or excuse hard-gate failures',
                  'dig_live feedback alternative requires paired paused evidence; its feedback noise is intentionally unavailable']}
    (root/(prefix+'_comparison.json')).write_text(json.dumps(output,indent=2),encoding='utf-8')
    print('completed pairs',len(pairs))
    return output
if __name__=='__main__':compare(sys.argv[1],sys.argv[2] if len(sys.argv)>2 else 't04_formal')
