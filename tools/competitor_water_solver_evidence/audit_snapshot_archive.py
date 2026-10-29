"""Verify immutable archived snapshot/trace artifacts and index successes and failures."""
import argparse
import json
import re
import shutil
from pathlib import Path
from evidence_contract import identity


def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--root',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);ap.add_argument('--project-profile',default='t06_snapshot_glsl_20261025_v7');ap.add_argument('--readstream-profile');args=ap.parse_args()
    root=args.root.resolve();out=args.output.resolve();out.mkdir(parents=True,exist_ok=False)
    errors=[];rows=[];total=0
    for run in sorted(root.iterdir()):
        if not run.is_dir() or run==out or not run.name.startswith(('t06_snapshot_','t06_trace_','t06_register_','t06_strict_','t06_token_','t06_storage_','t06_cpu_','t06_reassociation_','t06_profile_','t06_contract_','t06_readstream_')):continue
        path=run/'manifest.json'
        if not path.exists():errors.append(dict(run=run.name,error='MANIFEST_MISSING'));continue
        manifest=json.loads(path.read_text());count=0
        for item in manifest['artifacts']:
            p=Path(item['path']).resolve()
            if not p.is_relative_to(run):errors.append(dict(run=run.name,error='ARCHIVE_ARTIFACT_OUTSIDE_RUN',path=str(p)));continue
            now=identity(p)
            if now.get('sha256')!=item['sha256'] or now.get('size_bytes')!=item['size_bytes']:errors.append(dict(run=run.name,error='ARCHIVED_BYTES_CHANGED',expected=item,actual=now))
            count+=1
        total+=count
        rows.append(dict(run_id=run.name,manifest=identity(path),operation_status=manifest['operation_status'],verification_status=manifest['verification_status'],artifacts_checked=count))
    # Current project shader bytes must match the explicitly selected archived profile.
    base=json.loads((root/args.project_profile/'lowering.json').read_text());restored=base
    restored_rows=[]
    for old,new in zip(base['programs'],restored['programs']):
        actual=identity(new['shader']['path']);ok=old['event']==new['event'] and actual['sha256']==old['shader']['sha256']==new['shader']['sha256']
        restored_rows.append(dict(event=new['event'],current=actual,baseline=old['shader']['sha256'],passed=ok))
        if not ok:errors.append(dict(error='PROJECT_SNAPSHOT_NOT_RESTORED',event=new['event']))
    live_readstream=[]
    if args.readstream_profile:
        lower=json.loads((root/args.readstream_profile/'lowering.json').read_text())
        for key in ['shader','probe','scene']:
            actual=identity(lower[key]['path']);ok=actual['sha256']==lower[key]['sha256'] and actual['size_bytes']==lower[key]['size_bytes']
            live_readstream.append(dict(kind=key,current=actual,passed=ok))
            if not ok:errors.append(dict(error='PROJECT_READSTREAM_NOT_MATCHED',kind=key))
    # New knowledge entry links point to actual artifacts; no old historical links are rewritten.
    project=Path(__file__).resolve().parents[3];topic=project/'docs/competitor/水求解参考与同步.md'
    text=topic.read_text(encoding='utf-8').split('## WATER-SNAPSHOT-ARITHMETIC-01：',1)[1]
    for target in re.findall(r'\]\(([^)]+)\)',text):
        if not target.startswith('http') and not (topic.parent/target).is_file():errors.append(dict(error='KNOWLEDGE_LINK_MISSING',target=target))
    report=dict(operation_status='complete',verification_status='passed' if not errors else 'failed',scope='Archive byte integrity, restored shader identities and new topic links only; not numerical acceptance.',
        runs=rows,run_count=len(rows),artifacts_checked=total,current_project_profile=args.project_profile,restored_snapshot_shaders=restored_rows,current_readstream_profile=args.readstream_profile,live_readstream_artifacts=live_readstream,errors=errors)
    (out/'archive.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    for name in ['audit_snapshot_archive.py','evidence_contract.py']:shutil.copyfile(Path(__file__).parent/name,out/name)
    (out/'manifest.json').write_text(json.dumps(dict(operation_status='complete',verification_status=report['verification_status'],artifacts=[identity(p) for p in out.iterdir() if p.is_file()]),indent=2),encoding='utf-8')
    print(json.dumps(dict(status=report['verification_status'],runs=len(rows),artifacts=total,errors=errors[:5])))
    raise SystemExit(bool(errors))


if __name__=='__main__':main()
