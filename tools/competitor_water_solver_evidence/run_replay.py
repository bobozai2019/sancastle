"""Validate a request and launch one hidden RenderDoc embedded Python process."""
import argparse
import datetime
import json
import os
import subprocess
from pathlib import Path
from evidence_contract import identity, validate


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--request', required=True, type=Path)
    parser.add_argument('--script', type=Path, default=Path(__file__).with_name('pilot_replay.py'))
    parser.add_argument('--renderdoc', type=Path, default=Path('D:/other_software/RenderDoc/qrenderdoc.exe'))
    args = parser.parse_args()
    request_path = args.request.resolve()
    request = json.loads(request_path.read_text(encoding='utf-8'))
    errors = validate(request)
    if errors:
        print(json.dumps(dict(operation_status='failed', verification_status='not_evaluated', errors=errors)))
        raise SystemExit(1)
    env = dict(os.environ, WATER_EVIDENCE_REQUEST=request_path.as_posix(), WATER_EVIDENCE_SCRIPT=args.script.resolve().as_posix())
    command = [str(args.renderdoc), '--python', str(args.script.resolve())]
    identities = dict(request=identity(request_path), script=identity(args.script), executable=identity(args.renderdoc))
    start = datetime.datetime.now(datetime.timezone.utc).isoformat()
    startup = subprocess.STARTUPINFO()
    startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = 0
    process = subprocess.Popen(command, env=env, startupinfo=startup, creationflags=subprocess.CREATE_NO_WINDOW)
    print(json.dumps(dict(pid=process.pid, command=command, start=start)), flush=True)
    code = process.wait()
    result = dict(pid=process.pid, command=command, started_at=start,
                  finished_at=datetime.datetime.now(datetime.timezone.utc).isoformat(), exit_code=code,
                  **identities)
    out = Path(request['output_root'])
    if out.is_dir():
        (out / 'logs/launch.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
    print(json.dumps(result), flush=True)
    raise SystemExit(code)


if __name__ == '__main__':
    main()
