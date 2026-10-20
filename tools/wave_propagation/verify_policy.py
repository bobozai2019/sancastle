"""Stage rejection, final cap, roundoff accounting and reversing-donor evidence."""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from reference import Reference, G


def main():
    ap = argparse.ArgumentParser();ap.add_argument('output', type=Path)
    out = ap.parse_args().output.resolve();out.mkdir(parents=True, exist_ok=False)
    sources = [Path(__file__), Path(__file__).with_name('reference.py')]
    hashes = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
    for p in sources:
        (out/p.name).write_bytes(p.read_bytes())
    rows = []
    n, dx = 32, .125
    x = (np.arange(n)+.5-n/2)*dx;X, Z = np.meshgrid(x, x)
    for dtype in (np.float64, np.float32):
        solver = Reference(np.full((n, n), .4), dx, periodic=True, dtype=dtype)
        state = np.zeros((4, n, n), dtype=dtype)
        state[0] = .1+.0002*np.sin(np.pi*X)*np.cos(np.pi*Z)
        state[1] = .002;state[2] = -.001;state[3] = .05*state[0]
        final, stats, flux = solver.advance(state, 1/30, capacity=1)
        okay = stats['accepted_substeps'] == 0 and stats['rejected_trials'] == 1 and stats['advanced_time_s'] == 0
        okay &= np.array_equal(final, state) and all(not np.any(f) for f in flux)
        rows.append({'case': 'rejected_trial_'+dtype.__name__, 'pass': bool(okay), 'stats': stats})
        np.savez_compressed(out/('rejected_trial_'+dtype.__name__+'.npz'), initial=state, final=final,
                            integrated_z=flux[0], integrated_x=flux[1])

        # A convex mixture of individually capped momenta can exceed cap(h).
        mixture = np.zeros_like(state);mixture[0] = .505
        mixture[1] = .5*(.01*1.5+3*np.sqrt(G))
        count = solver.limit_momentum(mixture)
        max_speed = float(np.max(np.hypot(mixture[1], mixture[2])/mixture[0]))
        rows.append({'case': 'final_cap_'+dtype.__name__, 'pass': count == n*n and max_speed <= 3*np.sqrt(G*.505)*(1+8*np.finfo(dtype).eps),
                     'limited_cells': count, 'max_speed': max_speed})
        update = np.zeros_like(state);update[0] = .1;update[3] = .005
        update[0, 0, 0] = -np.finfo(dtype).eps*.01
        scale = np.zeros_like(state);scale[0] = .1;scale[3] = .005
        correction = solver.correct_roundoff(update, scale)
        rows.append({'case': 'roundoff_'+dtype.__name__, 'pass': correction['water_roundoff_cells'] == 1 and correction['water_roundoff_m3'] > 0 and update[0, 0, 0] == 0,
                     'correction': correction})
        update[0, 0, 0] = -.001
        try:
            solver.correct_roundoff(update, scale)
            rejected = False
        except ArithmeticError:
            rejected = True
        rows.append({'case': 'substantive_negative_'+dtype.__name__, 'pass': rejected})

    solver = Reference(np.full((n, n), .4), dx, periodic=True)
    rng = np.random.default_rng(2081)
    state = np.zeros((4, n, n));state[0] = .1+.003*rng.standard_normal((n, n))
    state[1] = .002*rng.standard_normal((n, n));state[2] = .002*rng.standard_normal((n, n))
    state[3] = state[0]*(.01+.005*(np.sin(X) > 0))
    dt = solver.stable_dt(state)*.5
    first = solver.euler(state, dt);second = solver.euler(first.state, dt)
    final = .5*(state+second.state)
    concentration = state[3]/state[0]
    reversals, mismatch = 0, 0.
    for axis in (0, 1):
        f0, f1 = first.flux[axis], second.flux[axis]
        reversals += int((f0[0]*f1[0] < 0).sum())
        net = .5*(f0+f1)
        naive = net[0]*np.where(net[0] >= 0, concentration, np.roll(concentration, -1, axis=axis))
        mismatch = max(mismatch, float(abs(net[3]-naive).max()))
    rows.append({'case': 'stage_direction_reversal', 'seed': 2081, 'pass': reversals > 0 and mismatch > 1e-8 and np.min(final[[0, 3]]) >= 0 and abs((final[3]-state[3]).sum()*dx*dx) < 1e-12,
                 'reversed_edges': reversals, 'net_flux_wrong_donor_error_m2_s': mismatch,
                 'sediment_mass_error_m3': float((final[3]-state[3]).sum()*dx*dx)})
    np.savez_compressed(out/'stage_direction_reversal.npz', initial=state, stage1=first.state, stage2=second.state, final=final,
                        stage0_z=first.flux[0], stage0_x=first.flux[1], stage1_z=second.flux[0], stage1_x=second.flux[1])
    drift = [p.name for p in sources if hashes[p.name] != hashlib.sha256(p.read_bytes()).hexdigest()]
    for row in rows:
        row['pass'] = bool(row['pass'])
    artifacts = [{'path': str(p), 'sha256': hashlib.sha256(p.read_bytes()).hexdigest(), 'bytes': p.stat().st_size} for p in out.glob('*.npz')]
    result = {'outcome': 'pass' if all(r['pass'] for r in rows) and not drift else 'fail',
              'rows': rows, 'source_hashes': hashes, 'source_drift': drift,
              'artifacts': artifacts,
              'numpy_version': np.__version__, 'scope': 'Offline reference policy only; GPU and coupled production not implemented'}
    (out/'result.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
    print(json.dumps(result, indent=2));raise SystemExit(result['outcome'] != 'pass')


if __name__ == '__main__':
    main()
