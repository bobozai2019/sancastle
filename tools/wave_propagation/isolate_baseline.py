"""Make a self-contained runtime copy and reject concurrent source changes."""
import hashlib
import json
from pathlib import Path
import re
import argparse

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--destination',type=Path,default=ROOT/'test_output/wave_propagation/g0_workspace_20261020')
    destination=parser.parse_args().destination.resolve()
    destination.mkdir(parents=True, exist_ok=False)
    paths = [ROOT / 'project.godot', ROOT / 'icon.svg']
    for name in ('scripts', 'shaders', 'scenes', 'assets', 'addons', 'tools/wave_propagation', '.godot/imported'):
        paths.extend(p for p in (ROOT / name).rglob('*') if p.is_file() and '__pycache__' not in p.parts)
    for name in ('uid_cache.bin', 'global_script_class_cache.cfg'):
        p = ROOT / '.godot' / name
        if p.exists():
            paths.append(p)
    fixture = ROOT / 'test_output/wave_propagation/g0_baseline_20261020/fixture.json'
    paths.append(fixture)
    # Retained legacy entry scripts preload research prototypes outside scripts/.
    # Copy their file dependencies without copying development outputs or tokens.
    pending = [p for p in paths if p.suffix in ('.gd', '.tscn', '.tres')]
    known = set(paths)
    while pending:
        p = pending.pop()
        for relative in re.findall(r'res://([^"\s\)]+)', p.read_text(encoding='utf-8')):
            dependency = ROOT / relative
            if not relative.startswith('tests/') or not dependency.is_file() or dependency in known:
                continue
            known.add(dependency)
            paths.append(dependency)
            if dependency.suffix in ('.gd', '.tscn', '.tres'):
                pending.append(dependency)
    for p in list(paths):
        metadata = Path(str(p) + '.import')
        if metadata.is_file() and metadata not in known:
            known.add(metadata)
            paths.append(metadata)
    identity = {}
    for p in paths:
        relative = p.relative_to(ROOT).as_posix()
        raw = p.read_bytes()
        digest = hashlib.sha256(raw).hexdigest()
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(raw)
        identity[relative] = {'sha256': digest, 'bytes': len(raw)}
    drift = [str(p.relative_to(ROOT)) for p in paths
             if hashlib.sha256(p.read_bytes()).hexdigest() != identity[p.relative_to(ROOT).as_posix()]['sha256']]
    (destination / 'snapshot_identity.json').write_text(json.dumps({
        'source_root': str(ROOT), 'runtime_root': str(destination), 'files': identity,
        'drift_during_copy': drift, 'pass': not drift,
        'note': 'Independent file bytes, no links. User runtime and in-progress changes retained.'
    }, indent=2), encoding='utf-8')
    if drift:
        raise RuntimeError('Source changed during copy: ' + repr(drift))
    print(destination)


if __name__ == '__main__':
    main()
