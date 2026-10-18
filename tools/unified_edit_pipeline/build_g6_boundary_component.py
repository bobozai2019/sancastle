"""Collect boundary/wave/geometry evidence; formal G6 remains incomplete."""
import hashlib
import json
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT/'test_output/unified_edit_pipeline'
TARGET = ROOT/'task/sandcastle_unified_edit_pipeline/验收/G6_潮汐波浪边界组件.json'
RUNS = [('boundary', 'g6_boundary_matrix05'), ('handoff', 'g6_boundary_handoff05'), ('spine', 'g6_boundary_spine05'), ('capture', 'g6_boundary_capture05'), ('restore', 'g6_boundary_restore05')]
AUDITS = ['g6_boundary_independent05.json', 'g6_boundary_handoff_independent05.json', 'g6_boundary_spine_independent05.json', 'g6_boundary_capture_independent05.json', 'g6_boundary_restore_independent05.json']


def load(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def identity(path):
    return {'path': str(path.resolve()), 'bytes': path.stat().st_size, 'sha256': sha(path)}


def source_map(data):
    result = {p.replace('\\', '/').removeprefix('res://'): h.lower() for p, h in data.items()}
    assert all(sha(ROOT/p) == h for p, h in result.items())
    return result


def main():
    if TARGET.exists():
        raise SystemExit('Fresh component required')
    sources, runs, audits, archives, cpu = [], [], [], [], []
    manifests = {}
    for label, directory in RUNS:
        path = OUT/directory/'run-manifest.json';data = load(path)
        assert data['pass'] and not data['drift'] and all(r['pass'] for r in data['runs'])
        sources.append(source_map(data['sources']));manifests[label] = path
        runs.append({'label': label, 'manifest': identity(path), 'cases': [r['case'] for r in data['runs']], 'checks': sum(r['checks'] for r in data['runs'])})
    common = set.intersection(*(set(s) for s in sources))
    assert all(len({s[k] for s in sources}) == 1 for k in common)
    for relative in AUDITS:
        path = OUT/relative;data = load(path);assert data['pass']
        audits.append({**identity(path), 'checks': len(data.get('checks', [])), 'raw_cases': len(data.get('records', []))})
    for label, expected in [('protocol', 212), ('configuration', 87)]:
        path = OUT/('g6_boundary_'+label+'05')/'run-manifest.json';data = load(path)
        assert data['pass'] and not data['drift'] and data['checks'] == expected
        source_map(data['sources']);manifests[label] = path;cpu.append({'label': label, 'manifest': identity(path), 'checks': expected})
    parameters = OUT/'g6_boundary_parameters05/probe.json';data = load(parameters)
    assert data['pass'] and len(data['checks']) == 79
    source_map(data['sources']);cpu.append({'label': 'runtime_parameter_boundaries', 'probe': identity(parameters), 'checks': 79, 'source': identity(ROOT/'tests/integration/unified_edit_runtime_configuration_probe.gd')})
    for label, manifest in manifests.items():
        path = OUT/'g6_boundary_final_sources05'/(label+'.zip')
        with zipfile.ZipFile(path) as archive:
            assert archive.testzip() is None
            index = json.loads(archive.read('evidence/source-index.json'))
            assert all(hashlib.sha256(archive.read(p)).hexdigest() == h for p, h in index.items())
            assert hashlib.sha256(archive.read('evidence/run-manifest.json')).hexdigest() == sha(manifest)
            if label in dict(RUNS):
                assert index['tools/unified_edit_pipeline/run_gpu_contract.ps1'] == load(manifest)['tool_sha256'].lower()
        archives.append({**identity(path), 'sources': len(index), 'all_members_verified': True})
    failed_audit = OUT/'g6_boundary_independent03.json';assert not load(failed_audit)['pass']
    result = {'role': 'partial_T06_prescribed_tide_wave_and_geometry_boundary_component', 'component_pass': True, 'G6_pass': False, 'completed_objectives': 24, 'total_objectives': 36, 'T06_completed': 0, 'runs': runs, 'GPU_cases': sum(len(r['cases']) for r in runs), 'GPU_probe_checks': sum(r['checks'] for r in runs), 'common_runtime_source_count': len(common), 'common_runtime_source_hashes': {p: sources[0][p] for p in sorted(common)}, 'independent_audits': audits, 'cpu_regressions': cpu, 'source_archives': archives, 'builder': identity(Path(__file__)), 'verified_scope': ['Actual main/test1 capture/backwash and geometry boundary parameters and source assets are frozen into configuration; mode3 matches the actual water-cycle profile and inlet span', 'Each admitted water tick or implicit tick freezes its wave packets; requests cannot affect an older pending tick', 'Wave identities, generation/domain, pending tick floor, old phase mapping, expiration-on-admission and 128 capacity are bounded; no independent authority pump', 'Boundary executes with retained erosion and all foam/local-front/gravel enabled; ordered asynchronous before/after snapshots independently prove inlet-only changes, momentum and exact actual source/sink reduction', 'Geometry rise/fall cases use explicitly marked synthetic-clock native fixtures from actual initial GPU fields, not alleged naturally elapsed scene time', 'Native capture reads and validates the real padded 2048-byte wave buffer; restore preserves f64 start clocks/highwater and rebases generation metadata, then verifies 46 actual readers', 'Real saved native physical/display fields, all 64 physics maps, continued ticks and second captures/ledgers agree', 'Full boundary-enabled two-slot material/collision handoff and related failure/unknown ownership regressions pass', 'Private read-only GPU sine diagnostics attribute host-libm oracle mismatch without changing production boundary shaders, physical budgets or total-wave comparison budgets'], 'preserved_failures': [identity(OUT/'g6_boundary_boot01/run-manifest.json'), identity(OUT/'g6_boundary_boot01_sources.zip'), identity(failed_audit), identity(OUT/'g6_boundary_matrix03_sources.zip'), identity(OUT/'g6_boundary_trace_independent04.json'), identity(OUT/'g6_boundary_trace04_sources.zip')], 'precision_reference': {'url': 'https://github.com/microsoft/DirectXShaderCompiler/blob/main/docs/DXIL.rst#sin', 'verified_date': '2026-10-18', 'role': 'Supplementary DXIL Sin precision specification; actual observed values and strict physical/total-wave checks remain primary evidence', 'maximum_absolute_error_in_spec': .0008, 'specified_input_interval': '[-100*pi,+100*pi]', 'physical_and_total_wave_budget_changed': False}, 'runner_difference': 'Boundary matrix was sealed before adding only handoff_boundary to the runner whitelist. Every archive retains its own actual runner; shared runtime bytes are identical.', 'pending': ['Formal main/test1 three-entry factory/UI wiring and retirement of reachable legacy writer/fallback paths', 'Gravel spawn intent and continuously advancing preview readiness', 'Full formal open-stroke/save/close/unknown lifecycle and ten full scene loops', 'G7 configuration-only extension audit and G8 visible complete-load performance/long stability'], 'formal_entries_changed': False, 'performance_pass': False}
    TARGET.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({'component_pass': True, 'G6_pass': False, 'GPU_cases': result['GPU_cases'], 'GPU_checks': result['GPU_probe_checks'], 'common_sources': len(common), 'report': str(TARGET.resolve())}))


if __name__ == '__main__':
    main()
