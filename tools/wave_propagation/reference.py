"""Draft full-2D hydrostatic MUSCL/MC + SSP-RK2 reference, not production.

State layout is (h, qx, qz, suspended thickness), float64. Each direction
owns one oriented +edge per cell; sediment uses the actual stage donor.
The water/sand production source terms are deliberately absent here.
"""
from dataclasses import dataclass, field
import numpy as np

G = 9.81
DRY = .001
VELOCITY_DEPTH = .005
COURANT = .2


def shift(a, direction, axis):
    return np.roll(a, -direction, axis=axis)


def mc(a, axis):
    left, right = a - shift(a, -1, axis), shift(a, 1, axis) - a
    return np.where(left*right > 0, np.sign(left)*np.minimum(
        np.minimum(2*np.abs(left), 2*np.abs(right)), .5*np.abs(left+right)), 0.)


@dataclass
class Step:
    state: np.ndarray
    flux: tuple
    max_speed_sum: float
    limiter_cells: int
    roundoff: dict = field(default_factory=dict)


class Reference:
    def __init__(self, bed, dx, *, periodic=False, obstacle=None, dtype=np.float64):
        self.dtype = np.dtype(dtype)
        if self.dtype not in (np.dtype('float32'), np.dtype('float64')):
            raise ValueError('unsupported arithmetic dtype')
        self.bed = np.asarray(bed, dtype=self.dtype)
        self.dx = float(dx)
        self.periodic = periodic
        self.obstacle = np.zeros_like(self.bed, dtype=bool) if obstacle is None else np.asarray(obstacle, dtype=bool)
        if self.bed.ndim != 2 or self.dx <= 0 or not np.isfinite(self.bed).all():
            raise ValueError('invalid bed/grid')

    def faces(self, state, axis):
        h, qx, qz, _ = state
        wet = h > DRY
        u = np.where(wet, qx/np.maximum(h, VELOCITY_DEPTH), 0.)
        v = np.where(wet, qz/np.maximum(h, VELOCITY_DEPTH), 0.)
        values = np.stack((h, h+self.bed, u, v))
        safe = wet & ~self.obstacle
        for other in (0, 1):
            safe &= shift(wet & ~self.obstacle, -1, other) & shift(wet & ~self.obstacle, 1, other)
        if not self.periodic:
            safe[[0, -1], :] = False
            safe[:, [0, -1]] = False
        slopes = np.stack([mc(a, axis) for a in values]) * safe
        slopes[0] *= np.minimum(1., 2*h/np.maximum(np.abs(slopes[0]), np.finfo(self.dtype).tiny))
        minus, plus = values-.5*slopes, values+.5*slopes
        return minus, plus

    def edge(self, state, axis):
        minus, plus = self.faces(state, axis)
        left, right = plus, shift(minus, 1, axis+1)
        hl, el, ul, vl = left
        hr, er, ur, vr = right
        zl, zr = el-hl, er-hr
        zmax = np.maximum(zl, zr)
        hls, hrs = np.maximum(0., el-zmax), np.maximum(0., er-zmax)
        normal = 1 if axis == 1 else 2
        un_l, un_r = (ul, ur) if normal == 1 else (vl, vr)
        speed = np.maximum(np.abs(un_l)+np.sqrt(G*hls), np.abs(un_r)+np.sqrt(G*hrs))
        ql, qr = np.stack((hls, hls*ul, hls*vl)), np.stack((hrs, hrs*ur, hrs*vr))
        fl, fr = ql*un_l, qr*un_r
        fl[normal] += .5*G*hls*hls
        fr[normal] += .5*G*hrs*hrs
        flux = .5*(fl+fr)-.5*speed*(qr-ql)
        wall = self.obstacle | shift(self.obstacle, 1, axis)
        if not self.periodic:
            wall = wall.copy()
            if axis == 0:
                wall[-1, :] = True
            else:
                wall[:, -1] = True
        flux[:, wall] = 0.
        corr_l = .5*G*(hl*hl-hls*hls)
        corr_r = .5*G*(hr*hr-hrs*hrs)
        corr_l[wall] = .5*G*hl[wall]**2
        corr_r[wall] = .5*G*hr[wall]**2
        # Within-cell bed source; vanishes on flat bed and cancels stationary
        # face-pressure differences when eta is constant.
        bm, bp = minus[1]-minus[0], plus[1]-plus[0]
        source = -.5*G*(minus[0]+plus[0])*(bp-bm)/self.dx
        return flux, corr_l, corr_r, source, float(speed.max())

    def stable_dt(self, state):
        speed_sum = sum(self.edge(state, axis)[4] for axis in (0, 1))
        return COURANT*self.dx/max(speed_sum, .01)

    def limit_momentum(self, state):
        state[1:3, state[0] <= DRY] = 0.
        length = np.hypot(state[1], state[2])
        cap = state[0]*np.maximum(1.5, 3*np.sqrt(G*state[0]))
        limited = length > cap
        state[1:3] *= np.minimum(1., cap/np.maximum(length, np.finfo(self.dtype).tiny))
        state[1:3, self.obstacle] = 0.
        return int(limited.sum())

    def correct_roundoff(self, updated, scale):
        stats = {}
        for name, index in [('water', 0), ('sediment', 3)]:
            negative = updated[index] < 0
            tolerance = np.minimum(2e-6, 8*np.finfo(self.dtype).eps*scale[index])
            if np.any(updated[index] < -tolerance):
                raise ArithmeticError('substantive negative '+name)
            stats[name+'_roundoff_cells'] = int(negative.sum())
            stats[name+'_roundoff_m3'] = float(-updated[index][negative].astype(np.float64).sum()*self.dx**2)
            updated[index][negative] = 0
        return stats

    def euler(self, state, dt):
        edges = [self.edge(state, axis) for axis in (0, 1)]
        ratio = dt/self.dx
        outgoing = np.zeros_like(self.bed)
        for axis, (flux, *_rest) in enumerate(edges):
            outgoing += np.maximum(flux[0], 0.) + np.maximum(-shift(flux[0], -1, axis), 0.)
        tiny = np.finfo(self.dtype).tiny
        donor = np.minimum(1., state[0]/np.maximum(ratio*outgoing, tiny))
        updated, accepted_flux = state.copy(), []
        magnitude = np.abs(state).copy()
        for axis, (raw, corr_l, corr_r, source, _speed) in enumerate(edges):
            scale = np.where(raw[0] >= 0, donor, shift(donor, 1, axis))
            flux = np.zeros_like(state)
            flux[:3] = raw*scale
            concentration = np.divide(state[3], state[0], out=np.zeros_like(state[0]), where=state[0] > 0)
            flux[3] = flux[0]*np.where(flux[0] >= 0, concentration, shift(concentration, 1, axis))
            updated += ratio*(shift(flux, -1, axis+1)-flux)
            magnitude += abs(ratio)*(abs(shift(flux, -1, axis+1))+abs(flux))
            normal = 1 if axis == 1 else 2
            updated[normal] += ratio*(shift(corr_r, -1, axis)-corr_l) + dt*source
            accepted_flux.append(flux)
        if not np.isfinite(updated).all():
            raise ArithmeticError('nonfinite stage')
        roundoff = self.correct_roundoff(updated, magnitude)
        limited = self.limit_momentum(updated)
        updated[:, self.obstacle] = state[:, self.obstacle]
        updated[1:3, self.obstacle] = 0.
        return Step(updated, tuple(accepted_flux), sum(e[4] for e in edges), limited, roundoff)

    def advance(self, state, requested_dt, capacity=64):
        if not np.isfinite(state).all() or np.min(state[[0, 3]]) < 0 or not np.isfinite(requested_dt) or requested_dt <= 0:
            raise ValueError('invalid state/time')
        state = np.array(state, dtype=self.dtype, copy=True)
        advanced, accepted, rejected, limited = 0., 0, 0, 0
        retry_dt = np.inf
        integrated = [np.zeros_like(state), np.zeros_like(state)]
        roundoff = {name+suffix: 0 for name in ('water', 'sediment') for suffix in ('_roundoff_cells', '_roundoff_m3')}
        for _trial in range(capacity):
            remaining = requested_dt-advanced
            if remaining <= requested_dt*1e-12:
                break
            dt = min(remaining, self.stable_dt(state), retry_dt)
            first = self.euler(state, dt)
            # Validate the actual reconstructed stage-one speeds on the device
            # analogue; rejected trials do not touch time or authority.
            if dt > self.stable_dt(first.state)*(1+8*np.finfo(self.dtype).eps):
                rejected += 1
                retry_dt = dt*.5
                continue
            second = self.euler(first.state, dt)
            combined = .5*(state+second.state)
            final_limited = self.limit_momentum(combined)
            state = combined
            for axis in (0, 1):
                integrated[axis] += .5*dt*(first.flux[axis]+second.flux[axis])
            advanced += dt
            accepted += 1
            limited += first.limiter_cells+second.limiter_cells+final_limited
            for name in ('water', 'sediment'):
                roundoff[name+'_roundoff_cells'] += first.roundoff[name+'_roundoff_cells']+second.roundoff[name+'_roundoff_cells']
                roundoff[name+'_roundoff_m3'] += .5*(first.roundoff[name+'_roundoff_m3']+second.roundoff[name+'_roundoff_m3'])
            retry_dt = np.inf
        return state, {'advanced_time_s': advanced, 'accepted_substeps': accepted,
                       'rejected_trials': rejected, 'velocity_limited_cells': limited,
                       'capacity_exhausted': advanced < requested_dt*(1-1e-12), **roundoff}, tuple(integrated)
