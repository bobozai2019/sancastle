"""Independent accumulated-time and force reconstruction from a G2 trace."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import struct
import numpy as np


def vector(value):
    return tuple(map(float, value.strip('()').split(',')))


def ulp32(value):
    bits = struct.unpack('<I', struct.pack('<f', abs(value)))[0]
    return struct.unpack('<f', struct.pack('<I', bits+1))[0]-abs(value)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('run', type=Path)
    args = parser.parse_args()
    result = json.loads((args.run/'probe.json').read_text('utf-8-sig'))
    manifest = json.loads((args.run/'run-manifest.json').read_text('utf-8-sig'))
    obs = result['observations']
    checks = []

    def check(name, passed):
        checks.append(dict(name=name, **{'pass': bool(passed)}))

    check('functional_run_and_source_identity', result['pass'] and manifest['pass'] and not manifest['drift'])
    events = obs['events']
    native_steps = [e for e in events if e['kind'] == 'physics']
    resting_steps = [e for e in events if e['kind'] == 'sleep_step']
    steps = [e for e in events if e['kind'] in {'physics', 'sleep_step'}]

    def quantum(event):
        return event['data']['state_step'] if event['kind'] == 'physics' else event['data']['effective_step_s']
    grants = [e for e in events if e['kind'] == 'admit']
    forces = [e for e in events if e['kind'] == 'point_force']
    origin = next(e['data']['origin_time_s'] for e in events if e['kind'] == 'layout_reset')
    body_ids = list(obs['profile'])
    actual_by_body = {body: math.fsum(quantum(e) for e in steps if str(e['data']['body_id']) == body) for body in body_ids}
    actual = actual_by_body[body_ids[0]]
    reserved = math.fsum(e['data']['delta'] for e in grants)
    maximum_step = max((quantum(e) for e in steps), default=1/60)
    clock_rounding = 4*ulp32(obs['final']['advanced_time_s'])+len(grants)*ulp32(maximum_step)+1e-6
    check('every_world_quantum_has_one_grant', all(sum(str(e['data']['body_id']) == body for e in steps) == len(grants) for body in body_ids))
    check('real_state_step_and_expected_match', all(abs(e['data']['state_step']-e['data']['expected_step']) < 1e-7 and not e['data']['error'] for e in native_steps))
    check('resting_world_steps_have_explicit_boundary_proof', all(e['data']['world_frame_delta'] == 1 and (e['data']['was_sleeping'] or e['data']['now_sleeping']) and abs(e['data']['effective_step_s']-e['data']['last_observed_state_step_s']) < 1e-10 and abs(e['data']['effective_step_s']-e['data']['expected_step']) < 1e-7 and not e['data']['error'] for e in resting_steps))
    check('budget_never_overdrawn', all(e['data']['budget_before']+1e-7 >= e['data']['delta'] for e in grants))
    check('force_samples_respect_frozen_age_budget', all(0 <= e['data']['force_age_s'] <= min(p['max_sample_age_s'] for p in obs['profile'].values())+1e-6 for e in grants if 'force_age_s' in e['data']))
    check('sum_real_steps_matches_report', all(abs(value-obs['final']['actual_time_s'][body]) < clock_rounding for body, value in actual_by_body.items()))
    check('sum_grants_matches_report', abs(reserved-obs['final']['admitted_time_s']) < 1e-9)
    check('physical_consumption_never_ahead_of_capture', all(e['data']['actual_time_s'] <= e['captured_time_s']-origin+clock_rounding for e in steps))
    gap = obs['final']['advanced_time_s']-origin-actual
    check('common_boundary_within_one_real_step_and_rounding', -clock_rounding <= gap < maximum_step+clock_rounding)
    check('real_consumed_equals_reserved_with_rounding', all(abs(value-reserved) <= clock_rounding for value in actual_by_body.values()))
    force_errors = []
    fraction_errors = []
    dry_forces = []
    clouds = {}
    distances = []
    for event in forces:
        row = event['data']
        profile = obs['profile'][str(row['body_id'])]
        point = profile['points'][row['point_id']-1]
        actual_point = np.array(row.get('position_m', vector(row['position'])))
        sample_point = np.array(vector(row['sample_position']))
        distances.append(float(np.linalg.norm(actual_point-sample_point))/profile['max_pose_distance_m'])
        clouds.setdefault((event['generation'], event['frame'], row['body_id']), {})[row['point_id']] = (actual_point, sample_point)
        y = row.get('position_m', vector(row['position']))[1]
        half = point['half_height_m']
        dry_depth = 8589935/8589934592 if row.get('sample_abi', 1) >= 2 else 1e-6
        sample_h = struct.unpack('<f', struct.pack('<f', row['sample_h']))[0]
        fraction = max(0, min(1, (min(y+half, row['sample_eta'])-max(y-half, row['sample_bed']))/(2*half))) if sample_h > dry_depth else 0
        fraction_errors.append(abs(fraction-row['fraction']))
        # Vector fields in this human trace are decimal Godot strings. The
        # 0.002 N bound covers their <=1e-6 positional/velocity normalization.
        vx, vy, vz = row.get('point_velocity_m_s', vector(row['point_velocity']))
        ux, uz = row.get('sample_u_m_s', vector(row['sample_u']))
        mass = profile['mass_kg']*point['mass_weight']*fraction
        predicted = (mass*(ux-vx)/profile['drag_time_horizontal_s'],
                     1000*9.8*point['effective_volume_m3']*fraction-mass*vy/profile['drag_time_vertical_s'],
                     mass*(uz-vz)/profile['drag_time_horizontal_s'])
        observed = row.get('force_n', vector(row['force']))
        force_errors.append(max(abs(a-b) for a, b in zip(observed, predicted)))
        if sample_h <= dry_depth:
            dry_forces.append(max(map(abs, observed)))
    check('force_and_submergence_trace_present', bool(forces))
    check('independent_interval_fraction', max(fraction_errors, default=0) < 1e-5)
    force_budget = 0.0002 if all('force_n' in e['data'] for e in forces) else 0.002
    check('independent_buoyancy_and_relative_drag', max(force_errors, default=0) < force_budget)
    check('dry_points_have_zero_water_force', all(v == 0 for v in dry_forces))
    angles = []
    complete_clouds = True
    for (_, _, body), cloud in clouds.items():
        profile = obs['profile'][str(body)]
        count = len(profile['points'])
        if len(cloud) != count:
            complete_clouds = False
            continue
        local = np.array([vector(p['local_position_m']) for p in profile['points']])
        rank = np.linalg.matrix_rank(local-local.mean(axis=0), tol=1e-5)
        actual_cloud = np.array([cloud[i+1][0] for i in range(count)])
        query_cloud = np.array([cloud[i+1][1] for i in range(count)])
        if rank == 1:
            i, j = max(((i, j) for i in range(count) for j in range(i)), key=lambda ij: np.linalg.norm(local[ij[0]]-local[ij[1]]))
            a, b = actual_cloud[i]-actual_cloud[j], query_cloud[i]-query_cloud[j]
            angle = math.acos(float(np.clip(a@b/(np.linalg.norm(a)*np.linalg.norm(b)), -1, 1)))
        elif rank >= 2:
            a, b = actual_cloud-actual_cloud.mean(axis=0), query_cloud-query_cloud.mean(axis=0)
            u, _, vt = np.linalg.svd(a.T@b)
            correction = np.eye(3)
            correction[2, 2] = np.linalg.det(u@vt)
            rotation = u@correction@vt
            angle = math.acos(float(np.clip((np.trace(rotation)-1)/2, -1, 1)))
        else:
            angle = 0.0
        angles.append(angle/profile['max_pose_angle_rad'])
    check('every_force_cloud_complete', complete_clouds and bool(clouds))
    check('independent_point_displacement_budget', max(distances, default=0) <= 1+2e-5)
    check('independent_observable_cloud_angle_budget', max(angles, default=0) <= 1+2e-4)
    metrics = dict(actual_time_s=actual, actual_by_body_s=actual_by_body, reserved_time_s=reserved, boundary_gap_s=gap,
                   observed_integrator_callbacks=len(native_steps), resting_world_quanta=len(resting_steps), total_world_quanta=len(steps), max_step_s=maximum_step, rounding_budget_s=clock_rounding,
                   max_force_reconstruction_error_n=max(force_errors, default=0),
                   force_reconstruction_budget_n=force_budget,
                   max_pose_distance_budget_fraction=max(distances, default=0), max_pose_angle_budget_fraction=max(angles, default=0),
                   max_capture_lag_s=max((e['captured_time_s']-e['admitted_time_s'] for e in events), default=0))
    verifier = Path(__file__).read_bytes()
    report = dict(checks=checks, metrics=metrics, verifier_sha256=hashlib.sha256(verifier).hexdigest(), **{'pass': all(c['pass'] for c in checks)})
    path = args.run/'independent_physics.json'
    if path.exists():
        raise SystemExit('Do not overwrite evidence')
    (args.run/'independent_physics_verifier.py').write_bytes(verifier)
    path.write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8')
    print('BOTTLE_PHYSICS', report['pass'], metrics)
    print('FAILURES', [c['name'] for c in checks if not c['pass']])
    raise SystemExit(0 if report['pass'] else 1)


if __name__ == '__main__':
    main()
