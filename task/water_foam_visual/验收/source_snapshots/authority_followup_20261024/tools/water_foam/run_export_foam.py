"""Export one fresh actual PCK, then use the existing outside-project GPU audit."""
import argparse
import json
from pathlib import Path
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[2]
ENGINE='D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'
parser=argparse.ArgumentParser()
parser.add_argument('--run-id',required=True)
args=parser.parse_args()
out=ROOT/'task/water_foam_visual/验收/G4'/args.run_id
out.mkdir(parents=True,exist_ok=False);(out/'.gdignore').touch()
pack=out/'sandcastle.pck'
cmd=[ENGINE,'--headless','--path',str(ROOT),'--export-pack','Windows Desktop',str(pack)]
(out/'export_command.json').write_text(json.dumps(cmd,ensure_ascii=False,indent=2),encoding='utf-8')
with (out/'export_stdout.log').open('wb') as stdout,(out/'export_stderr.log').open('wb') as stderr:
    proc=subprocess.run(cmd,cwd=ROOT,stdout=stdout,stderr=stderr,timeout=300)
(out/'export_result.json').write_text(json.dumps({'exit_code':proc.returncode,'pack_exists':pack.is_file()}),encoding='utf-8')
if proc.returncode!=0 or not pack.is_file():raise SystemExit(1)
raise SystemExit(subprocess.call([sys.executable,str(ROOT/'tools/validate_export.py'),'--pack',str(pack),'--output',str(out/'isolated')],cwd=ROOT))
