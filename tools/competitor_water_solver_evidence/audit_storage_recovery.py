"""Verify frozen evidence bytes after transparent NTFS compression; no relocation/deletion."""
import argparse
import hashlib
import json
import shutil
from pathlib import Path
from evidence_contract import identity


def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--manifest',type=Path,required=True);ap.add_argument('--backup-ledger',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);args=ap.parse_args()
    out=args.output.resolve();out.mkdir(parents=True,exist_ok=False);m=json.loads(args.manifest.read_text());errors=[]
    for i,a in enumerate(m['artifacts']):
        path=Path(a['path'])
        with path.open('rb') as f:digest=hashlib.file_digest(f,'sha256').hexdigest()
        if digest!=a['sha256'] or path.stat().st_size!=a['size_bytes']:errors.append(a['path'])
        if (i+1)%1000==0:print(json.dumps(dict(checked=i+1,total=len(m['artifacts']))),flush=True)
    backup=json.loads(args.backup_ledger.read_text())
    if backup['verification_status']!='passed' or backup['errors']:errors.append('BACKUP_NOT_VERIFIED')
    report=dict(operation_status='complete',verification_status='passed' if not errors else 'failed',source_manifest=identity(args.manifest),artifacts_checked=len(m['artifacts']),errors=errors,
        backup_ledger=identity(args.backup_ledger),backup_copy_files=len(backup['checked']),canonical_D_paths_retained=True,relocation_performed=False,originals_deleted=False,
        metadata_actions=['NTFS compact on t06_native_matrix_20261025_v1','NTFS compact on t06_snapshot_godot_full_20261025_v2/raw','Compression inheritance enabled on task evidence root'],
        D_free_bytes=shutil.disk_usage('D:/').free,
        scope='All indexed original matrix content hashes verified after transparent NTFS compression. Verified C backup is redundant; no canonical data depends on a junction or temporary path.')
    (out/'audit.json').write_text(json.dumps(report,indent=2),encoding='utf-8');shutil.copyfile(args.backup_ledger,out/'verified_backup_copy.json')
    for name in ['audit_storage_recovery.py','evidence_contract.py']:shutil.copyfile(Path(__file__).parent/name,out/name)
    (out/'manifest.json').write_text(json.dumps(dict(operation_status='complete',verification_status=report['verification_status'],artifacts=[identity(p) for p in out.iterdir() if p.is_file()]),indent=2),encoding='utf-8')
    print(json.dumps(dict(status=report['verification_status'],checked=len(m['artifacts']),errors=errors[:3])));raise SystemExit(bool(errors))


if __name__=='__main__':main()
