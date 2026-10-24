"""Preserve matching candidate sources alongside completed visual runs."""
import argparse
import hashlib
import json
import shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser()
parser.add_argument('--gate',default='G1',choices=['G1','G2','G3'])
args=parser.parse_args()
GATE=ROOT/'task/water_foam_visual/验收'/args.gate
entries=[]
for probe_path in sorted(GATE.glob('*/*/probe.json')):
    directory=probe_path.parent
    probe=json.loads(probe_path.read_text(encoding='utf-8-sig'))
    cmd=json.loads((directory/'command.json').read_text(encoding='utf-8'))
    candidate=probe.get('observations',{}).get('candidate',{}).get('material',{})
    shader=ROOT/candidate.get('shader','').removeprefix('res://')
    if not shader.is_file():continue
    preserved=directory/'sources'/shader.relative_to(ROOT)
    shader_source=preserved if preserved.is_file() else shader
    shader_hash=hashlib.sha256(shader_source.read_bytes()).hexdigest()
    if shader_hash!=candidate.get('shader_sha256'):raise SystemExit(f'Source no longer matches {probe_path}')
    texture=next((arg.split('=',1)[1] for arg in cmd if arg.startswith('--foam-texture=')),'res://assets/water_foam/foam_cells.png')
    texture_path=ROOT/texture.removeprefix('res://')
    snapshots=[]
    for path in [shader,texture_path,texture_path.with_suffix('.png.import')]:
        target=directory/'sources'/path.relative_to(ROOT)
        target.parent.mkdir(parents=True,exist_ok=True)
        if not target.exists():shutil.copy2(path,target)
        digest=hashlib.sha256(target.read_bytes()).hexdigest()
        snapshots.append(dict(path=target.relative_to(directory).as_posix(),sha256=digest))
    result=dict(scope='Visual probe only; not full Gate or performance acceptance',probe_pass=probe.get('pass'),checks=len(probe.get('checks',[])),texture=texture,shader_sha256=shader_hash,sources=snapshots,command=cmd)
    (directory/'candidate_identity.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    entries.append(dict(run=directory.relative_to(GATE).as_posix(),**result))
(GATE/'visual_index.json').write_text(json.dumps(entries,ensure_ascii=False,indent=2),encoding='utf-8')
print(f'Sealed {len(entries)} visual runs; candidate source identity matched.')
