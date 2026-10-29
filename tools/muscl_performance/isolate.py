"""Rebuild a controlled project from the immutable round-two archive."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import zipfile
from context import add_arguments, resolve, baseline_paths

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
add_arguments(parser)
parser.add_argument('--name', required=True)
parser.add_argument('--diagnostic', action='store_true')
parser.add_argument('--overlay-root',type=Path,help='Explicit immutable sources tree, with project-relative paths')
args = parser.parse_args()
task, temporary = resolve(args)
target = temporary / 'projects' / args.name
target.mkdir(parents=True, exist_ok=False)
baseline, reference = baseline_paths(args,task)
archive = baseline / 'runtime.zip'
with zipfile.ZipFile(archive) as source:
    source.extractall(target)
shutil.copytree(reference, target / 'task' / task.name / reference.name)
shutil.copytree(ROOT / 'tools/muscl_performance', target / 'tools/muscl_performance', dirs_exist_ok=True)
if args.diagnostic:
    # Keep the recorder and its private binding layouts together. Copying only
    # the recorder becomes invalid once a candidate adds private shader fields.
    relatives=['scripts/simulation/unified_edit/'+n for n in ('water.gd','water_muscl.gd','water_numerics.gd','coupled.gd')]
    relatives += [p.relative_to(ROOT).as_posix() for p in (ROOT/'shaders/simulation/muscl').glob('*') if p.is_file()]
    for relative in relatives:shutil.copy2(ROOT/relative,target/relative)
if args.overlay_root:
    for source in args.overlay_root.resolve().rglob('*'):
        if source.is_file():
            relative=source.relative_to(args.overlay_root.resolve())
            destination=target/relative;destination.parent.mkdir(parents=True,exist_ok=True)
            shutil.copy2(source,destination)
# Freeze only imported outputs actually referenced by archived .import files;
# never link a live workspace cache into a measured project.
imported = set()
for path in target.rglob('*.import'):
    imported.update(re.findall(r'"res://([^"\n]+)"', path.read_text(encoding='utf-8')))
copied = 0
missing = []
for relative in sorted(imported):
    if not relative.startswith('.godot/imported/'):
        continue
    source = ROOT / relative
    if not source.is_file():
        missing.append(relative)
        continue
    destination = target / relative
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)
    copied += 1
for name in ('global_script_class_cache.cfg', 'uid_cache.bin'):
    source = ROOT / '.godot' / name
    if source.exists():
        (target / '.godot').mkdir(exist_ok=True)
        shutil.copy2(source, target / '.godot' / name)
identity = {p.relative_to(target).as_posix():hashlib.sha256(p.read_bytes()).hexdigest()
            for p in target.rglob('*') if p.is_file()}
(target/'isolation_identity.json').write_text(json.dumps({'archive_sha256':hashlib.sha256(archive.read_bytes()).hexdigest(),
 'diagnostic_overlay':args.diagnostic,'overlay_root':str(args.overlay_root) if args.overlay_root else None,'imported_copies':copied,'missing_imports':missing,'files':identity},indent=2),encoding='utf-8')
print(json.dumps({'path':str(target),'imported_copies':copied,'missing_imports':missing}))
