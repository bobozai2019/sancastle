"""Freeze consumed sources and rerun the complete 43-case formal joint matrix."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import zipfile
ROOT=Path(__file__).resolve().parents[2]
GROUPS={'formal':'run_formal.py','boundaries':'run_formal_boundaries.py','remaining':'run_formal_remaining.py','completions':'run_formal_completions.py'}
REFERENCES=['g6_formal_entry01','g6_formal_boundaries_final02','g6_formal_remaining01','g6_formal_completions02','g7_features_snapshot02','g7_extension_runtime02']
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path,required=True);args=parser.parse_args();folder=args.output.resolve();folder.mkdir(parents=True,exist_ok=False)
    paths=set()
    for ref in REFERENCES:
        report=json.loads((ROOT/'test_output/unified_edit_pipeline'/ref/'report.json').read_text('utf-8'));assert report['pass'];paths.update(n.removeprefix('res://') for n in report['sources'])
    paths.add('tools/unified_edit_pipeline/run_g8_regressions.py')
    paths.update('tools/unified_edit_pipeline/'+name for name in GROUPS.values())
    frozen={name:sha(ROOT/name) for name in sorted(paths)}
    (folder/'frozen.json').write_text(json.dumps({'sources':frozen,'scope':'Current consumed source union; no historical runtime result counted as final regression.'},indent=2),'utf-8')
    with zipfile.ZipFile(folder/'frozen_sources.zip','x',zipfile.ZIP_DEFLATED) as z:
        for name in sorted(paths):z.write(ROOT/name,name)
    result={'pass':False,'groups':[],'sources':frozen,'frozen_zip_sha256':sha(folder/'frozen_sources.zip')}
    try:
        for group,script in GROUPS.items():
            command=[sys.executable,str(ROOT/'tools/unified_edit_pipeline'/script),'--output',str(folder/group)]
            with (folder/(group+'_runner.txt')).open('w',encoding='utf-8') as stream:done=subprocess.run(command,cwd=ROOT,stdout=stream,stderr=subprocess.STDOUT)
            result['groups'].append({'group':group,'command':command,'exit_code':done.returncode})
            assert done.returncode==0,group+' failed; original evidence retained'
            report=json.loads((folder/group/'report.json').read_text('utf-8'));assert report['pass']
            for name,digest in report['sources'].items():
                path=name.removeprefix('res://')
                if path in frozen:assert frozen[path]==digest,path
            assert all(sha(ROOT/name)==digest for name,digest in frozen.items()),'frozen source drift'
            print('FINAL_GROUP',group,'PASS',len(report['runs']),flush=True)
        result['pass']=True
    finally:(folder/'matrix.json').write_text(json.dumps(result,indent=2),'utf-8')
if __name__=='__main__':main()
