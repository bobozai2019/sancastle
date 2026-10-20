"""Run one diagnostic process and retain commands, source identity and raw fields."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import time
import shutil

ROOT = Path(__file__).resolve().parents[2]
ENGINE = Path('D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('mode', choices=['flat', 'flat_shovel', 'main'])
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    shutil.copy2(ROOT/'tools/wave_propagation/diagnose.gd', out/'probe.gd')
    cmd = [str(ENGINE), '--path', str(ROOT), '--rendering-driver', 'd3d12',
           '--script', 'res://tools/wave_propagation/diagnose.gd',
           '--log-file', str(out/'godot.log'), '--', '--mode='+args.mode, '--output='+str(out)]
    manifest = {'command': cmd, 'started_unix': time.time(), 'engine_sha256': sha(ENGINE),
                'probe_sha256': sha(ROOT/'tools/wave_propagation/diagnose.gd'),
                'other_processes': 'Existing user editor/game left running; no performance claim.'}
    with (out/'stdout.txt').open('w', encoding='utf-8') as log:
        child = subprocess.Popen(cmd, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
        manifest['pid'] = child.pid
        try:
            manifest['exit_code'] = child.wait(timeout=330)
        except subprocess.TimeoutExpired:
            child.terminate()
            manifest['exit_code'] = child.wait()
            manifest['timeout'] = True
    manifest['elapsed_s'] = time.time()-manifest['started_unix']
    manifest['probe_unchanged'] = manifest['probe_sha256'] == sha(ROOT/'tools/wave_propagation/diagnose.gd')
    (out/'manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    print(json.dumps(manifest), flush=True)
    print((out/'stdout.txt').read_text(encoding='utf-8', errors='replace')[-6000:], flush=True)
    raise SystemExit(manifest['exit_code'])


if __name__ == '__main__':
    main()
