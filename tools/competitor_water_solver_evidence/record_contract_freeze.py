"""Record the C03 numeric freeze and unchanged C04/C05 fields, with snapshots."""
import argparse
import datetime
import json
import shutil
from pathlib import Path
from evidence_contract import identity


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--budget',required=True,type=Path);p.add_argument('--output',required=True,type=Path)
    args=p.parse_args();out=args.output
    if not out.is_absolute() or not str(out).isascii():raise ValueError('Absolute ASCII output required')
    out.mkdir(parents=True,exist_ok=False)
    for name in ['sources','raw','derived','logs']:(out/name).mkdir()
    task=Path(__file__).resolve().parents[1]
    records=[]
    for name,target in [('参考执行与比较.md','reference_contract_v1_1.md'),('README.md','contract_index.md')]:
        path=task/'契约'/name;snapshot=out/'sources'/target;shutil.copyfile(path,snapshot)
        records.append(dict(source=identity(path),snapshot=identity(snapshot)))
    for name in ['record_contract_freeze.py','evidence_contract.py']:
        shutil.copyfile(Path(__file__).with_name(name),out/'sources'/name)
    document=dict(schema_version='1.0',run_id=out.name,recorded_at=datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),
        contract_document_version='1.1',components=dict(C03='method v1 and registered single-kernel numeric budget v1',C04='field semantics v1 unchanged; observation window pending',C05='isolation semantics v1 unchanged; probe path pending'),
        contracts=records,budget=identity(args.budget),previous_freeze=identity(task.parents[1]/'docs/competitor/evidence/water_solver_reconstruction/t00_baseline_20261025_v2/contract_freeze.json'),
        change_scope='Adds current numerical rule and exact source reference to C03. No runtime code/physical semantics, C04 fields or C05 isolation changes. No Godot candidate comparison has occurred.',
        affected_consumers=['T06 must select matching frozen program/input/constant/dependency identity; new scope requires native references and versioned budget before comparison'],
        operation_status='complete',verification_status='not_evaluated',errors=[],artifacts=[identity(p) for p in out.rglob('*') if p.is_file()])
    (out/'manifest.json').write_text(json.dumps(document,indent=2),encoding='utf-8')
    print(json.dumps(dict(output=out.as_posix(),budget=document['budget'],contracts=len(records))))


if __name__=='__main__':main()
