"""Run the frozen G0 matrix; never treat probe completion as numeric acceptance."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
ENGINE = Path('D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('mode', choices=['flat', 'main'])
    ap.add_argument('output', type=Path)
    args = ap.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    probe = ROOT / 'tools/wave_propagation/baseline_probe.gd'
    digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
    sources = {str(p): digest(p) for p in [probe, ENGINE, ROOT / 'test_output/wave_propagation/g0_baseline_20261020/fixture.json']}
    (out / 'probe.gd').write_bytes(probe.read_bytes())
    cmd = [str(ENGINE), '--path', str(ROOT), '--rendering-driver', 'd3d12',
           '--script', 'res://tools/wave_propagation/baseline_probe.gd',
           '--log-file', str(out / 'godot.log'), '--', '--mode=' + args.mode, '--output=' + str(out)]
    manifest = {'command': cmd, 'sources': sources, 'started_unix': time.time(),
                'scope': 'Numeric baseline; no performance claim. Existing user processes retained.'}
    with (out / 'stdout.txt').open('w', encoding='utf-8') as log:
        child = subprocess.Popen(cmd, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
        manifest['pid'] = child.pid
        (out / 'manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
        try:
            manifest['exit_code'] = child.wait(timeout=930)
        except subprocess.TimeoutExpired:
            child.terminate()
            manifest['exit_code'] = child.wait()
            manifest['timeout'] = True
    manifest['elapsed_s'] = time.time() - manifest['started_unix']
    manifest['source_drift'] = [p for p, h in sources.items() if digest(Path(p)) != h]
    diagnosis = out / 'diagnosis.json'
    manifest['outcome'] = 'incomplete'
    if diagnosis.is_file():
        report = json.loads(diagnosis.read_text(encoding='utf-8'))
        manifest['outcome'] = 'pass' if report.get('pass') and not report.get('source_drift') else 'fail'
    if manifest['exit_code'] or manifest['source_drift']:
        manifest['outcome'] = 'fail'
    (out / 'manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    print(json.dumps(manifest, indent=2))
    print((out / 'stdout.txt').read_text(encoding='utf-8', errors='replace')[-4000:])
    raise SystemExit(manifest['exit_code'] or int(manifest['outcome'] != 'pass'))


if __name__ == '__main__':
    main()
