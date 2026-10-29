"""Run isolated Godot uint4 codec with native-reference data, bit basis and input negatives."""
import argparse
import datetime
import json
import shutil
import subprocess
from pathlib import Path
import numpy as np
from evidence_contract import identity
from reference_budget import codes


FIELDS = ['nx', 'nz', 'vx', 'vz', 'A', 'bed', 'B', 'source', 'sea']


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--output', required=True, type=Path)
    ap.add_argument('--godot', type=Path, default=Path('D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'))
    args = ap.parse_args()
    root = Path(__file__).resolve().parents[3]
    project = root / 'tests/investigation/water_solver_evidence_probe'
    out = args.output.resolve()
    if not str(out).isascii():
        raise ValueError('ASCII output required')
    out.mkdir(parents=True, exist_ok=False)
    for folder in ['sources', 'inputs', 'positive', 'bad_hash', 'bad_size']:
        (out / folder).mkdir()
    for source in [*project.rglob('*.gd'), *project.rglob('*.glsl'), project / 'probe.tscn', project / 'project.godot', Path(__file__), Path(__file__).with_name('reference_budget.py'), Path(__file__).with_name('evidence_contract.py')]:
        shutil.copyfile(source, out / 'sources' / source.name)
    reference_manifest = root / 'docs/competitor/evidence/water_solver_reconstruction/t03_six_kernel_20261025_v4/manifest.json'
    reference = json.loads(reference_manifest.read_text())
    original = reference_manifest.parent / 'sources/e1484/water.bin'
    expected = next(x for x in reference['artifacts'] if x['path'] == original.as_posix())
    if identity(original)['sha256'] != expected['sha256']:
        raise ValueError('Frozen input changed')
    shutil.copyfile(original, out / 'inputs/native_floor_input.bin')
    basis = np.zeros((512 * 256, 4), dtype='<u4')
    for bit in range(128):
        basis[bit, bit // 32] = np.uint32(1) << np.uint32(bit % 32)
    basis[128] = np.uint32(0xffffffff)
    basis.tofile(out / 'inputs/bit_basis.bin')
    rng = np.random.Generator(np.random.PCG64(20261025))
    entropy = rng.integers(0, 2**32, size=(512 * 256, 4), dtype=np.uint32).astype('<u4')
    entropy.tofile(out / 'inputs/bit_entropy.bin')
    paths = list((out / 'inputs').glob('*.bin'))
    request = dict(schema_version='1.0', operation='codec_only', output_root=(out / 'positive').as_posix(),
                   source_manifest=identity(reference_manifest), fields=FIELDS,
                   fixture_semantics='Only native_floor_input comes from the frozen original-program reference. Bit basis and PCG64 seed20261025 entropy are synthetic encoding tests, not physically reachable game states.',
                   cases=[dict(case_id=p.stem, input=identity(p)) for p in paths])
    (out / 'request.json').write_text(json.dumps(request, indent=2), encoding='utf-8')
    runs = []

    def execute(name, req, headless=False):
        path = out / (name + '_request.json')
        path.write_text(json.dumps(req, indent=2), encoding='utf-8')
        command = [str(args.godot), '--path', str(project), '--log-file', str(out / name / 'engine.log')]
        command += ['--headless'] if headless else ['--rendering-method', 'mobile', '--rendering-driver', 'vulkan']
        command += ['--', '--request', str(path)]
        start = datetime.datetime.now(datetime.timezone.utc).isoformat()
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        timed_out = False
        try:
            stdout, stderr = process.communicate(timeout=90)
        except subprocess.TimeoutExpired:
            timed_out = True
            process.kill()  # Only this exact owned Popen instance.
            stdout, stderr = process.communicate()
        (out / name / 'stdout.bin').write_bytes(stdout)
        (out / name / 'stderr.bin').write_bytes(stderr)
        result_path = out / name / 'probe_result.json'
        result = json.loads(result_path.read_text()) if result_path.exists() else None
        row = dict(command=command, started_at=start, finished_at=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                   pid=process.pid, exit_code=process.returncode, timed_out=timed_out, result=result)
        runs.append(row)
        return row

    positive = execute('positive', request)
    errors, comparisons = [], []
    if positive['exit_code'] or not positive['result'] or positive['result']['operation_status'] != 'complete':
        errors.append('POSITIVE_GPU_RUN_FAILED')
    else:
        for case in positive['result']['cases']:
            input_path = next(p for p in paths if p.stem == case['case_id'])
            fields = codes(input_path)
            expected_codes = np.column_stack([fields[f] for f in FIELDS]).astype('<u4')
            actual_codes = np.fromfile(case['codes'], dtype='<u4').reshape(-1, len(FIELDS))
            original_words = np.fromfile(input_path, dtype='<u4')
            actual_words = np.fromfile(case['roundtrip'], dtype='<u4')
            field_errors = {name: int(np.count_nonzero(actual_codes[:, index] != expected_codes[:, index])) for index, name in enumerate(FIELDS)}
            word_errors = int(np.count_nonzero(original_words != actual_words))
            if word_errors or any(field_errors.values()):
                errors.append('PACKED_CODEC_MISMATCH:' + case['case_id'])
            comparisons.append(dict(case_id=case['case_id'], input=identity(input_path), decoded_fields=identity(case['codes']),
                                    roundtrip=identity(case['roundtrip']), word_mismatches=word_errors, field_mismatches=field_errors))
    negatives = []
    for name, code in [('bad_hash', 'INPUT_IDENTITY_MISMATCH'), ('bad_size', 'INPUT_SIZE_MISMATCH')]:
        req = json.loads(json.dumps(request))
        req['output_root'] = (out / name).as_posix()
        req['cases'] = req['cases'][:1]
        if name == 'bad_hash':
            req['cases'][0]['input']['sha256'] = '0' * 64
        else:
            req['cases'][0]['input']['size_bytes'] -= 4
        run = execute(name, req, headless=True)
        rejected = run['exit_code'] == 1 and run['result'] and code in run['result']['errors']
        negatives.append(dict(case=name, rejected=bool(rejected), expected_error=code))
        if not rejected:
            errors.append('NEGATIVE_NOT_REJECTED:' + name)
    report = dict(operation_status='complete', verification_status='passed' if not errors else 'failed',
                  scope='T06-G01 packed codec and input identity only. No six solver stages, original/ping-pong equivalence, short sequence or G5 acceptance.',
                  godot=identity(args.godot), project_sources=[identity(p) for p in (out / 'sources').iterdir()],
                  reference_manifest=identity(reference_manifest), original_input=expected, requests=identity(out / 'request.json'),
                  runs=runs, comparisons=comparisons, negatives=negatives, errors=errors)
    (out / 'codec_audit.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    (out / 'manifest.json').write_text(json.dumps(dict(operation_status='complete', verification_status=report['verification_status'], errors=errors, artifacts=[identity(p) for p in out.rglob('*') if p.is_file()]), indent=2), encoding='utf-8')
    print(json.dumps(dict(status=report['verification_status'], comparisons=len(comparisons), negatives=negatives, errors=errors)))
    raise SystemExit(bool(errors))


if __name__ == '__main__':
    main()
