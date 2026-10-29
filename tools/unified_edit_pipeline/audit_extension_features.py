"""Independent decoded fields/trace/advertised-feature matrix verification."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import struct
import zipfile
from audit_extensions import floats, sha, ROOT

def main():
    parser=argparse.ArgumentParser();parser.add_argument('run',type=Path);args=parser.parse_args();folder=args.run.resolve()
    if (folder/'audit.json').exists():raise SystemExit('Fresh output required')
    report=json.loads((folder/'report.json').read_text('utf-8'));checks=[];details={}
    def check(name,value):checks.append({'name':name,'pass':bool(value)})
    expected={f'{kind}_{w}_{m}' for kind,ms in [('fill',[0]),('stamp',[0,1]),('transfer',[2])] for w in range(4) for m in ms}
    check('complete_sixteen_advertised_combinations',report['pass'] and {r['case'] for r in report['runs']}==expected)
    with zipfile.ZipFile(report['source_zip']) as z:
        check('source_zip_crc',z.testzip() is None);check('source_zip_sha256',sha(Path(report['source_zip']))==report['source_zip_sha256'])
        for name,digest in report['sources'].items():check('source:'+name,hashlib.sha256(z.read(name.removeprefix('res://'))).hexdigest()==digest)
    skeletons={};configs=set()
    for row in report['runs']:
        name=row['case'];kind,w,m=name.split('_');w=int(w);m=int(m)
        p=Path(row['evidence']);d=json.loads(p.read_text('utf-8'));o=d['observations'];r=o['result'];c=o['intent']['configuration']
        check(name+':actual_exit',row['exit_code']==0 and row['clean_logs'] and d['pass'] and sha(p)==row['evidence_sha256'])
        check(name+':selected_advertised_features',c['water_policy']==w and c['material_policy']==m and w in o['profile']['allowed_features']['water_policy'] and m in o['profile']['allowed_features']['material_policy'])
        check(name+':actual_identity',r['outcome']==1 and r['error_code']==0 and r['invalid_flags']==0 and r['generation']==9007199254740993 and r['effective_hash']==c['effective_hash'])
        check(name+':derived_write_mask',r['changed_fields'] & ~c['derived_fields']==0)
        raw={}
        for phase,index in d['snapshots'].items():
            raw[phase]={}
            for field,item in index.items():
                p=Path(item['path']);b=p.read_bytes();raw[phase][field]=b
                check(name+':'+phase+':'+field,len(b)==item['bytes'] and sha(p)==item['sha256'])
                if field!='control':
                    values=(v[0] for v in struct.iter_unpack('<e',b)) if field.startswith(('compaction','wetness')) else floats(b)
                    check(name+':'+phase+':'+field+':finite',all(math.isfinite(v) for v in values))
        check(name+':rock_obstacle_immutable',all(raw['before'][f]==raw['after'][f] for f in ['rock','obstacle']))
        delta=[b-a for a,b in zip(floats(raw['before']['sand0']),floats(raw['after']['sand0']))]
        add=math.fsum(max(0,v) for v in delta)*.015625;remove=-math.fsum(min(0,v) for v in delta)*.015625
        check(name+':actual_sand_result',any(delta) and abs(add-remove-r['added_m3']+r['removed_m3'])<=r['eps_sand_m3'])
        check(name+':nonnegative_physical_fields',all(min(floats(raw['after'][f]))>=0 for f in ['sand0','water0','sediment0']))
        if kind=='transfer':check(name+':transfer_balance',add>0 and remove>0 and abs(add-remove)<=r['eps_transfer_m3'])
        if w==0:
            check(name+':water_disabled_exact_unchanged',all(raw['before'][f+str(i)]==raw['after'][f+str(i)] for f in ['water','sediment','momentum_x','momentum_z'] for i in range(2)))
        trace=next(t for t in o['trace'] if t['command_id']==o['sample_id'])
        expected_water=[] if w==0 else ['prepare','velocity_only' if w==2 else 'packed','displace','velocity','velocity_reduce','audit_blocks','audit_merge']
        check(name+':water_stage_selection',trace['water_stages']==expected_water)
        check(name+':common_tail',trace['phases'][-5:]==[12,5,6,7,8])
        if kind not in skeletons:skeletons[kind]=trace['phases']
        check(name+':same_operation_skeleton',trace['phases']==skeletons[kind])
        if kind=='stamp':check(name+':material_selection_actual',(raw['before']['mold_support0']!=raw['after']['mold_support0'])==(m==1))
        control=raw['after']['control'];check(name+':completed_version',struct.unpack_from('<q',control,16)[0]==r['state_seq'] and struct.unpack_from('<q',control,24)[0]==0)
        configs.add(o['configuration_hash']);details[name]={'added_m3':add,'removed_m3':remove,'selected_features':o['selected_features'],'phases':trace['phases'],'water_stages':trace['water_stages'],'effective_hash':r['effective_hash']}
    check('one_immutable_configuration',len(configs)==1)
    identity=json.loads((ROOT/'assets/unified_edit/extensions/fixture_identity.json').read_text('utf-8'))
    for name,digest in identity['core_before'].items():check('core_after:'+name,sha(ROOT/name)==digest)
    result={'pass':all(c['pass'] for c in checks),'checks':checks,'details':details,'auditor_sha256':sha(Path(__file__)),'scope':'Sixteen advertised legal water/material combinations and varied legal numeric parameters, illegal capabilities/ranges, actual raw fields/common traces. Runtime consumers are separate evidence.'}
    (folder/'audit.json').write_text(json.dumps(result,indent=2),'utf-8');print('FEATURE_AUDIT',result['pass'],'checks',len(checks));print('FAILURES',[c['name'] for c in checks if not c['pass']]);raise SystemExit(0 if result['pass'] else 1)
if __name__=='__main__':main()
