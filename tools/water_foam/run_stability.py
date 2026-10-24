"""Final visible long stability: each scene >=600 wall seconds and >=3 wave cycles."""
import argparse
import json
from pathlib import Path
import subprocess
from run_final_cost import ROOT,ENGINE,identities
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--run-id',required=True)
args=parser.parse_args()
out=ROOT/'task/water_foam_visual/验收/G5'/args.run_id
out.mkdir(parents=True,exist_ok=False);(out/'.gdignore').touch()
for scene in ['main','test1_geometry']:
    dest=out/scene;dest.mkdir()
    cmd=[ENGINE,'--path',str(ROOT),'--script','res://tests/visual_water_alignment/foam_stability_probe.gd','--','--scene='+scene,'--output=res://'+dest.relative_to(ROOT).as_posix(),'--ignore-parameter-config']
    (dest/'command.json').write_text(json.dumps(cmd,ensure_ascii=False,indent=2),encoding='utf-8')
    before=identities();(dest/'sources_before.json').write_text(json.dumps(before,indent=2),encoding='utf-8')
    with (dest/'stdout.log').open('wb') as stdout,(dest/'stderr.log').open('wb') as stderr:
        try:
            proc=subprocess.run(cmd,cwd=ROOT,stdout=stdout,stderr=stderr,timeout=1350)
            result={'exit_code':proc.returncode,'timeout':False}
        except subprocess.TimeoutExpired:result={'exit_code':None,'timeout':True}
    after=identities();(dest/'sources_after.json').write_text(json.dumps(after,indent=2),encoding='utf-8')
    result['source_drift']=[p for p in before.keys()|after.keys() if before.get(p)!=after.get(p)]
    (dest/'result.json').write_text(json.dumps(result),encoding='utf-8')
    print(scene,result,flush=True)
    if result['exit_code']!=0 or result['source_drift']:raise SystemExit(1)
