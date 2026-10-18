"""Seal terminal G7 evidence and exact independent verifier dependencies."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile
ROOT=Path(__file__).resolve().parents[2]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    p=argparse.ArgumentParser();p.add_argument('run',type=Path);p.add_argument('--auditor',required=True);args=p.parse_args();folder=args.run.resolve()
    report=json.loads((folder/'report.json').read_text('utf-8'));audit=json.loads((folder/'audit.json').read_text('utf-8'))
    assert report['pass'] and audit['pass']
    extras=[args.auditor,'tools/unified_edit_pipeline/audit_extensions.py','tools/unified_edit_pipeline/native_variant.py','tools/unified_edit_pipeline/seal_g7.py']
    with zipfile.ZipFile(report['source_zip']) as src,zipfile.ZipFile(folder/'verification_sources.zip','x',zipfile.ZIP_DEFLATED) as dst:
        assert src.testzip() is None
        for name in src.namelist():dst.writestr(name,src.read(name))
        for name in extras:
            if name not in src.namelist():dst.write(ROOT/name,name)
    with zipfile.ZipFile(folder/'verification_sources.zip') as z:
        assert z.testzip() is None and len(z.namelist())==len(set(z.namelist()))
        for name in extras:assert hashlib.sha256(z.read(name)).hexdigest()==sha(ROOT/name)
    assert audit['auditor_sha256']==sha(ROOT/args.auditor)
    index={p.relative_to(folder).as_posix():{'bytes':p.stat().st_size,'sha256':sha(p)} for p in sorted(folder.rglob('*')) if p.is_file()}
    target=folder/'artifact-index.json';assert not target.exists();target.write_text(json.dumps(index,indent=2),'utf-8')
    print('SEALED',folder.name,'artifacts',len(index))
if __name__=='__main__':main()
