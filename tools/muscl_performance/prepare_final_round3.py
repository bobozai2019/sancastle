"""Freeze final cumulative/runtime and common probe inputs before T06."""
import argparse
import difflib
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
from context import ROOT,add_arguments,resolve

p=argparse.ArgumentParser(description=__doc__);add_arguments(p)
p.add_argument('--base',type=Path,required=True);p.add_argument('--prefix',required=True)
a=p.parse_args();task,temp=resolve(a);e=task/'验收'
subprocess.run([sys.executable,str(ROOT/'tools/muscl_performance/isolate.py'),'--task-root',str(task),'--temp-root',str(temp),'--name',a.prefix+'_a0'],check=True)
original=temp/'projects'/(a.prefix+'_a0');candidate=temp/'projects'/(a.prefix+'_combined')
shutil.copytree(a.base,candidate)
for target in (original,candidate):
    shutil.copytree(ROOT/'tools/muscl_performance',target/'tools/muscl_performance',dirs_exist_ok=True)
    for rel in ('tests/integration/water_execution_exact_probe.gd','tools/wave_propagation/native_restart_probe.gd'):
        shutil.copy2(ROOT/rel,target/rel)
path=candidate/'scripts/simulation/unified_edit/coupled.gd';text=path.read_text(encoding='utf-8')
removed=[];lines=[]
for line in text.splitlines(True):
    if 'sediment_replacements["#version 450"]' in line or line.strip()=='sets.sediment_copy=[]':removed.append(line)
    else:lines.append(line)
path.write_text(''.join(lines),encoding='utf-8')
out=e/(a.prefix+'_sources');out.mkdir(parents=True,exist_ok=False)
changes={};diff=[]
for folder in ('scripts','shaders'):
    for path in (candidate/folder).rglob('*'):
        if not path.is_file() or path.suffix not in ('.gd','.glsl','.glslinc'):continue
        rel=path.relative_to(candidate);base=original/rel
        if base.is_file() and base.read_bytes()==path.read_bytes():continue
        target=out/'sources'/rel;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(path,target)
        changes[rel.as_posix()]={'a0_sha256':hashlib.sha256(base.read_bytes()).hexdigest() if base.is_file() else None,'candidate_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'workspace_before_sha256':hashlib.sha256((ROOT/rel).read_bytes()).hexdigest() if (ROOT/rel).is_file() else None}
        diff.extend(difflib.unified_diff(base.read_text(encoding='utf-8').splitlines(True) if base.is_file() else [],path.read_text(encoding='utf-8').splitlines(True),fromfile='a/'+rel.as_posix(),tofile='b/'+rel.as_posix()))
(out/'changes.diff').write_text(''.join(diff),encoding='utf-8')
(out/'identity.json').write_text(json.dumps({'original':str(original),'candidate':str(candidate),'changes':changes,'cleanup_removed':removed,'cleanup_scope':'Remove overwritten identity #version replacement and unused empty sediment_copy descriptor collection; final source is revalidated before application.'},indent=2),encoding='utf-8')
print(original);print(candidate)
