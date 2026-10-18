"""Run one visible GPU probe, pin exact sources, and retain failures unchanged."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import time
import zipfile

ROOT = Path(__file__).resolve().parents[2]
ENGINE = Path('D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe')


def digest(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--script', default='tests/floating_props/sample_probe.gd')
    parser.add_argument('--case', default='normal')
    parser.add_argument('--timeout', type=int, default=180)
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    spec = importlib.util.spec_from_file_location('audit', ROOT/'tools/unified_edit_pipeline/audit_architecture.py')
    audit = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(audit)
    sources, _, _ = audit.graph()
    # Include the inherited test helper closure in the pinned archive too.
    pending = [args.script, 'project.godot', 'tools/floating_props/run_probe.py',
               'tools/floating_props/verify_bottle.py', 'tools/floating_props/verify_sample.py',
               'task/sandcastle_floating_props/契约/probe_ABI_v1.json',
               'task/sandcastle_floating_props/契约/probe_ABI_v2.json']
    added = set()
    while pending:
        path = pending.pop()
        if path in added:
            continue
        added.add(path)
        if not (ROOT/path).is_file():
            continue
        raw = (ROOT/path).read_bytes()
        sources[path] = raw
        if Path(path).suffix in audit.TEXT:
            pending.extend(t.removeprefix('res://') for t in audit.PATH.findall(raw.decode('utf-8-sig')))
    hashes = {p: digest(b) for p, b in sources.items()}
    with zipfile.ZipFile(out/'sources.zip', 'x', zipfile.ZIP_DEFLATED) as archive:
        for path, data in sorted(sources.items()):
            archive.writestr(path, data)
    command = [str(ENGINE), '--path', str(ROOT), '--rendering-driver', 'd3d12',
               '--script', 'res://'+args.script, '--quit-after', '12000',
               '--log-file', str(out/'godot.log'), '--', '--output='+str(out/'probe.json'), '--case='+args.case]
    started = time.time()
    timed_out = False
    with (out/'stdout.txt').open('wb') as stream:
        process = subprocess.Popen(command, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT)
        try:
            exit_code = process.wait(timeout=args.timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            process.terminate()
            exit_code = process.wait(timeout=15)
    report = json.loads((out/'probe.json').read_text('utf-8-sig')) if (out/'probe.json').exists() else {}
    drift = [p for p, h in hashes.items() if not (ROOT/p).is_file() or digest((ROOT/p).read_bytes()) != h]
    log = (out/'godot.log').read_text('utf-8-sig') if (out/'godot.log').exists() else ''
    passed = exit_code == 0 and not timed_out and report.get('pass') is True and not drift and 'SCRIPT ERROR:' not in log
    manifest = dict(command=command, engine_sha256=digest(ENGINE.read_bytes()), started_unix=started,
                    elapsed_s=time.time()-started, exit_code=exit_code, timed_out=timed_out,
                    sources=hashes, source_zip_sha256=digest((out/'sources.zip').read_bytes()),
                    drift=drift, checks=len(report.get('checks', [])), **{'pass': passed})
    (out/'run-manifest.json').write_text(json.dumps(manifest, indent=2)+'\n', encoding='utf-8')
    print(json.dumps({k: manifest[k] for k in ['pass', 'checks', 'elapsed_s', 'exit_code', 'drift']}), flush=True)
    raise SystemExit(0 if passed else 1)


if __name__ == '__main__':
    main()
