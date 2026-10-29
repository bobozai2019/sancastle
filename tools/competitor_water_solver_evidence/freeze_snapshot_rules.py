"""Freeze exact uint4 arithmetic comparison for matched explicit snapshot adaptations only."""
import argparse
import json
import shutil
from pathlib import Path
from evidence_contract import identity


def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--reference',required=True,type=Path);ap.add_argument('--output',required=True,type=Path)
    args=ap.parse_args();out=args.output.resolve();out.mkdir(parents=True,exist_ok=False)
    manifest=json.loads(args.reference.read_text())
    if manifest['operation_status']!='complete' or manifest['verification_status']!='passed' or manifest['errors']:raise ValueError('SNAPSHOT_REFERENCE_NOT_VALID')
    if manifest['execution_mode']!='explicit_readonly_snapshot_adaptation':raise ValueError('NOT_SNAPSHOT_ADAPTATION')
    if not all(c['passed'] for c in manifest['controls']+manifest['negatives']):raise ValueError('CONTROL_OR_NEGATIVE_NOT_VALID')
    references=[]
    for r in manifest['references']:
        if not r['repeat_stable'] or len(r['checks'])!=3:raise ValueError('REFERENCE_NOT_STABLE')
        for check in r['checks']:
            for a in [check['before'],check['snapshot_before'],check['after'],*check['original_srvs_before']]:
                observed=identity(a['path'])
                if observed['sha256']!=a['sha256'] or observed['size_bytes']!=a['size_bytes']:raise ValueError('REFERENCE_ARTIFACT_CHANGED')
            if not check['fence_complete']:raise ValueError('GPU_COMPLETION_NOT_PROVEN')
        references.append(dict(reference_id=r['reference_id'],original_reference_id=r['original_reference_id'],event_id=r['event_id'],
            original_program=r['original_program'],adapted_program=r['adapted_program'],snapshot=r['snapshot'],output_seed=r['output_seed'],
            constants=r['constants'],srvs=r['srvs'],baseline=r['checks'][0]['after'],outputs=[c['after'] for c in r['checks']],
            criterion='Exact 2097152-byte packed uint4 equality; all nine code fields and their coupling bits included',
            extra_fp_allowance=0,extra_quantization_allowance=0))
    for name in ['freeze_snapshot_rules.py','evidence_contract.py']:shutil.copyfile(Path(__file__).parent/name,out/name)
    report=dict(operation_status='complete',verification_status='passed',
        scope='Matched explicit readonly snapshot adaptation only. No original in-place, schedule, sequence or G02/G5 claim.',
        reference_manifest=identity(args.reference),references=references,
        rule='No numerical padding. Criterion must precede comparison for each new identity; previously compared identities reuse the unchanged exact criterion. File creation alone does not prove chronology; inspect parent experiment receipts. Different mode/input/CB/SRVs/program requires an explicit identity.')
    (out/'rules.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    (out/'manifest.json').write_text(json.dumps(dict(operation_status='complete',verification_status='passed',artifacts=[identity(p) for p in out.iterdir() if p.is_file()]),indent=2),encoding='utf-8')
    print(json.dumps(dict(references=len(references),rule='exact packed bytes')))


if __name__=='__main__':main()
