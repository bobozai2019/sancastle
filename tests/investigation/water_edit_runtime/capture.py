"""Read-only runtime observation of an owned, hash-verified Sandcastle copy.

No original package writes, no game business-method hooks, no synthetic input.
Keep this host alive while the user operates; stop.json detaches without killing.
"""
import argparse
import collections
import datetime
import hashlib
import json
import queue
import shutil
import subprocess
import sys
import threading
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(HERE.parent / 'brush_hit_competitor/runtime_collider/deps'))
import frida

EXPECTED = '147030ecf9527a25250238120364eb761390b99688b1812c4ea555b3b04e56a0'


def identity(path):
    path = Path(path).resolve()
    h = hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda: f.read(1048576), b''):
            h.update(block)
    return dict(path=str(path), bytes=path.stat().st_size, sha256=h.hexdigest())


def save(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf8')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', required=True)
    ap.add_argument('--seconds', type=int, default=3600)
    ap.add_argument('--no-renderdoc', action='store_true')
    ap.add_argument('--prepare-only', action='store_true')
    ap.add_argument('--reuse', action='store_true')
    a = ap.parse_args()
    out = Path(a.out).resolve()
    out.mkdir(parents=True, exist_ok=a.reuse)
    source = ROOT / 'sandcastlegame'
    assert identity(source / 'GameAssembly.dll')['sha256'] == EXPECTED, 'unsupported source version'
    game = out / 'owned_game'
    if not a.reuse:
        rows = []
        for p in sorted(source.rglob('*')):
            if p.is_file() and p.suffix.lower() != '.rdc':
                dst = game / p.relative_to(source)
                dst.parent.mkdir(parents=True, exist_ok=True)
                src = identity(p)
                shutil.copy2(p, dst)
                copy = identity(dst)
                assert src['sha256'] == copy['sha256']
                rows.append(dict(source=src, copy=copy))
        save(out / 'copy_manifest.json', rows)
        profile = Path.home() / 'AppData/LocalLow/BubblebirdStudio/Sandcastle'
        if profile.is_dir():
            # Copy user data before a normal game launch may autosave it.
            rows = []
            for p in profile.rglob('*'):
                if p.is_file() and p.suffix.lower() not in ('.log', '.txt'):
                    dest = out / 'user_data_before' / p.relative_to(profile)
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(p, dest)
                    rows.append(dict(source=identity(p), backup=identity(dest)))
            save(out / 'user_data_before.json', rows)
    for row in json.loads((out / 'copy_manifest.json').read_text('utf8')):
        assert identity(row['copy']['path'])['sha256'] == row['copy']['sha256']
    if a.prepare_only:
        print(out, flush=True)
        return
    attempt = out / ('session_' + datetime.datetime.now().strftime('%Y%m%d_%H%M%S'))
    attempt.mkdir()
    (attempt / 'raw').mkdir()
    (attempt / 'rdc').mkdir()
    agent = HERE / 'agent.js'
    shutil.copy2(agent, attempt / 'agent.js')
    shutil.copy2(__file__, attempt / 'capture.py')
    renderdoc = Path('D:/other_software/RenderDoc/renderdoc.dll')
    cfg = dict(renderdoc=None if a.no_renderdoc else str(renderdoc),
               capture_prefix=str(attempt / 'rdc/water_edit'),
               snapshot_active_ms=100, snapshot_idle_ms=10000,
               max_raw_bytes=8 * 1024**3, max_captures=12,
               expected_gameassembly_sha256=EXPECTED)
    save(attempt / 'manifest.json', dict(frida=frida.__version__, python=sys.version,
        command=sys.argv, agent=identity(agent), driver=identity(__file__),
        renderdoc=None if a.no_renderdoc else identity(renderdoc), config=cfg,
        source_manifest=str(out / 'copy_manifest.json'),
        scope='Unity compute submission, uploads, published Readback cache; not GPU timing or business code'))
    records = queue.Queue(maxsize=2048)
    counts = collections.Counter()
    errors = []
    dropped = 0
    raw_total = 0
    last = {}

    def writer():
        nonlocal raw_total
        with (attempt / 'events.jsonl').open('a', encoding='utf8') as log:
            while True:
                item = records.get()
                if item is None:
                    records.task_done()
                    break
                message, data, received = item
                payload = message.get('payload', {})
                kind = payload.get('kind', message['type'])
                counts[kind] += 1
                row = dict(received_monotonic_ns=str(received), message=message)
                if data is not None:
                    p = attempt / 'raw' / ('%012d.bin' % counts['raw_file'])
                    counts['raw_file'] += 1
                    p.write_bytes(data)
                    raw_total += len(data)
                    row['raw'] = identity(p)
                if message['type'] == 'error' or kind in ('error', 'hook_error', 'install_error'):
                    errors.append(message)
                last[kind] = {k:v for k,v in payload.items() if k not in ('events', 'methods')}
                log.write(json.dumps(row, ensure_ascii=False) + '\n')
                log.flush()
                records.task_done()

    worker = threading.Thread(target=writer, daemon=True)
    worker.start()
    dev = frida.get_local_device()
    argv = [str(game / 'Sandcastle.exe'), '-screen-fullscreen', '0',
            '-screen-width', '1280', '-screen-height', '720', '-force-d3d11',
            '-logFile', str(attempt / 'player.log')]
    if a.no_renderdoc:
        pid = dev.spawn(argv, cwd=str(game))
    else:
        # RenderDoc initializes its graphics hooks before Frida is attached.
        # Module.load(renderdoc.dll) from a Frida callback stalled device creation
        # in session_20261019_000744; preserve that attempt as a failed startup.
        launch_args = [str(renderdoc.with_name('renderdoccmd.exe')), 'capture',
            '-d', str(game), '-c', cfg['capture_prefix'],
            '--opt-delay-for-debugger', '15', *argv]
        before = {p.pid for p in dev.enumerate_processes()}
        launch_log = (attempt / 'renderdoc_launch.log').open('wb')
        launcher = subprocess.Popen(launch_args, stdout=launch_log, stderr=subprocess.STDOUT)
        pid = None
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            candidates = [p.pid for p in dev.enumerate_processes()
                          if p.pid not in before and p.name.lower() == 'sandcastle.exe']
            if candidates:
                assert len(candidates) == 1, 'ambiguous newly launched process'
                pid = candidates[0]
                break
            time.sleep(.1)
        assert pid is not None, 'RenderDoc did not launch game'
        save(attempt / 'launcher.json', dict(pid=launcher.pid, argv=launch_args, target_pid=pid))
    save(attempt / 'owner.json', dict(pid=pid, argv=argv, host_pid=__import__('os').getpid(),
        created_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
        ownership='created by water_edit_runtime', launch_mode='frida_spawn' if a.no_renderdoc else 'renderdoc_capture'))
    save(out / 'current_session.json', dict(path=str(attempt), pid=pid))
    print('SESSION=' + str(attempt), flush=True)
    print('GAME_PID=' + str(pid), flush=True)
    session = None
    script = None
    resumed = False
    started = time.monotonic()
    try:
        session = dev.attach(pid)
        script = session.create_script('globalThis.PROBE_CONFIG=' + json.dumps(cfg) + ';\n' + agent.read_text('utf8'))
        def message(message, data):
            nonlocal dropped
            try:
                records.put_nowait((message, data, time.monotonic_ns()))
            except queue.Full:
                dropped += 1
        script.on('message', message)
        script.load()
        if a.no_renderdoc:
            dev.resume(pid)
        resumed = True
        while time.monotonic() - started < a.seconds and not session.is_detached:
            save(attempt / 'status.json', dict(pid=pid, active=True,
                elapsed_seconds=time.monotonic()-started, counts=dict(counts),
                queue_backlog=records.qsize(), dropped_messages=dropped,
                raw_bytes=raw_total, errors=errors[-10:], last=last,
                free_bytes=shutil.disk_usage(out).free))
            if (attempt / 'stop.json').exists():
                break
            if shutil.disk_usage(out).free < 2 * 1024**3:
                save(attempt / 'storage_stop.json', dict(reason='less than 2 GiB free'))
                break
            time.sleep(1)
    except Exception as e:
        save(attempt / 'failure.json', dict(type=type(e).__name__, message=str(e)))
        raise
    finally:
        if session and not session.is_detached:
            if script:
                try:
                    script.exports_sync.flush()
                    script.unload()
                except Exception as e:
                    errors.append(dict(cleanup_error=str(e)))
            session.detach()
        if not resumed and a.no_renderdoc:
            dev.resume(pid)
        records.put(None)
        worker.join(timeout=30)
        save(attempt / 'status_final.json', dict(pid=pid, active=False,
            counts=dict(counts), errors=errors, dropped_messages=dropped,
            raw_bytes=raw_total, process='left running; no termination requested'))
        # Captures are indexed only after recording has stopped.
        save(attempt / 'rdc_index.json', [identity(p) for p in (attempt / 'rdc').glob('*.rdc')])


if __name__ == '__main__':
    main()
