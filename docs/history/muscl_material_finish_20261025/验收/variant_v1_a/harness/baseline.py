"""Freeze current runtime inputs and collect serial round-two baseline evidence."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
import zipfile
from context import add_arguments, resolve, baseline_paths

ROOT = Path(__file__).resolve().parents[2]
TASK = ROOT / 'task/muscl_performance_round2'
TEMP = ROOT / 'test_output/muscl_performance_round2'
BASELINE = TASK / '验收/baseline'
REFERENCE = TASK / 'reference'


def configure(args):
    global TASK, TEMP, BASELINE, REFERENCE
    TASK, TEMP = resolve(args)
    BASELINE, REFERENCE = baseline_paths(args,TASK)
_RUNNER_BYTES=Path(__file__).read_bytes()
_LAUNCHER_PATH=Path(sys.argv[0]).resolve()
_LAUNCHER_BYTES=_LAUNCHER_PATH.read_bytes() if _LAUNCHER_PATH.is_file() else None


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf-8')


def freeze(parameter_source=None):
    target = BASELINE
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
    reference = REFERENCE
    reference.mkdir(exist_ok=False)
    for relative in identity:
        if relative.startswith(('scripts/simulation/unified_edit/', 'shaders/simulation/muscl/')):
            destination = reference / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / relative, destination)
    write(reference / 'identity.json', identity)
    source = parameter_source or Path(os.environ['APPDATA']) / 'Godot/app_userdata/sandcastle/parameters'
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


def run(engine, run_id, mode, source_root=ROOT,extra_args=(),telemetry=False):
    destination = TASK / '验收' / run_id
    destination.mkdir(parents=True, exist_ok=False)
    harness=destination/'harness'
    harness.mkdir()
    (harness/'baseline.py').write_bytes(_RUNNER_BYTES)
    if _LAUNCHER_BYTES is not None:(harness/'launcher.py').write_bytes(_LAUNCHER_BYTES)
    temporary = TEMP / run_id
    temporary.mkdir(parents=True, exist_ok=False)
    baseline = BASELINE
    parameters = temporary / 'parameters'
    parameters.mkdir()
    shutil.copy2(baseline / 'startup.json', parameters / 'startup.json')
    if (baseline / 'windows.cfg').exists():
        shutil.copy2(baseline / 'windows.cfg', parameters / 'windows.cfg')
    identity = json.loads((baseline / 'identity.json').read_text(encoding='utf-8'))
    def source_paths():
        paths = set(identity)
        for folder in ('scripts', 'shaders', 'scenes', 'assets', 'addons', 'tools', 'tests'):
            paths.update(p.relative_to(source_root).as_posix() for p in (source_root/folder).rglob('*')
                         if p.is_file() and '__pycache__' not in p.parts)
        return paths
    before = {p: digest(source_root / p) for p in source_paths()}
    real = Path(os.environ['APPDATA']) / 'Godot/app_userdata/sandcastle/parameters'
    user_before = {n: digest(real / n) for n in ('startup.json', 'windows.cfg')}
    script = {'exact': 'tests/integration/water_execution_exact_probe.gd',
              'scene': 'tools/muscl_performance/scene_baseline.gd',
              'diagnostic': 'tools/muscl_performance/diagnostic_scene.gd',
              'diagnostic-exact': 'tools/muscl_performance/diagnostic_exact.gd',
              'diagnostic-lifecycle': 'tools/muscl_performance/diagnostic_lifecycle.gd',
              'dependency': 'tools/muscl_performance/list_dependency_probe.gd',
              'cost': 'tools/muscl_performance/cost_scene.gd',
              'special': 'tools/wave_propagation/special_gpu_probe.gd',
              'shared-boundary': 'tools/muscl_performance/shared_boundary_exact.gd',
              'variant': 'tools/muscl_performance/variant_states.gd',
              'first-order': 'tools/muscl_performance/first_order_support.gd',
              'indirect': 'tools/muscl_performance/indirect_states.gd',
              'footprint': 'tools/muscl_performance/cache_footprint.gd',
              'initialization': 'tools/muscl_performance/initialization_probe.gd',
              'flat': 'tools/muscl_performance/flat_cost.gd',
              'restart': 'tools/muscl_performance/restart_probe.gd',
              'formal-states': 'tools/muscl_performance/formal_states.gd',
              'inline-material': 'tools/muscl_performance/inline_material_probe.gd',
              'formal-inputs': 'tools/muscl_performance/formal_inputs.gd',
              'material-inputs': 'tools/muscl_performance/formal_material_inputs.gd',
              'continuous': 'tools/muscl_performance/continuous_scene.gd',
              'promotion-mixed': 'tools/muscl_performance/promotion_mixed.gd',
              'input-cost': 'tools/muscl_performance/input_cost.gd',
              'main-live': 'tools/muscl_performance/main_live.gd',
              'dispatch-trace': 'tools/muscl_performance/dispatch_trace.gd',
              'core-local': 'tools/muscl_performance/core_local.gd',
              'publication': 'tools/muscl_performance/publication_probe.gd',
              'policies': 'tools/muscl_performance/policies_probe.gd',
              'checkpoint-lifecycle': 'tools/muscl_performance/checkpoint_lifecycle.gd',
              'scene-service': 'tools/muscl_performance/scene_service.gd',
              'efficiency': 'tools/muscl_performance/efficiency_scene.gd',
              'efficiency-diagnostic': 'tools/muscl_performance/efficiency_diagnostic_scene.gd',
              'efficiency-exact': 'tools/muscl_performance/efficiency_diagnostic_exact.gd'}[mode]
    command = [str(engine), '--path', str(source_root), '--rendering-method', 'forward_plus', '--rendering-driver', 'd3d12',
               '--resolution', '1280x720', '--script', 'res://' + script, '--',
               '--output=' + temporary.as_posix(), '--parameter-config=' + (parameters / 'startup.json').as_posix()]
    if mode in ('exact', 'diagnostic-exact', 'shared-boundary', 'efficiency-exact'):
        command += ['--reference=' + REFERENCE.as_posix() + '/']
    command += list(extra_args)
    (destination / 'command.txt').write_text(subprocess.list2cmdline(command), encoding='utf-8')
    started = time.time()
    telemetry_info=None
    telemetry_process=None
    telemetry_output=None
    telemetry_error=None
    smi=shutil.which('nvidia-smi') if telemetry else None
    if smi:
        telemetry_command=[smi,'--query-gpu=timestamp,pstate,clocks.gr,clocks.mem,temperature.gpu,utilization.gpu','--format=csv','--loop=1']
        telemetry_output=(destination/'gpu_telemetry.csv').open('w',encoding='utf-8')
        telemetry_error=(destination/'gpu_telemetry_stderr.txt').open('w',encoding='utf-8')
        telemetry_process=subprocess.Popen(telemetry_command,stdout=telemetry_output,stderr=telemetry_error,creationflags=subprocess.CREATE_NO_WINDOW if os.name=='nt' else 0)
        telemetry_info={'command':telemetry_command,'binary_sha256':digest(Path(smi)),'pid':telemetry_process.pid}
    with (destination / 'run.log').open('w', encoding='utf-8') as log:
        try:
            process = subprocess.Popen(command, cwd=source_root, stdout=log, stderr=subprocess.STDOUT)
            write(destination / 'process.json', {'pid': process.pid, 'started_unix': started, 'command': command,'telemetry':telemetry_info})
            code = process.wait()
        finally:
            if telemetry_process is not None:
                if telemetry_process.poll() is None:telemetry_process.terminate()
                telemetry_info['exit_code']=telemetry_process.wait(timeout=5)
                telemetry_output.close();telemetry_error.close()
    engine_errors=[line for line in (destination/'run.log').read_text(encoding='utf-8',errors='replace').splitlines() if line.startswith(('ERROR:','SCRIPT ERROR:'))]
    for name in ('capture.json', 'exact.json', 'source_hashes.json', 'scene.png', 'isolation.json', 'diagnostic_exact.json', 'lifecycle.json', 'dependency.json', 'result.json', 'variant.json', 'states.zip', 'footprint.json', 'trace_source.txt'):
        if (temporary / name).exists():
            shutil.copy2(temporary / name, destination / name)
    for path in temporary.glob('*.bin'):
        shutil.copy2(path,destination/path.name)
    if (temporary/'data').is_dir():shutil.copytree(temporary/'data',destination/'data')
    shutil.copytree(parameters, destination / 'parameters')
    if (source_root / 'isolation_identity.json').exists():
        shutil.copy2(source_root / 'isolation_identity.json', destination / 'isolation_identity.json')
    after = {p: digest(source_root / p) for p in source_paths()}
    source_snapshot = destination / 'sources'
    for relative in before:
        if before[relative] != identity.get(relative):
            source = source_root / relative
            if source.is_file():
                target = source_snapshot / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, target)
    user_after = {n: digest(real / n) for n in user_before}
    write(destination / 'manifest.json', {'run_id': run_id, 'mode': mode, 'source_root':str(source_root), 'exit_code': code,
          'engine_errors':engine_errors,'validated_exit_code':code if code else (1 if engine_errors else 0),'baseline_root':str(BASELINE),'reference_root':str(REFERENCE),
          'runner_sha256':hashlib.sha256(_RUNNER_BYTES).hexdigest(),'launcher_path':str(_LAUNCHER_PATH),
          'telemetry':telemetry_info,'telemetry_requested':telemetry,
          'launcher_sha256':hashlib.sha256(_LAUNCHER_BYTES).hexdigest() if _LAUNCHER_BYTES is not None else None,
          'duration_s': time.time() - started, 'engine': str(engine), 'engine_sha256': digest(engine),
          'source_hashes': before, 'source_drift': [p for p in sorted(set(before)|set(after)) if before.get(p) != after.get(p)],
          'baseline_differences': [p for p in sorted(set(before)|set(identity)) if before.get(p) != identity.get(p)],
          'user_before': user_before, 'user_after': user_after, 'user_unchanged': user_before == user_after,
          'parameter_initial_sha256': digest(baseline / 'startup.json'),
          'artifacts': {p.name: digest(p) for p in destination.iterdir() if p.is_file()}})
    print(run_id, 'exit', code, 'user unchanged', user_before == user_after, flush=True)
    if code:
        raise SystemExit(code)
    if engine_errors:raise SystemExit(1)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    add_arguments(parser)
    parser.add_argument('action', choices=('freeze', 'scene', 'exact', 'diagnostic', 'diagnostic-exact', 'diagnostic-lifecycle', 'dependency', 'cost', 'special', 'shared-boundary', 'variant', 'first-order', 'indirect', 'footprint', 'initialization', 'flat', 'restart', 'formal-states', 'inline-material', 'formal-inputs', 'material-inputs', 'continuous', 'promotion-mixed', 'input-cost', 'main-live', 'dispatch-trace', 'core-local', 'publication', 'policies', 'checkpoint-lifecycle', 'scene-service', 'efficiency'))
    parser.add_argument('--run-id')
    parser.add_argument('--parameter-source', type=Path, help='Read-only startup/window inputs for a new freeze')
    parser.add_argument('--source-root',type=Path,default=ROOT)
    parser.add_argument('--duration',type=float)
    parser.add_argument('--ticks',type=int)
    parser.add_argument('--input',type=Path)
    parser.add_argument('--cpu-only',action='store_true')
    parser.add_argument('--case')
    parser.add_argument('--scene',help='Explicit formal scene path, forwarded to the selected probe')
    parser.add_argument('--retry-cases-only',action='store_true')
    parser.add_argument('--telemetry',action='store_true')
    parser.add_argument('--backlog',action='store_true',help='Developer efficiency supply mode; retains production queue limits')
    parser.add_argument('--engine', type=Path, default=Path('D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'))
    args = parser.parse_args()
    configure(args)
    if args.action == 'freeze':
        freeze(args.parameter_source)
    else:
        if not args.run_id:
            parser.error('--run-id required')
        extra=[]
        if args.duration is not None:extra.append('--duration='+str(args.duration))
        if args.ticks is not None:extra.append('--ticks='+str(args.ticks))
        if args.input is not None:extra.append('--input='+args.input.resolve().as_posix())
        if args.cpu_only:extra.append('--cpu-only')
        if args.case:extra.append('--case='+args.case)
        if args.scene:extra.append('--scene='+args.scene)
        if args.retry_cases_only:extra.append('--retry-cases-only')
        if args.backlog:extra.append('--backlog')
        run(args.engine, args.run_id, args.action,args.source_root.resolve(),extra,args.telemetry)
