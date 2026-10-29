"""Capture immutable G0 source identity; this is not a runtime/architecture PASS."""
from __future__ import annotations
import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path
import re
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[2]
ENTRIES = ['scenes/main.tscn', 'scenes/playable/test1_capture.tscn',
           'scenes/playable/test1_backwash.tscn']
TEXT = {'.gd', '.glsl', '.gdshader', '.tscn', '.tres', '.json', '.godot', '.import'}

def sha(path):
    return hashlib.file_digest(path.open('rb'), 'sha256').hexdigest()

def write(directory, name, value):
    (directory / name).write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf-8')

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--engine', type=Path, required=True)
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    # Broad inventory includes dynamically assembled shader paths; literal references
    # alone cannot prove runtime reachability or completeness.
    files = {ROOT / 'project.godot'}
    for directory in ['scripts', 'shaders', 'scenes', 'assets', 'tools/unified_edit_pipeline']:
        files.update(p for p in (ROOT / directory).rglob('*') if p.is_file()
                     and p.suffix in TEXT and '__pycache__' not in p.parts)
    files.update((ROOT / 'tools/unified_edit_pipeline').glob('*.py'))
    files.update((ROOT / 'tools/unified_edit_pipeline').glob('*.ps1'))
    edges, missing, pending = [], [], list(files)
    scanned = set()
    pattern = re.compile(r'res://[^\s\"\'<>\)\]}]+')
    while pending:
        path = pending.pop()
        if path in scanned:
            continue
        scanned.add(path)
        if path.suffix not in TEXT:
            continue
        source = path.read_text(encoding='utf-8-sig', errors='replace')
        for match in pattern.finditer(source):
            target = ROOT / match.group()[6:]
            row = {'source': path.relative_to(ROOT).as_posix(),
                   'line': source.count('\n', 0, match.start()) + 1,
                   'reference': match.group()}
            if target.is_file():
                edges.append(row)
                if target not in files:
                    files.add(target)
                    pending.append(target)
            else:
                missing.append(row)
    identities = {p.relative_to(ROOT).as_posix(): {'bytes': p.stat().st_size, 'sha256': sha(p)}
                  for p in sorted(files)}
    archive = out / 'reference_sources.zip'
    with zipfile.ZipFile(archive, 'x', zipfile.ZIP_DEFLATED) as package:
        for path in sorted(files):
            package.write(path, path.relative_to(ROOT).as_posix())
    status = subprocess.check_output(['git', 'status', '--porcelain=v1', '-z'], cwd=ROOT)
    (out / 'git_status.z').write_bytes(status)
    (out / 'working_tree.patch').write_bytes(subprocess.check_output(['git', 'diff', '--binary'], cwd=ROOT))
    manifest = {'created_at': dt.datetime.now(dt.timezone(dt.timedelta(hours=8))).isoformat(),
                'role': 'G0 source identity, not runtime validation', 'root': str(ROOT),
                'git_head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
                'engine': {'path': str(args.engine.resolve()), 'sha256': sha(args.engine),
                           'version': subprocess.check_output([str(args.engine), '--version'], text=True).strip()},
                'entries': ENTRIES, 'files': identities,
                'archive': {'path': str(archive), 'sha256': sha(archive)},
                'limits': ['Broad source/resource inventory, not all files are runtime reachable.',
                           'Literal references omit dynamic resource paths; missing references include prefixes.',
                           'User Godot instance is preserved; concurrent GPU activity requires runtime classification.']}
    write(out, 'baseline_manifest.json', manifest)
    write(out, 'literal_dependencies.json', {'edges': edges, 'unresolved_literals': missing})
    print(json.dumps({'output': str(out), 'files': len(files), 'archive_sha256': sha(archive)}))

if __name__ == '__main__':
    main()
