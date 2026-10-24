"""Read-only numerical-isolation diagnostic; no performance optimization."""
import argparse
import hashlib
import json
import subprocess
from run_final_cost import ROOT,ENGINE,identities
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--run-id',required=True)
parser.add_argument('--probe',choices=['foam_authority_capture_factor_probe.gd','foam_latest_ui_switch_probe.gd','foam_original_authority_probe.gd'],default='foam_authority_capture_factor_probe.gd')
args=parser.parse_args()
dest=ROOT/'task/water_foam_visual/验收/G4'/args.run_id/'main'
dest.mkdir(parents=True,exist_ok=False);(dest.parent/'.gdignore').touch()
probe='tests/visual_water_alignment/'+args.probe
def sources():
    result=identities();result[probe]=hashlib.sha256((ROOT/probe).read_bytes()).hexdigest();return result
def save(name,value):(dest/name).write_text(json.dumps(value,ensure_ascii=False,indent=2),encoding='utf-8')
cmd=[ENGINE,'--path',str(ROOT),'--script','res://'+probe,'--','--scene=main','--output=res://'+dest.relative_to(ROOT).as_posix(),'--ignore-parameter-config']
before=sources();save('sources_before.json',before);save('command.json',cmd)
with (dest/'stdout.log').open('wb') as stdout,(dest/'stderr.log').open('wb') as stderr:
    try:
        process=subprocess.run(cmd,cwd=ROOT,stdout=stdout,stderr=stderr,timeout=600)
        result={'exit_code':process.returncode,'timeout':False}
    except subprocess.TimeoutExpired:result={'exit_code':None,'timeout':True}
after=sources();save('sources_after.json',after)
result['source_drift']=[p for p in before.keys()|after.keys() if before.get(p)!=after.get(p)]
save('result.json',result);print(result,flush=True)
