"""Run original six-kernel references on declared boundary/threshold inputs."""
import argparse
import itertools
import json
import shutil
from pathlib import Path
import numpy as np
from evidence_contract import identity
from analyze_repeats import difference,decode
from run_native_suite import STAGES,run,write


def verify(artifact):
    actual=identity(artifact['path'])
    if actual['sha256']!=artifact['sha256'] or actual['size_bytes']!=artifact['size_bytes']:raise ValueError('SOURCE_CHANGED:'+artifact['path'])


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--suite',type=Path,required=True);parser.add_argument('--fixtures',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();out=args.output
    if not out.is_absolute() or not str(out).isascii():raise ValueError('Absolute ASCII output required')
    out.mkdir(parents=True,exist_ok=False)
    for name in ['raw','sources','derived','logs']:(out/name).mkdir()
    report=dict(schema_version='1.0',run_id=out.name,operation_status='failed',verification_status='not_evaluated',
                results=[],errors=[],numeric_budget=None,reference_scope='Synthetic independent single-kernel inputs, not original trajectory')
    write(out/'manifest.json',report)
    try:
        fixture_manifest=json.loads((args.fixtures/'manifest.json').read_text());suite=json.loads((args.suite/'manifest.json').read_text())
        if suite['verification_status']!='passed':raise ValueError('SIX_KERNEL_BASELINE_NOT_VALID')
        baseline={r['request']['event_id']:r['request'] for r in suite['references'] if r['request']['before_copy']}
        exe=out/'sources/water_reference.exe';shutil.copyfile(args.suite/'sources/water_reference.exe',exe)
        shutil.copyfile(args.suite/'sources/water_reference.cpp',out/'sources/water_reference.cpp')
        for name in ['run_native_controlled.py','run_native_suite.py','evidence_contract.py','analyze_repeats.py']:
            shutil.copyfile(Path(__file__).with_name(name),out/'sources'/name)
        requests=[]
        for fixture in fixture_manifest['fixtures']:
            for key in ['water','sand','air','obstacle']:verify(fixture[key])
            for eid,(kind,_,program_hash) in STAGES.items():
                base=baseline[eid]
                for key in ['program','constants']:verify(base[key])
                if base['program']['sha256']!=program_hash:raise ValueError('PROGRAM_MISMATCH')
                name=fixture['fixture_id']+'_e%d'%eid;target=out/'raw'/name
                command=[str(exe),'--program',base['program']['path'],'--input',fixture['water']['path'],
                    '--constants',base['constants']['path'],'--kind',kind,'--before-copy','1','--repeat','3','--output',str(target)]
                dependencies=[fixture['water'],base['program'],base['constants']]
                srvs=[]
                if kind=='floor':command+=['--srv0',fixture['sand']['path']];srvs=[dict(register=0,artifact=fixture['sand'])]
                if kind=='sources':
                    command+=['--texture0',fixture['obstacle']['path'],'--srv1',fixture['air']['path']]
                    srvs=[dict(register=0,artifact=fixture['obstacle']),dict(register=1,artifact=fixture['air'])]
                requests.append(dict(reference_id=name,event_id=eid,fixture_id=fixture['fixture_id'],origin=fixture['origin'],
                    command=command,output=str(target),input=fixture['water'],program=base['program'],constants=base['constants'],
                    srvs=srvs,dependencies=dependencies+[s['artifact'] for s in srvs],probe=fixture.get('B_probe') if eid==1495 else None,
                    pairing_kind='reconstructed_controlled',numeric_budget=None))
        write(out/'request.json',dict(fixture_manifest=identity(args.fixtures/'manifest.json'),baseline=identity(args.suite/'manifest.json'),
            executable=identity(exe),requests=requests,scope='No candidate implementation or tolerance fitting. All parameters unchanged; fixture definitions distinguish only the declared state inputs.'))
        all_metrics=[]
        for req in requests:
            if req['event_id']==1484:print(json.dumps(dict(phase='fixture',fixture=req['fixture_id'])),flush=True)
            execution=run(req['command'],out/'logs'/req['reference_id'])
            if execution['exit_code']:
                report['errors'].append(dict(code='CONTROLLED_NATIVE_FAILURE',reference_id=req['reference_id'],execution=execution));break
            root=Path(req['output']);logs=[json.loads(line) for line in (root/'execution.jsonl').read_text().splitlines()]
            if len(logs)!=3:raise ValueError('INCOMPLETE_REPEATS')
            checks=[]
            for index,log in enumerate(logs):
                before=identity(root/('before_%d.bin'%index));after=identity(root/('after_%d.bin'%index))
                if before['sha256']!=req['input']['sha256'] or after['size_bytes']!=2097152 or log['fence_completed']<log['fence_ticket']:raise ValueError('RESTORATION_OR_FENCE_FAILURE')
                dep_checks=[]
                for srv in req['srvs']:
                    observed=identity(root/('srv%d_before_%d.bin'%(srv['register'],index)))
                    if observed['sha256']!=srv['artifact']['sha256']:raise ValueError('SRV_RESTORATION_FAILURE')
                    dep_checks.append(observed)
                record=dict(repeat=index,before=before,after=after,srv_before=dep_checks,fence_complete=True)
                if req['probe']:
                    p=req['probe'];raw=np.fromfile(after['path'],dtype='<u4').reshape(256,512,4)
                    region=(raw[p['y_range'][0]:p['y_range'][1]+1,p['x_range'][0]:p['x_range'][1]+1,3]>>16)&255
                    record['B_probe']=dict(expected=p['expected_code'],values=np.unique(region).tolist(),mismatches=int(np.count_nonzero(region!=p['expected_code'])))
                    if record['B_probe']['mismatches']:report['errors'].append(dict(code='B_PROBE_EXPECTATION_FAILED',reference_id=req['reference_id'],repeat=index,observation=record['B_probe']))
                checks.append(record)
                all_metrics.append(dict(reference_id=req['reference_id'],kind='input_to_output',repeat=index,
                    metric=difference(req['input']['path'],after['path'])))
            for left,right in itertools.combinations(range(3),2):
                all_metrics.append(dict(reference_id=req['reference_id'],kind='same_input_repeat',left=left,right=right,
                    metric=difference(root/('after_%d.bin'%left),root/('after_%d.bin'%right))))
            report['results'].append(dict(reference_id=req['reference_id'],request=req,execution=execution,checks=checks,
                program_unmodified=True,pairing_kind='reconstructed_controlled',dependency_complete=True))
            write(out/'manifest_partial.json',report)
        write(out/'derived/metrics.json',all_metrics)
        report['operation_status']='complete' if len(report['results'])==len(requests) else 'partial'
        report['verification_status']='failed' if report['errors'] else 'passed'
    except Exception as error:
        report['errors'].append(dict(code='CONTROLLED_EXCEPTION',message=str(error)));report['verification_status']='failed'
    report['artifacts']=[identity(p) for p in out.rglob('*') if p.is_file() and p.name!='manifest.json']
    write(out/'manifest.json',report)
    print(json.dumps(dict(operation_status=report['operation_status'],verification_status=report['verification_status'],references=len(report['results']),errors=report['errors'])),flush=True)
    raise SystemExit(1 if report['errors'] else 0)


if __name__=='__main__':main()
