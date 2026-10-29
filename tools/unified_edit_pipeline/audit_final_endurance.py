"""Independent timed declarations, real receipts, native headers and ownership."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import zipfile
from native_variant import VariantReader
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    parser=argparse.ArgumentParser();parser.add_argument('run',type=Path);args=parser.parse_args();folder=args.run.resolve();checks=[]
    assert not (folder/'audit.json').exists(),'Fresh audit required'
    def check(name,value):checks.append({'name':name,'pass':bool(value)})
    report=json.loads((folder/'report.json').read_text('utf-8'));check('runner_pass',report['pass'] and len(report['runs'])==1)
    with zipfile.ZipFile(report['source_zip']) as z:
        check('source_zip_crc',z.testzip() is None);check('source_zip_hash',sha(Path(report['source_zip']))==report['source_zip_sha256'])
        for name,digest in report['sources'].items():check('source:'+name,hashlib.sha256(z.read(name.removeprefix('res://'))).hexdigest()==digest)
    row=report['runs'][0];p=Path(row['evidence']);d=json.loads(p.read_text('utf-8'));o=d['observations']
    check('actual_process_evidence',row['exit_code']==0 and row['clean_logs'] and sha(p)==row['evidence_sha256'] and d['pass'])
    interactions=o['interactions'];receipts=o['mixed_results'];samples=o['resource_samples'];rounds=o['rounds']
    tools={'place_sand','remove_sand','wall_v1','shovel_v1','castle_v1','smooth_v1','compact_v1','suspended_sand','gravel_drop'}
    check('nine_tools_actual_admission',len(interactions)>=300 and {x['tool'] for x in interactions}==tools and all(x['begin']['accepted'] and x['move']['accepted'] and x['end']['accepted'] for x in interactions))
    check('three_minutes_input_timestamps',interactions[-1]['elapsed_ms']-interactions[0]['elapsed_ms']>=180000 and o['interaction_elapsed_ms']>=180000)
    check('monotonic_continuous_input',all(b['elapsed_ms']>a['elapsed_ms'] and b['first_id']==a['last_id']+1 for a,b in zip(interactions,interactions[1:])))
    ids={r['command_id'] for r in receipts}
    check('all_actual_command_receipts_once',len(receipts)==len(ids) and ids==set(range(interactions[0]['first_id'],interactions[-1]['last_id']+1)))
    check('real_gpu_receipts_no_unknown',all(r.get('outcome') in [1,2,3] and r.get('completion_phase')==1 and r.get('generation')==1001 and r.get('invalid_flags')==0 for r in receipts))
    check('both_realtime_and_paused_editing',{x['playing'] for x in interactions}=={True,False} and interactions[-1]['completed_tick']>interactions[0]['completed_tick']+10)
    check('at_least_thirty_resource_samples',len(samples)>=30)
    check('bounded_queues_and_consumers',all(s['pending']<=64 and s['active']<=3 and s['height_active']<=2 and s['results_reserved']<=512 for s in samples))
    check('same_live_gpu_resource_counts',all(s['ownership']==samples[0]['ownership'] for s in samples))
    check('ten_rounds',len(rounds)==10 and [r['iteration'] for r in rounds]==list(range(10)))
    for r in rounds:
        name='round_'+str(r['iteration']);p=Path(r['path']);raw=p.read_bytes()
        check(name+':native_sha',sha(p)==r['sha256'])
        check(name+':native_header',raw[:8]==b'SANDUE06' and struct.unpack_from('<II',raw,8)==(1,len(raw)-48) and hashlib.sha256(raw[48:]).digest()==raw[16:48])
        # Read only the scalar identity prefix. Configuration/native structures
        # are validated by unchanged product Codec; no unsupported Variant is
        # replaced or assumed empty in this independent prefix check.
        reader=VariantReader(raw[48:]);assert reader.unpack('<I')==27;count=reader.unpack('<I');prefix={}
        for _ in range(count):
            key=reader.value()
            if key=='configuration':break
            prefix[key]=reader.value()
        check(name+':saved_identity',prefix['generation']==r['old_generation'] and prefix['state_seq']==r['saved_state_seq'] and r['restored_generation']==r['old_generation']+1)
        check(name+':both_old_gpu_bundles_zero',all(len(r[key])==8 and all(v==0 for v in r[key].values()) for key in ['restored_owner_zero','switched_owner_zero']))
        check(name+':formal_target',r['target']==('test1_capture' if r['iteration']%2==0 else 'main'))
    check('all_switched_roots_closed_and_freed',len(o['release_records'])>=10 and all(r['gpu_released'] and r['node_freed'] for r in o['release_records']))
    result={'pass':all(c['pass'] for c in checks),'checks':checks,'auditor_sha256':sha(Path(__file__)),'interaction_window_ms':interactions[-1]['elapsed_ms']-interactions[0]['elapsed_ms'],'max_input_gap_ms':max(b['elapsed_ms']-a['elapsed_ms'] for a,b in zip(interactions,interactions[1:])),'scope':'Actual admission timestamps/complete receipts, bounded fixed GPU ownership, scalar native container prefix and ten restore/switch/close ownership rounds. Save/switch time excluded. Observer retains logs/results, so process-memory samples are diagnostic rather than a leak proof.'}
    (folder/'audit.json').write_text(json.dumps(result,indent=2),'utf-8');print('ENDURANCE_AUDIT',result['pass'],'checks',len(checks));print('FAILURES',[x['name'] for x in checks if not x['pass']]);raise SystemExit(0 if result['pass'] else 1)
if __name__=='__main__':main()
