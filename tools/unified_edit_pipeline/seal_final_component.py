"""Archive exact terminal source/verifier bytes without changing outcomes."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile
ROOT=Path(__file__).resolve().parents[2]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    p=argparse.ArgumentParser();p.add_argument('run',type=Path);p.add_argument('--auditor',required=True);p.add_argument('--extra',action='append',default=[]);args=p.parse_args();folder=args.run.resolve()
    report=json.loads((folder/'report.json').read_text('utf-8'));audit=json.loads((folder/'audit.json').read_text('utf-8'));assert report['pass'] and audit['pass']
    extras={args.auditor,'tools/unified_edit_pipeline/native_variant.py','tools/unified_edit_pipeline/seal_final_component.py',*args.extra}
    for name,digest in audit.get('dependencies',{}).items():
        path='tools/unified_edit_pipeline/'+name;assert sha(ROOT/path)==digest;extras.add(path)
    if (folder/'independent_audit.json').exists():
        independent=json.loads((folder/'independent_audit.json').read_text('utf-8'));assert independent['pass'];extras.add('tools/unified_edit_pipeline/audit_migration.gd');assert independent['auditor_sha256']==sha(ROOT/'tools/unified_edit_pipeline/audit_migration.gd')
    assert audit['auditor_sha256']==sha(ROOT/args.auditor)
    with zipfile.ZipFile(report['source_zip']) as source,zipfile.ZipFile(folder/'verification_sources.zip','x',zipfile.ZIP_DEFLATED) as target:
        assert source.testzip() is None
        for name in source.namelist():target.writestr(name,source.read(name))
        for name in sorted(extras):
            if name not in source.namelist():target.write(ROOT/name,name)
    with zipfile.ZipFile(folder/'verification_sources.zip') as z:
        assert z.testzip() is None and len(z.namelist())==len(set(z.namelist()))
        for name in extras:assert hashlib.sha256(z.read(name)).hexdigest()==sha(ROOT/name)
    index={p.relative_to(folder).as_posix():{'bytes':p.stat().st_size,'sha256':sha(p)} for p in sorted(folder.rglob('*')) if p.is_file()}
    p=folder/'artifact-index.json';assert not p.exists();p.write_text(json.dumps(index,indent=2),'utf-8');print('FINAL_SEAL',folder.name,len(index))
if __name__=='__main__':main()
