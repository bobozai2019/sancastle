"""Supplement retained full archives with the accepted indirect buffer."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys
import zipfile
from baseline import configure,run
from context import ROOT,add_arguments,resolve

p=argparse.ArgumentParser(description=__doc__);add_arguments(p)
p.add_argument('--variants',type=Path,required=True,help='JSON list of project/full_run/prefix')
p.add_argument('--engine',type=Path,default=Path('D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'))
a=p.parse_args();configure(a);task,temp=resolve(a);e=task/'验收'
rows=json.loads(a.variants.read_text(encoding='utf-8'));results=[]
previous=None
for spec in rows:
    source=Path(spec['project']).resolve()
    for rel in ['tools/muscl_performance/'+name for name in ('variant_states.gd','indirect_states.gd','fixture_upload.gd')]:shutil.copy2(ROOT/rel,source/rel)
    run(a.engine,spec['prefix'],'indirect',source)
    missing=[];different=[]
    with zipfile.ZipFile(e/spec['full_run']/'states.zip') as full,zipfile.ZipFile(e/spec['prefix']/'states.zip') as supplement:
        for name in supplement.namelist():
            if name.endswith('/accepted_indirect.bin'):continue
            if name not in full.namelist():missing.append(name)
            elif supplement.read(name)!=full.read(name):different.append(name)
    assert not missing and not different,(spec,missing,different)
    if previous:
        subprocess.run([sys.executable,str(ROOT/'tools/muscl_performance/compare_variant_states.py'),'--a',str(e/previous),'--b',str(e/spec['prefix']),'--output',str(e/(spec['prefix']+'_comparison.json'))],check=True)
    results.append({'run':spec['prefix'],'full_run':spec['full_run'],'original_control_trajectory_matches':not missing and not different,'compared_to':previous})
    previous=spec['prefix']
(e/'accepted_indirect_audit.json').write_text(json.dumps({'pass':True,'rows':results,'scope':'Same fixtures with actual accepted-indirect plus all original control/MUSCL buffers/CPU ledger; every shared byte also matches its retained full texture archive. Final full probes capture this buffer together with textures.'},indent=2),encoding='utf-8')
