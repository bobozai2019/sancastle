"""Freeze the G0 input and create an isolated probe without altering old evidence."""
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    destination = ROOT / 'test_output/wave_propagation/g0_baseline_20261020'
    destination.mkdir(parents=True, exist_ok=False)
    tracked = subprocess.check_output(['git', 'ls-files', '-z'], cwd=ROOT).decode().split('\0')
    paths = set(p for p in tracked if p and p.endswith(('.gd', '.glsl', '.tscn', '.tres', '.godot', '.py')))
    paths.update(p.relative_to(ROOT).as_posix() for p in (ROOT / 'tools/wave_propagation').glob('*') if p.is_file())
    identity = {p: {'sha256': sha(ROOT / p), 'bytes': (ROOT / p).stat().st_size}
                for p in sorted(paths) if (ROOT / p).is_file()}
    (destination / 'source_identity.json').write_text(json.dumps({
        'head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT).decode().strip(),
        'status': subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT).decode(),
        'files': identity,
        'entry': 'res://scenes/main.tscn',
        'note': 'Pre-existing changes retained. Numeric probes are not cost measurements.',
    }, indent=2), encoding='utf-8')
    cases = []
    for depth in (.05, .1, .2):
        for amplitude in (.0001, .0002):
            for wavelength in (.5, 1., 2., 4.):
                cases.append({'id': f'sine_h{depth:g}_a{amplitude:g}_l{wavelength:g}',
                              'kind': 'sine', 'depth': depth, 'amplitude': amplitude,
                              'wavelength': wavelength})
    cases += [{'id': name, 'kind': kind, 'depth': .1, 'amplitude': .0001,
               'wavelength': 1., 'speed': speed}
              for name, kind, speed in [('flat_control', 'control', 0.),
                                         ('radial_pulse', 'pulse', 0.), ('shovel_B', 'shovel', .25)]]
    fixture = {'schema': 1, 'solver_id': 'rusanov_first_order_v1', 'grid_size': 256,
               'cell_size_m': .125, 'requested_tick_s': 1 / 30,
               'sample_ticks': [0, 1, 3, 6, 9, 12, 15, 18, 21, 24, 27, 30, 36, 42, 48, 54, 60, 75, 90, 105, 120, 135, 150, 165, 180],
               'spectral_interval_m': [-4, 4], 'spectral_row': 128,
               'far_points_xz_m': [[1.5625, .0625], [2.0625, .0625], [2.5625, .0625]],
               'point_rule': 'Fixed +X ray from midpoint of the 1 m Z stroke; cell centres; require wet for full control run.',
               'cases': cases}
    (destination / 'fixture.json').write_text(json.dumps(fixture, indent=2), encoding='utf-8')
    source = (ROOT / 'tools/wave_propagation/diagnose.gd').read_text(encoding='utf-8')
    (destination / 'original_probe.gd').write_text(source, encoding='utf-8')
    source = source.replace('var started := 0', 'var started := 0\nvar fixture: Dictionary = {}\nvar selected: Dictionary = {}')
    source = source.replace('started = Time.get_ticks_msec()', 'fixture = JSON.parse_string(FileAccess.get_file_as_string("res://test_output/wave_propagation/g0_baseline_20261020/fixture.json"))\n\tstarted = Time.get_ticks_msec()')
    source = source.replace('300000', '900000')
    source = source.replace('for target in [1,3,6,15,30,60,120]:', 'for target in fixture.sample_ticks:\n\t\tif target == 0: continue')
    source = source.replace('domain.water.fill(0.1)', 'domain.water.fill(float(selected.get("depth", 0.1)))')
    source = source.replace('0.0001 * sin', 'float(selected.get("amplitude", 0.0001)) * sin')
    source = source.replace('sqrt(9.81*0.1)*eta', 'sqrt(9.81*float(selected.get("depth", 0.1)))*eta')
    source = source.replace('current.configuration = config.value', 'current.configuration = config.value\n\tcurrent.fixture = selected.duplicate(true)')
    start = source.index('\tfor spec in [["sine_1m"')
    end = source.index('\nfunc run_main()', start)
    source = source[:start] + '''\tfor spec in fixture.cases:
\t\tselected = spec
\t\tcurrent = {"id":spec.id,"snapshots":[]}
\t\tawait boot_flat(spec.kind, float(spec.wavelength))
\t\tif failed: return
\t\tawait snapshot("before")
\t\tif spec.kind == "shovel":
\t\t\tawait flat_shovel(float(spec.speed))
\t\t\tawait snapshot("edited")
\t\tawait advance_and_capture()
\t\tcases.append(current)
\t\tawait finish_flat()
\t\tif failed: return
''' + source[end:]
    source = source.replace('"mean_depth_m":0.1', '"mean_depth_m":float(selected.get("depth",0.1))')
    source = source.replace('"amplitude_m":0.0001 if kind=="sine" else 0.005', '"amplitude_m":float(selected.get("amplitude",0.0001)) if kind=="sine" else 0.005')
    source = source.replace('extra.append("res://tools/wave_propagation/diagnose.gd")', 'extra.append("res://tools/wave_propagation/baseline_probe.gd")')
    source = source.replace('"tick":owner.completed_tick,"revision":owner.completed_revision,"state_seq":owner.completed_state_seq', '"tick":str(owner.completed_tick),"revision":str(owner.completed_revision),"state_seq":str(owner.completed_state_seq),"generation":str(owner._generation)')
    source = source.replace('"elapsed_ms":Time.get_ticks_msec()-started', '"fixture":fixture,"elapsed_ms":Time.get_ticks_msec()-started')
    probe = ROOT / 'tools/wave_propagation/baseline_probe.gd'
    if probe.exists():
        raise FileExistsError(probe)
    probe.write_text(source, encoding='utf-8')
    print(destination)


if __name__ == '__main__':
    main()
