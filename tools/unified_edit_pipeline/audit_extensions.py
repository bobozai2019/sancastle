"""Independent raw-field and normalized execution comparison for config fixtures."""
import argparse
from array import array
import hashlib
import json
import math
from pathlib import Path
import struct
import zipfile

ROOT = Path(__file__).resolve().parents[2]


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def f32(value):return struct.unpack('<f', struct.pack('<f', value))[0]
def floats(data):
    result = array('f');result.frombytes(data);return result


def main():
    parser = argparse.ArgumentParser();parser.add_argument('run', type=Path);args = parser.parse_args();folder = args.run.resolve();out = folder/'audit.json'
    if out.exists():raise SystemExit('Fresh audit output required')
    checks=[];details={}
    def check(name, value):checks.append({'name':name,'pass':bool(value)})
    report=json.loads((folder/'report.json').read_text('utf-8'));check('six_cases',report['pass'] and {r['case'] for r in report['runs']}=={x+'_'+y for x in ['fill','stamp','transfer'] for y in ['base','new']})
    with zipfile.ZipFile(report['source_zip']) as z:
        check('zip_crc',z.testzip() is None);check('zip_sha',sha(Path(report['source_zip']))==report['source_zip_sha256'])
        for name,digest in report['sources'].items():check('source_'+name,hashlib.sha256(z.read(name.removeprefix('res://'))).hexdigest()==digest)
    data={};all_configs=set();core=None
    for row in report['runs']:
        name=row['case'];path=Path(row['evidence']);d=json.loads(path.read_text('utf-8'));data[name]=d;o=d['observations'];r=o['result'];intent=o['intent'];all_configs.add(o['configuration_hash'])
        check(name+'_actual_exit',row['exit_code']==0 and row['clean_logs'] and d['pass'] and sha(path)==row['evidence_sha256'])
        check(name+'_real_gpu_result',r['outcome']==1 and r['completion_phase']==1 and r['generation']==9007199254740993 and r['error_code']==0 and r['invalid_flags']==0)
        check(name+'_frozen_effective_hash',r['effective_hash']==intent['configuration']['effective_hash'] and r['profile_version']==o['profile']['version'])
        check(name+'_derived_fields',r['changed_fields'] & ~intent['configuration']['derived_fields']==0)
        raw={}
        for phase,index in d['snapshots'].items():
            raw[phase]={}
            for field,item in index.items():
                p=Path(item['path']);b=p.read_bytes();raw[phase][field]=b;check(name+'_'+phase+'_'+field,len(b)==item['bytes'] and sha(p)==item['sha256'])
                if field!='control':
                    values=(v[0] for v in struct.iter_unpack('<e',b)) if field.startswith(('compaction','wetness')) else floats(b)
                    check(name+'_'+phase+'_'+field+'_finite',all(math.isfinite(v) for v in values))
        check(name+'_immutable_inputs',all(raw['before'][field]==raw['after'][field] for field in ['rock','obstacle']))
        before=floats(raw['before']['sand0']);after=floats(raw['after']['sand0']);delta=[b-a for a,b in zip(before,after)]
        added=math.fsum(max(x,0) for x in delta)*.015625;removed=-math.fsum(min(x,0) for x in delta)*.015625
        check(name+'_sand_nonnegative',min(after)>=0)
        check(name+'_actual_field_change',any(delta))
        check(name+'_sand_result_budget',abs((added-removed)-(r['added_m3']-r['removed_m3']))<=r['eps_sand_m3'])
        check(name+'_water_sediment_nonnegative',min(floats(raw['after']['water0']))>=0 and min(floats(raw['after']['sediment0']))>=0)
        control=raw['after']['control'];check(name+'_shared_completed_version',struct.unpack_from('<q',control,16)[0]==r['state_seq'] and struct.unpack_from('<q',control,24)[0]==0 and struct.unpack_from('<f',control,32)[0]==0)
        if core is None:core=o['core_before']
        check(name+'_same_core_snapshot',core==o['core_before'])
        details[name]={'changed_cells':sum(x!=0 for x in delta),'added_m3':added,'removed_m3':removed,'sand_sha':hashlib.sha256(raw['after']['sand0']).hexdigest(),'water_sha':hashlib.sha256(raw['after']['water0']).hexdigest(),'trace':next(t for t in o['trace'] if t['command_id']==o['sample_id'])}
        if name.startswith('transfer_'):check(name+'_actual_transfer_conservation',abs(added-removed)<=r['eps_transfer_m3'] and added>0 and removed>0)
        if name=='stamp_new':
            template=o['profile']['template'];payload=floats((ROOT/template['payload_path'].removeprefix('res://')).read_bytes());height=f32(o['profile']['defaults']['height_m']);rock=floats(raw['before']['rock']);mismatches=0
            for z in range(256):
                for x in range(256):
                    i=z*256+x;lx=(x+.5-128)*.125;lz=(z+.5-128)*.125;expected=before[i]
                    if abs(lx)<=2 and abs(lz)<=2:
                        tx=int((lx+2)/.0625);tz=int((lz+2)/.0625);p=(tz*65+tx)*4
                        if payload[p+1]>=.5:expected=max(expected,f32(f32(payload[p]*height)-rock[i]))
                    if after[i]!=expected:mismatches+=1
            check('new_template_exact_f32_height_field',mismatches==0);details[name]['template_mismatches']=mismatches
            check('new_template_changes_material',raw['after']['mold_support0']!=raw['before']['mold_support0'])
    check('one_configuration_for_all_comparisons',len(all_configs)==1)
    for group in ['fill','stamp','transfer']:
        a,b=details[group+'_base'],details[group+'_new']
        check(group+'_same_common_trace',{k:v for k,v in a['trace'].items() if k!='command_id'}=={k:v for k,v in b['trace'].items() if k!='command_id'})
        check(group+'_configuration_effect_visible',a['sand_sha']!=b['sand_sha'])
    check('wide_fill_actual_wider_footprint',details['fill_new']['changed_cells']>details['fill_base']['changed_cells'])
    check('wide_transfer_actual_more_moved',details['transfer_new']['removed_m3']>details['transfer_base']['removed_m3'])
    for name,digest in core.items():check('core_after_'+name,sha(ROOT/name)==digest)
    result={'pass':all(c['pass'] for c in checks),'checks':checks,'details':details,'auditor_sha256':sha(Path(__file__)),'scope':'Actual raw fields, exact original template prediction, conservation result budgets and common traces; no broader G7 writer audit or formal UI/cost claim'}
    out.write_text(json.dumps(result,indent=2),encoding='utf-8');print('EXTENSION_AUDIT',result['pass'],'checks',len(checks));raise SystemExit(0 if result['pass'] else 1)


if __name__=='__main__':main()
