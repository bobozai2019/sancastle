"""Join completed immutable cost subsets, retaining excluded startup failures."""
import argparse
import hashlib
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path,required=True);parser.add_argument('groups',nargs='+',type=Path);args=parser.parse_args();folder=args.output.resolve();folder.mkdir(parents=True,exist_ok=False)
    rows=[];excluded=[];inputs=[];current=None;engine=None
    for group in args.groups:
        group=group.resolve();path=group/'report.json';r=json.loads(path.read_text('utf-8'))
        if current is None:current=r['current_sources'];engine=r['engine_sha256']
        assert current==r['current_sources'] and engine==r['engine_sha256'],'current source/engine drift'
        inputs.append({'path':str(path),'sha256':sha(path),'parent_pass':r['pass']})
        for row in r['runs']:
            if row['pass']:
                assert row['exit_code']==0 and row['clean_logs'] and sha(Path(row['evidence']))==row['evidence_sha256'];rows.append({**row,'source_report':str(path),'source_report_sha256':sha(path)})
            else:
                d=json.loads(Path(row['evidence']).read_text('utf-8'))
                assert not d['commands'] and not d['input_open'] and d['startup']['load_to_ready_us']>=60000000
                assert [x['name'] for x in d['checks'] if not x['pass']]==['ready'],'Only the proven pre-input startup timeout may be excluded'
                excluded.append({**row,'reason':'Original observer startup limit reached before any input/cost window; raw failed report retained','source_report':str(path),'source_report_sha256':sha(path)})
    keys=[(x['mode'],x['tool'],x['repeat'],x['family']) for x in rows]
    expected={(m,t,i,f) for m in ['detailed','coarse'] for t in ['dig','fill','wall','shovel'] for i in range(3) for f in ['old','current']}
    assert len(rows)==48 and len(set(keys))==48 and set(keys)==expected
    for mode in ['detailed','coarse']:
        for tool in ['dig','fill','wall','shovel']:
            for repeat in range(3):
                order=[x['family'] for x in rows if x['mode']==mode and x['tool']==tool and x['repeat']==repeat]
                assert order==(['old','current'] if repeat%2==0 else ['current','old'])
    proof=ROOT/'test_output/unified_edit_pipeline/g8_cost_final01/observer_wait_change.json';p=json.loads(proof.read_text('utf-8'));assert p['normalized_run_equal']
    first=json.loads((Path('D:/godot/test_runs/uep_g8_reference01')/'reference-index.json').read_text('utf-8'));second=json.loads((Path('D:/godot/test_runs/uep_g8_reference02')/'reference-index.json').read_text('utf-8'))
    observer='tools/unified_edit_pipeline/reference_cost_probe.gd'
    assert first['files'][observer]['sha256']==p['original_wrapper_sha256'] and second['files'][observer]['sha256']==p['new_wrapper_sha256']
    old=(Path('D:/godot/test_runs/uep_g8_reference01')/'tools/unified_edit_pipeline/workload_probe.gd').read_text('utf-8');old=old[old.index('func _run() -> void:'):old.index('\nfunc _finish() -> void:')].strip()
    new=(Path('D:/godot/test_runs/uep_g8_reference02')/observer).read_text('utf-8');new=new[new.index('func _run() -> void:'):].strip()
    assert new.replace('Time.get_ticks_msec()+180000','Time.get_ticks_msec()+60000')==old
    assert set(first['files'])==set(second['files'])
    variations=[];allowed={'tools/unified_edit_pipeline/reference_cost_probe.gd','.godot/global_script_class_cache.cfg','.godot/uid_cache.bin'}
    for name in first['files']:
        if first['files'][name]['sha256']!=second['files'][name]['sha256']:
            assert name in allowed,'Reference game source/resource changed: '+name
            variations.append(name)
    result={'pass':True,'runs':rows,'excluded_failed_starts':excluded,'source_groups':inputs,'current_sources':current,'engine_sha256':engine,'reference_variations':variations,'observer_wait_change':{'path':str(proof),'sha256':sha(proof)},'scope':'48 actually completed runs from immutable subsets, same current sources and old reference game/resources. One explicitly pre-input failed startup is preserved and excluded; six unaffected detailed dig samples are not rerun or relabeled. The sole observer logic change is a longer startup allowance.'}
    (folder/'report.json').write_text(json.dumps(result,indent=2),'utf-8');print('COST_JOINT',len(rows),'excluded_failed_starts',len(excluded))
if __name__=='__main__':main()
