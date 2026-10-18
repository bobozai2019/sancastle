"""Read-only independent native container/64 height-map/ownership audit."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import zipfile
from audit_extensions import sha, floats, f32
from native_variant import VariantReader

def main():
    parser=argparse.ArgumentParser();parser.add_argument('run',type=Path);parser.add_argument('--features',type=Path,required=True);args=parser.parse_args()
    folder=args.run.resolve();checks=[]
    if (folder/'audit.json').exists():raise SystemExit('Fresh output required')
    def check(name,value):checks.append({'name':name,'pass':bool(value)})
    report=json.loads((folder/'report.json').read_text('utf-8'))
    check('one_actual_runtime_case',report['pass'] and len(report['runs'])==1)
    with zipfile.ZipFile(report['source_zip']) as z:
        check('source_zip_crc',z.testzip() is None);check('source_zip_sha',sha(Path(report['source_zip']))==report['source_zip_sha256'])
        for name,digest in report['sources'].items():check('source:'+name,hashlib.sha256(z.read(name.removeprefix('res://'))).hexdigest()==digest)
    row=report['runs'][0];p=Path(row['evidence']);d=json.loads(p.read_text('utf-8'));o=d['observations']
    check('actual_exit_and_clean_logs',row['exit_code']==0 and row['clean_logs'] and d['pass'] and sha(p)==row['evidence_sha256'])
    container=Path(o['container']['path']).read_bytes()
    check('native_container_identity',sha(Path(o['container']['path']))==o['container']['sha256'])
    check('native_container_header',container[:8]==b'SANDUE06' and struct.unpack_from('<II',container,8)==(1,len(container)-48) and hashlib.sha256(container[48:]).digest()==container[16:48])
    cp=VariantReader(container[48:]).document()
    check('checkpoint_identity',cp['generation']==9007199254740993 and cp['state_seq']==3 and cp['highwater_id']==7 and cp['sim_tick']==0)
    check('fourteen_profiles_in_actual_container',len(cp['configuration']['profiles'])==14 and all(k in cp['configuration']['profiles'] for k in ['wide_fill_v1','stepped_mound_tool_v1','wide_transfer_v1']))
    check('same_frozen_configuration',cp['configuration']['configuration_hash']==o['container']['configuration_hash'])
    maps_meta=o['physics']['maps'];maps=Path(maps_meta['path']).read_bytes()
    check('raw_maps_identity',sha(Path(maps_meta['path']))==maps_meta['sha256'] and len(maps)==64*33*33*4)
    heights=floats(maps);sand=floats(cp['native']['fields']['sand']);rock=floats(cp['native']['fields']['rock'])
    for chunk in range(64):
        expected=[f32(rock[min(255,(chunk//8)*32+z)*256+min(255,(chunk%8)*32+x)]+sand[min(255,(chunk//8)*32+z)*256+min(255,(chunk%8)*32+x)]) for z in range(33) for x in range(33)]
        check('actual_height_map:'+str(chunk),list(heights[chunk*1089:(chunk+1)*1089])==expected)
    check('three_actual_results',len(o['results'])==3 and all(r['outcome']==1 and r['error_code']==0 and r['invalid_flags']==0 for r in o['results']))
    check('each_new_profile_used',[(r['command_id'],c['profile_id']) for r,c in zip(o['results'],o['commands'])]==[(1,'wide_fill_v1'),(3,'stepped_mound_tool_v1'),(6,'wide_transfer_v1')])
    check('collision_changes_after_shared_consumer',o['rays']['edited']>o['rays']['initial']+.05)
    commits=[e for e in o['events'] if e['kind']=='commit']
    check('same_runtime_two_generations',len(commits)==2 and [x['detail']['generation'] for x in commits]==[9007199254740993,9007199254740994] and commits[1]['detail']['state_seq']==3)
    check('old_generation_retired',any(e['kind']=='retired' and e['detail']['generation']==9007199254740993 for e in o['events']))
    check('eight_nested_owner_types_zero',len(o['final_ownership'])==2 and all(len(owner)==8 and all(v==0 for v in owner.values()) for owner in o['final_ownership']))
    feature_report=json.loads((args.features/'report.json').read_text('utf-8'));snapshots=[];binary=[]
    for row in feature_report['runs']:
        data=json.loads(Path(row['evidence']).read_text('utf-8'));obs=data['observations'];snapshots.append(obs['full_configuration'])
        item=obs['configuration_bytes'];p=Path(item['path']);check('full_configuration_bytes:'+row['case'],sha(p)==item['sha256']);binary.append(p.read_bytes())
    check('all_sixteen_full_configuration_values_equal',len(snapshots)==16 and all(s==snapshots[0] for s in snapshots))
    check('all_sixteen_canonical_variant_bytes_equal',all(b==binary[0] for b in binary))
    result={'pass':all(c['pass'] for c in checks),'checks':checks,'auditor_sha256':sha(Path(__file__)),'scope':'Actual original extension registry, native container and all restored height bytes, shared collision/retirement lifecycle. Sixteen feature snapshots compared as values and raw canonical Variant bytes.'}
    (folder/'audit.json').write_text(json.dumps(result,indent=2),'utf-8');print('RUNTIME_AUDIT',result['pass'],'checks',len(checks));print('FAILURES',[c['name'] for c in checks if not c['pass']]);raise SystemExit(0 if result['pass'] else 1)
if __name__=='__main__':main()
