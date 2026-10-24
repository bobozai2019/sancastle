"""Freeze current runtime inputs and collect serial round-two baseline evidence."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time
import zipfile

ROOT = Path(__file__).resolve().parents[2]
TASK = ROOT / 'task/muscl_performance_round2'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf-8')


def freeze():
    target = TASK / '验收/baseline'
    target.mkdir(parents=True, exist_ok=False)
    files = [ROOT / 'project.godot', ROOT / 'icon.svg']
    for folder in ('scripts', 'shaders', 'scenes', 'assets', 'addons', 'tools'):
        files.extend(p for p in (ROOT / folder).rglob('*') if p.is_file())
    # These prototypes are live presentation and inherited script dependencies.
    files.extend(p for p in (ROOT / 'tests').rglob('*') if p.is_file() and
                 (p.suffix in ('.gd', '.glsl', '.glslinc', '.gdshader', '.tres', '.tscn', '.uid', '.json', '.import') or
                  'visual_water_alignment/prototypes/' in p.as_posix()))
    identity = {p.relative_to(ROOT).as_posix(): digest(p) for p in sorted(set(files))}
    with zipfile.ZipFile(target / 'runtime.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
        for relative in identity:
            archive.write(ROOT / relative, relative)
    write(target / 'identity.json', identity)
    reference = TASK / 'reference'
    reference.mkdir(exist_ok=False)
    for relative in identity:
        if relative.startswith(('scripts/simulation/unified_edit/', 'shaders/simulation/muscl/')):
            destination = reference / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / relative, destination)
    write(reference / 'identity.json', identity)
    source = Path(os.environ['APPDATA']) / 'Godot/app_userdata/sandcastle/parameters'
    for name in ('startup.json', 'windows.cfg'):
        if (source / name).exists():
            shutil.copy2(source / name, target / name)
    if not (target / 'startup.json').exists():
        write(target / 'startup.json', {'version': 1, 'scenes': {}})
    write(target / 'freeze.json', {'archive_sha256': digest(target / 'runtime.zip'),
          'parameter_source': str(source), 'parameter_hashes': {n: digest(source / n) for n in ('startup.json', 'windows.cfg')},
          'git_head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
          'git_status': subprocess.check_output(['git', 'status', '--porcelain=v1', '-z'], cwd=ROOT).decode('utf-8'),
          'input_sequence': 'scene: no user input; exact: fixtures and dt sequence in archived exact probe'})
    print('Frozen', len(identity), 'files', flush=True)


def run(engine, run_id, mode):
    destination = TASK / '验收' / run_id
    destination.mkdir(parents=True, exist_ok=False)
    temporary = ROOT / 'test_output/muscl_performance_round2' / run_id
    temporary.mkdir(parents=True, exist_ok=False)
    baseline = TASK / '验收/baseline'
    parameters = temporary / 'parameters'
    parameters.mkdir()
    shutil.copy2(baseline / 'startup.json', parameters / 'startup.json')
    if (baseline / 'windows.cfg').exists():
        shutil.copy2(baseline / 'windows.cfg', parameters / 'windows.cfg')
    identity = json.loads((baseline / 'identity.json').read_text(encoding='utf-8'))
    for path in (ROOT / 'tools/muscl_performance').glob('*'):
        if path.is_file():
            identity.setdefault(path.relative_to(ROOT).as_posix(), None)
    before = {p: digest(ROOT / p) for p in identity}
    real = Path(os.environ['APPDATA']) / 'Godot/app_userdata/sandcastle/parameters'
    user_before = {n: digest(real / n) for n in ('startup.json', 'windows.cfg')}
    script = {'exact': 'tests/integration/water_execution_exact_probe.gd',
              'scene': 'tools/muscl_performance/scene_baseline.gd',
              'diagnostic': 'tools/muscl_performance/diagnostic_scene.gd',
              'diagnostic-exact': 'tools/muscl_performance/diagnostic_exact.gd',
              'diagnostic-lifecycle': 'tools/muscl_performance/diagnostic_lifecycle.gd'}[mode]
    command = [str(engine), '--path', str(ROOT), '--rendering-method', 'forward_plus', '--rendering-driver', 'd3d12',
               '--resolution', '1280x720', '--script', 'res://' + script, '--',
               '--output=' + temporary.as_posix(), '--parameter-config=' + (parameters / 'startup.json').as_posix()]
    if mode in ('exact', 'diagnostic-exact'):
        command += ['--reference=res://task/muscl_performance_round2/reference/']
    (destination / 'command.txt').write_text(subprocess.list2cmdline(command), encoding='utf-8')
    started = time.time()
    with (destination / 'run.log').open('w', encoding='utf-8') as log:
        process = subprocess.Popen(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
        write(destination / 'process.json', {'pid': process.pid, 'started_unix': started, 'command': command})
        code = process.wait()
    for name in ('capture.json', 'exact.json', 'source_hashes.json', 'scene.png', 'isolation.json', 'diagnostic_exact.json', 'lifecycle.json'):
        if (temporary / name).exists():
            shutil.copy2(temporary / name, destination / name)
    shutil.copytree(parameters, destination / 'parameters')
    after = {p: digest(ROOT / p) for p in identity}
    source_snapshot = destination / 'sources'
    for relative in before:
        if before[relative] != identity[relative]:
            source = ROOT / relative
            if source.is_file():
                target = source_snapshot / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, target)
    user_after = {n: digest(real / n) for n in user_before}
    write(destination / 'manifest.json', {'run_id': run_id, 'mode': mode, 'exit_code': code,
          'duration_s': time.time() - started, 'engine': str(engine), 'engine_sha256': digest(engine),
          'source_hashes': before, 'source_drift': [p for p in before if before[p] != after[p]],
          'baseline_differences': [p for p in before if before[p] != identity[p]],
          'user_before': user_before, 'user_after': user_after, 'user_unchanged': user_before == user_after,
          'parameter_initial_sha256': digest(baseline / 'startup.json'),
          'artifacts': {p.name: digest(p) for p in destination.iterdir() if p.is_file()}})
    print(run_id, 'exit', code, 'user unchanged', user_before == user_after, flush=True)
    if code:
        raise SystemExit(code)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('freeze', 'scene', 'exact', 'diagnostic', 'diagnostic-exact', 'diagnostic-lifecycle'))
    parser.add_argument('--run-id')
    parser.add_argument('--engine', type=Path, default=Path('D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'))
    args = parser.parse_args()
    if args.action == 'freeze':
        freeze()
    else:
        if not args.run_id:
            parser.error('--run-id required')
        run(args.engine, args.run_id, args.action)
