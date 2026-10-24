"""Capture identities and run the existing visible baseline probe, serially."""
import datetime
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'task/water_foam_visual/验收/G0/baseline_20261024'
ENGINE = Path('D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe')

def sha(path):
    return hashlib.file_digest(path.open('rb'), 'sha256').hexdigest()

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / '.gdignore').touch()
    source = json.loads((ROOT / 'task/water_foam_visual/计划来源.json').read_text(encoding='utf-8-sig'))
    rows = []
    for old in source['sources']:
        path = ROOT / old['path']
        current = sha(path) if path.is_file() else None
        rows.append(dict(path=old['path'], planned_sha256=old['sha256'], current_sha256=current, matches=current == old['sha256']))
    status = subprocess.run(['git', 'status', '--porcelain=v1', '-z'], cwd=ROOT, capture_output=True, check=True)
    (OUT / 'worktree_status.bin').write_bytes(status.stdout)
    version = subprocess.run([str(ENGINE), '--version'], capture_output=True, text=True, timeout=20, check=True).stdout.strip()
    identity = dict(captured_at=datetime.datetime.now(datetime.timezone.utc).isoformat(), engine=str(ENGINE), version=version, engine_sha256=sha(ENGINE), sources=rows, optimization_used_s=0)
    (OUT / 'identity.json').write_text(json.dumps(identity, ensure_ascii=False, indent=2), encoding='utf-8')
    for scene in ['main', 'test1_geometry']:
        dest = OUT / scene
        dest.mkdir(exist_ok=True)
        command = [str(ENGINE), '--path', str(ROOT), '--script', 'res://docs/competitor/tools/probe_foam_comparison.gd', '--', '--scene=' + scene, '--output=res://' + dest.relative_to(ROOT).as_posix()]
        (dest / 'command.json').write_text(json.dumps(command, ensure_ascii=False, indent=2), encoding='utf-8')
        with (dest / 'stdout.log').open('wb') as stdout, (dest / 'stderr.log').open('wb') as stderr:
            try:
                result = subprocess.run(command, cwd=ROOT, stdout=stdout, stderr=stderr, timeout=600)
                outcome = dict(exit_code=result.returncode, timeout=False)
            except subprocess.TimeoutExpired:
                outcome = dict(exit_code=None, timeout=True)
        (dest / 'result.json').write_text(json.dumps(outcome), encoding='utf-8')
        print(scene, outcome, flush=True)

if __name__ == '__main__':
    main()
