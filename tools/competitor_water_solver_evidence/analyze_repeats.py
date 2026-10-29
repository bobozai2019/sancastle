"""Compare all retained T02 samples without assuming their input pairing."""
import argparse
import itertools
import json
import shutil
from pathlib import Path
import numpy as np
from evidence_contract import identity


def decode(path):
    raw = np.fromfile(path, dtype='<u4')
    if raw.size != 512 * 256 * 4:
        raise ValueError('DEPENDENCY_MISSING: expected complete uint4 water')
    raw = raw.reshape(-1, 4)
    u0, u1, u2, u3 = [raw[:, i].astype(np.uint64) for i in range(4)]
    scale = float(2**24 - 1)
    a = (u2 & 0xffffff).astype(np.float64) * 10.1 / scale
    fields = dict(nx=(u0 & 255).astype(np.float64) * 2 / 255 - 1,
        nz=((u0 >> 8) & 255).astype(np.float64) * 2 / 255 - 1,
        vx=((u0 >> 16) | ((u1 & 255) << 16)).astype(np.float64) * 8 / scale - 4,
        vz=(u1 >> 8).astype(np.float64) * 8 / scale - 4, A=a, h=np.maximum(a - 0.05, 0),
        bed=((u2 >> 24) | ((u3 & 65535) << 8)).astype(np.float64) * 10.1 / scale,
        B=(u3 >> 16) & 255, source=(u3 >> 24) & 15, sea=u3 >> 28)
    return raw, fields


def difference(left, right):
    ra, a = decode(left); rb, b = decode(right)
    changed = np.any(ra != rb, axis=1)
    indices = np.flatnonzero(changed)
    y, x = np.divmod(np.arange(512 * 256), 512)
    boundary = (x == 0) | (x == 511) | (y == 0) | (y == 255)
    result = dict(changed_cells=int(changed.sum()), component_mismatch=[int(np.count_nonzero(ra[:,i] != rb[:,i])) for i in range(4)],
        boundary_changed=int(np.count_nonzero(changed & boundary)),
        first_coordinate=None if not len(indices) else [int(indices[0] % 512), int(indices[0] // 512)], fields={})
    for field in a:
        da, db = a[field].astype(np.float64), b[field].astype(np.float64)
        delta = np.abs(da - db)
        index = int(np.argmax(delta))
        result['fields'][field] = dict(mae=float(delta.mean()), p99=float(np.quantile(delta, .99)), max=float(delta[index]),
            max_coordinate=[index % 512, index // 512], mismatch=int(np.count_nonzero(delta)),
            reference_range=[float(da.min()), float(da.max())], nonfinite=int(np.count_nonzero(~np.isfinite(db))))
    result['branch_differences'] = dict(wet=int(np.count_nonzero((a['h'] > 0) != (b['h'] > 0))),
        B=int(np.count_nonzero(a['B'] != b['B'])), source=int(np.count_nonzero(a['source'] != b['source'])),
        sea=int(np.count_nonzero(a['sea'] != b['sea'])))
    result['totals'] = dict(left_sum_A=float(a['A'].sum()), right_sum_A=float(b['A'].sum()),
                          left_sum_h=float(a['h'].sum()), right_sum_h=float(b['h'].sum()))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--matrix', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    out = args.output
    if not out.is_absolute() or not str(out).isascii():
        raise ValueError('Absolute ASCII output required')
    out.mkdir(parents=True, exist_ok=False)
    for name in ['derived', 'sources', 'raw', 'logs']:
        (out / name).mkdir()
    matrix = json.loads((args.matrix / 'repeat_matrix.json').read_text())
    groups = {}; checks=[]; errors=[]; samples=[]
    for spec in matrix['experiments']:
        req = json.loads(Path(spec['request']['path']).read_text())
        mpath = Path(req['output_root']) / 'manifest.json'
        m = json.loads(mpath.read_text())
        if m['operation_status'] != 'complete' or m['errors']:
            errors.append('INCOMPLETE_GROUP:' + req['run_id'])
        for sample in m['samples']:
            row = dict(sample, group=req['run_id'], manifest=identity(mpath), mode=req['repeat_mode'])
            row['sample_id'] = req['run_id'] + '_s%d' % sample['index']
            samples.append(row); groups.setdefault(req['repeat_mode'], []).append(row)
            for role in ['candidate_input','output']:
                for artifact in sample[role]['buffers'] + sample[role]['constants']:
                    actual = identity(artifact['path'])
                    valid = actual['sha256'] == artifact['sha256'] and actual['size_bytes'] == artifact['size_bytes']
                    checks.append(dict(path=artifact['path'], valid=valid))
                    if not valid:errors.append('ARTIFACT_CHANGED:' + artifact['path'])
    audits=[]; metrics=[]
    for mode, rows in groups.items():
        if len(rows) < 3:errors.append('TOO_FEW_SAMPLES:' + mode)
        audits.append(dict(mode=mode, sample_ids=[r['sample_id'] for r in rows],
            process_ids=sorted(set(r['process_id'] for r in rows)),
            candidate_input_hashes=sorted(set(r['candidate_input']['buffers'][0]['sha256'] for r in rows)),
            output_hashes=sorted(set(r['output']['buffers'][0]['sha256'] for r in rows)),
            output_constant_hashes=sorted(set(r['output']['constants'][0]['sha256'] for r in rows)),
            pairing_kind='unproven', input_proven_identical=False,
            classification='cached readback only' if mode=='cached' else 'replay variation with unproven input pairing'))
        for left, right in itertools.combinations(rows, 2):
            for role in ['candidate_input', 'output']:
                metric = difference(left[role]['buffers'][0]['path'], right[role]['buffers'][0]['path'])
                metrics.append(dict(mode=mode, left=left['sample_id'], right=right['sample_id'], role=role,
                    input_pairing='unproven', metric=metric))
    (out / 'derived/pairing_audit.json').write_text(json.dumps(audits, indent=2), encoding='utf-8')
    (out / 'derived/repeat_metrics.json').write_text(json.dumps(metrics, indent=2), encoding='utf-8')
    (out / 'derived/file_checks.json').write_text(json.dumps(checks, indent=2), encoding='utf-8')
    proposal = dict(ordinary_replay_sufficient=False,
        reason='Public post-event selections do not prove a same-execution pair or controlled restoration. Stable outputs would not close this logical gap.',
        input_state='candidate E1490 post-state retained, E1495 actual pre-state unproven',
        reference_noise=None, numeric_budget=None,
        recommended='native_reference',
        rationale='Controlled original-DXBC execution permits restored full UAV bytes, exact CBV/SRV/views and dispatch, plus repeatability probes without business-code analysis.',
        alternative='Targeted RenderDoc pre/post copy instrumentation if native backend compatibility fails',
        next_discriminating_experiment='Compile minimal D3D12 executor, run unmodified E1495 DXBC with one frozen complete input restored before each of three dispatches, wait fence and read back. Check binding, source hash and preserved fields.',
        prohibited_inference='Replay output variation is not proof of original shader nondeterminism or missing kernel barriers')
    (out / 'derived/reference_route_proposal.json').write_text(json.dumps(proposal, indent=2), encoding='utf-8')
    for name in ['analyze_repeats.py','evidence_contract.py']:
        shutil.copyfile(Path(__file__).with_name(name),out/'sources'/name)
    summary=[dict(mode=r['mode'], candidate_inputs=len(r['candidate_input_hashes']), outputs=len(r['output_hashes']),
                  constant_versions=len(r['output_constant_hashes'])) for r in audits]
    (out/'manifest.json').write_text(json.dumps(dict(operation_status='complete', verification_status='failed' if errors else 'passed',
        scope='G2 diagnosis only; no valid same-input reference noise or numeric equivalence judgment',
        matrix=identity(args.matrix/'repeat_matrix.json'), numpy_version=np.__version__, errors=errors,
        summary=summary, artifacts=[identity(p) for p in out.rglob('*') if p.is_file()]),indent=2),encoding='utf-8')
    print(json.dumps(dict(summary=summary, errors=errors)))
    raise SystemExit(1 if errors else 0)


if __name__ == '__main__':
    main()
