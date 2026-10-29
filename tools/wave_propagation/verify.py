"""Strict verification entry point. Only the offline reference suite exists yet."""
import argparse
import hashlib
import json
from pathlib import Path
import time
import traceback
import numpy as np
from reference import Reference, G

SOLVER = 'muscl_mc_ssprk2_v1'


def run_reference(out, fixture, group='all'):
    rows = []

    def run_case(name, bed, initial, dx, duration, periodic=False, obstacle=None, capacity=64):
        solver = Reference(bed, dx, periodic=periodic, obstacle=obstacle)
        state = initial.copy()
        clock, accepted, rejected, limited = 0., 0, 0, 0
        flux_integral = [np.zeros_like(state), np.zeros_like(state)]
        while clock < duration*(1-1e-12):
            state, stats, flux = solver.advance(state, min(1/30, duration-clock), capacity)
            if stats['advanced_time_s'] <= 0:
                raise ArithmeticError('no actual advancement')
            clock += stats['advanced_time_s']
            accepted += stats['accepted_substeps']
            rejected += stats['rejected_trials']
            limited += stats['velocity_limited_cells']
            for axis in (0, 1):
                flux_integral[axis] += flux[axis]
        expected_h = initial[0].copy()
        for axis in (0, 1):
            f = flux_integral[axis][0]
            expected_h += (np.roll(f, 1, axis=axis)-f)/dx
        row = {'case_id': name, 'grid_size': bed.shape[0], 'cell_size_m': dx,
               'advanced_time_s': clock, 'accepted_substeps': accepted, 'rejected_trials': rejected,
               'velocity_limited_cells': limited, 'finite': bool(np.isfinite(state).all()),
               'minimum_h_m': float(state[0].min()), 'minimum_sediment_m': float(state[3].min()),
               'max_h_change_m': float(abs(state[0]-initial[0]).max()),
               'max_abs_q_m2_s': float(abs(state[1:3]).max()),
               'net_flux_reconstruction_error_m': float(abs(state[0]-expected_h).max()),
               'water_mass_error_m3': float((state[0]-initial[0]).sum()*dx*dx),
               'sediment_mass_error_m3': float((state[3]-initial[3]).sum()*dx*dx)}
        path = out/(name+'.npz')
        np.savez_compressed(path, initial=initial, final=state, bed=bed,
                            integrated_edge_z=flux_integral[0], integrated_edge_x=flux_integral[1])
        row['fields'] = {'path': str(path), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                         'state_units': ['m', 'm2/s', 'm2/s', 'm'], 'dtype': 'float64'}
        rows.append(row)
        print(name, json.dumps(row, separators=(',', ':'))[:420], flush=True)
        return state, row

    n, dx = 256, .125
    x = (np.arange(n)+.5-n/2)*dx
    X, Z = np.meshgrid(x, x)
    beds = {'flat': np.full((n, n), .4), 'slope': .4+.003*X,
            'step': np.where(X < 0, .4, .45), 'dry_shore': .4+.02*X,
            'dune': .4+.15*np.exp(-(X*X+Z*Z)/8)}
    for name, bed in (beds.items() if group in ('all', 'static') else []):
        state = np.zeros((4, n, n));state[0] = np.maximum(0, .5-bed)
        _, row = run_case('lake_'+name, bed, state, dx, .1)
        row['pass'] = row['max_h_change_m'] <= 1e-12 and row['max_abs_q_m2_s'] <= 1e-12
    obstacle = (abs(X) < .5) & (abs(Z) < 1)
    state = np.zeros((4, n, n));state[0] = .1
    if group in ('all', 'static'):
        _, row = run_case('lake_obstacle', beds['flat'], state, dx, .1, obstacle=obstacle)
        row['pass'] = row['max_h_change_m'] <= 1e-12 and row['max_abs_q_m2_s'] <= 1e-12

    convergence = {}
    for direction in (('x', 'z', 'diagonal') if group in ('all', 'convergence') else []):
        errors = []
        for count in (32, 64, 128, 256):
            length, depth, amplitude, duration = 8., .1, .00001, .25
            spacing = length/count
            x = (np.arange(count)+.5-count/2)*spacing
            XX, ZZ = np.meshgrid(x, x)
            nx, nz = {'x': (1., 0.), 'z': (0., 1.), 'diagonal': (1/np.sqrt(2), 1/np.sqrt(2))}[direction]
            kx, kz = {'x': (np.pi, 0.), 'z': (0., np.pi), 'diagonal': (np.pi, np.pi)}[direction]
            phase, c = kx*XX+kz*ZZ, np.sqrt(G*depth)
            eta = amplitude*np.sin(phase)
            state = np.zeros((4, count, count));state[0] = depth+eta
            state[1] = c*eta*nx;state[2] = c*eta*nz
            final, row = run_case(f'convergence_{direction}_{count}', np.full((count, count), .4), state, spacing, duration, periodic=True)
            expected = depth+amplitude*np.sin(phase-np.hypot(kx, kz)*c*duration)
            error = float(np.mean(abs(final[0]-expected)))
            row['linear_wave_l1_h_error_m'] = error
            row['pass'] = row['finite'] and row['minimum_h_m'] >= 0
            errors.append(error)
        orders = [float(np.log2(a/b)) for a, b in zip(errors[:-1], errors[1:])]
        convergence[direction] = {'errors': errors, 'orders': orders, 'pass': orders[-1] >= 1.7}

    for concentration in ((.01, .05) if group in ('all', 'coupling') else []):
        state = np.zeros((4, n, n));state[0] = .1+.0002*np.sin(np.pi*X)*np.cos(np.pi*Z)
        state[1] = .002;state[2] = -.001;state[3] = concentration*state[0]
        final, row = run_case(f'constant_concentration_{concentration:g}', beds['flat'], state, dx, .1, periodic=True)
        error = float(abs(final[3]/final[0]-concentration).max())
        row['concentration_error'] = error
        row['pass'] = error <= 1e-12 and abs(row['water_mass_error_m3']) < 1e-10 and abs(row['sediment_mass_error_m3']) < 1e-10
    for name, right_depth in ([('dry_dam_break', 0.), ('near_dry_dam_break', .0009)] if group in ('all', 'strong') else []):
        state = np.zeros((4, n, n));state[0] = np.where(X < 0, .2, right_depth)
        final, row = run_case(name, beds['flat'], state, dx, .1)
        row['pass'] = row['finite'] and row['minimum_h_m'] >= 0 and abs(row['water_mass_error_m3']) < 1e-10
    state = np.zeros((4, n, n));state[0] = .1
    final, stats, _ = Reference(beds['flat'], dx).advance(state, 100., capacity=2)
    capacity_pass = stats['capacity_exhausted'] and 0 < stats['advanced_time_s'] < 100 and stats['accepted_substeps'] == 2
    return {'cases': rows, 'convergence': convergence, 'capacity_case': {**stats, 'pass': capacity_pass},
            'outcome': 'pass' if rows and all(r['pass'] for r in rows) and all(c['pass'] for c in convergence.values()) and capacity_pass else 'fail',
            'scope': 'Draft 2D numerical reference; no GPU, visual, cost, production coupling or G1 contract-freeze acceptance',
            'fixture': fixture}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--suite', choices=['baseline', 'reference', 'water', 'coupling', 'lifecycle', 'experience', 'cost', 'release'], required=True)
    parser.add_argument('--solver', required=True)
    parser.add_argument('--fixture', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--group', choices=['all', 'static', 'convergence', 'coupling', 'strong'], default='all')
    parser.add_argument('--project-root', type=Path)
    args = parser.parse_args()
    if args.suite in ('water','coupling','lifecycle'):
        if args.project_root is None or args.group!='all':parser.error('GPU suite needs project-root and no reference group')
        if args.suite=='water':from water_suite import run_suite
        elif args.suite=='coupling':from coupling_suite import run_suite
        else:from lifecycle_suite import run_suite
        raise SystemExit(not run_suite(args.fixture,args.solver,args.project_root,args.output))
    if args.suite != 'reference':
        parser.error('suite not implemented; no empty success result')
    if args.solver != SOLVER:
        parser.error('unknown reference solver')
    def reject_constant(value):
        raise ValueError('non-finite JSON constant: '+value)
    fixture = json.loads(args.fixture.read_text(encoding='utf-8'), parse_constant=reject_constant)
    expected_fixture = {'schema': 1, 'suite': 'reference', 'benchmark_id': 'fixed_bed_2d_v1',
                        'solver_id': SOLVER, 'grid_size': 256, 'cell_size_m': .125}
    if fixture != expected_fixture or type(fixture.get('schema')) is not int or type(fixture.get('grid_size')) is not int:
        parser.error('unsupported fixture')
    out = args.output.resolve();out.mkdir(parents=True, exist_ok=False)
    started = time.time()
    source_paths = [Path(__file__), Path(__file__).with_name('reference.py')]
    source_hashes = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in source_paths}
    for p in source_paths:
        (out/p.name).write_bytes(p.read_bytes())
    result = {'outcome': 'incomplete'}
    try:
        result = run_reference(out, fixture, args.group)
    except Exception:
        result['failure'] = traceback.format_exc()
        print(result['failure'], flush=True)
    drift = [p.name for p in source_paths if hashlib.sha256(p.read_bytes()).hexdigest() != source_hashes[p.name]]
    if drift:
        result['outcome'] = 'fail'
    result.update({'suite': args.suite, 'group': args.group, 'solver_id': args.solver,
                   'elapsed_wall_s': time.time()-started, 'numpy_version': np.__version__,
                   'fixture_sha256': hashlib.sha256(args.fixture.read_bytes()).hexdigest(),
                   'source_hashes': source_hashes, 'source_drift': drift})
    (out/'result.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
    raise SystemExit(result['outcome'] != 'pass')


if __name__ == '__main__':
    main()
