"""Collect enabled display-stage evidence; full lifecycle G6 stays incomplete."""
import hashlib
import json
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT/'test_output/unified_edit_pipeline'
TARGET = ROOT/'task/sandcastle_unified_edit_pipeline/验收/G6_启用表现组件.json'
RUNS = [('visuals', 'g6_visual_matrix03'), ('handoff', 'g6_visual_handoff03'), ('spine', 'g6_visual_spine03'), ('capture', 'g6_visual_capture03'), ('coupled', 'g6_visual_coupled03'), ('views', 'g6_visual_views03')]
AUDITS = ['g6_visual_independent03.json', 'g6_visual_handoff_independent03.json', 'g6_visual_spine_independent03.json', 'g6_visual_capture_independent03.json', 'g6_visual_coupled_independent03/result.json', 'g6_visual_views_independent03/result.json']


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
        path = OUT/('g6_visual_'+label+'03')/'run-manifest.json';data = load(path)
        assert data['pass'] and not data['drift'] and data['checks'] == expected
        source_map(data['sources']);manifests[label] = path;cpu.append({'label': label, 'manifest': identity(path), 'checks': expected})
    parameters = OUT/'g6_visual_parameters03/probe.json';parameter_data = load(parameters)
    assert parameter_data['pass'] and len(parameter_data['checks']) == 49
    source_map(parameter_data['sources'])
    cpu.append({'label': 'runtime_parameter_boundaries', 'probe': identity(parameters), 'checks': 49, 'source': identity(ROOT/'tests/integration/unified_edit_runtime_configuration_probe.gd')})
    for label, manifest in manifests.items():
        path = OUT/'g6_visual_final_sources03'/(label+'.zip')
        with zipfile.ZipFile(path) as archive:
            assert archive.testzip() is None
            index = json.loads(archive.read('evidence/source-index.json'))
            assert all(hashlib.sha256(archive.read(p)).hexdigest() == h for p, h in index.items())
            assert hashlib.sha256(archive.read('evidence/run-manifest.json')).hexdigest() == sha(manifest)
            assert index['tools/unified_edit_pipeline/run_gpu_contract.ps1'] == load(manifest)['tool_sha256'].lower() if label in dict(RUNS) else True
        archives.append({**identity(path), 'sources': len(index), 'all_members_verified': True})
    with zipfile.ZipFile(OUT/'g6_visual_final_sources03/protocol.zip') as archive:
        assert hashlib.sha256(archive.read('tests/integration/unified_edit_runtime_configuration_probe.gd')).hexdigest() == sha(ROOT/'tests/integration/unified_edit_runtime_configuration_probe.gd')
    result = {'role': 'partial_T06_enabled_display_stage_component', 'component_pass': True, 'G6_pass': False, 'completed_objectives': 24, 'total_objectives': 36, 'T06_completed': 0, 'runs': runs, 'GPU_cases': sum(len(r['cases']) for r in runs), 'GPU_probe_checks': sum(r['checks'] for r in runs), 'common_runtime_source_count': len(common), 'common_runtime_source_hashes': {p: sources[0][p] for p in sorted(common)}, 'independent_audits': audits, 'cpu_regressions': cpu, 'source_archives': archives, 'builder': identity(Path(__file__)), 'verified_scope': ['Optional foam/local-front/narrow-or-wide/gravel stages use retained shaders once per actual GPU water tick under the common decision', 'All stage RIDs belong to existing Water lifetime ownership; no second simulation pump or tool-private publication loop', 'Published read-only visual clones share the same sealed state as sand/water and stay unchanged on fatal, including earlier partial private physical edits', 'Original standalone visual recorder classes independently match the common stage bytes on the same physical inputs', 'Pure edit completion reprojects gravel onto the visible final bed without advancing time; guarded common copy protects stable visual slots on fatal', 'Enabled capture reads actual history and publication bytes, restores both visual slots including index=1 and distinct inactive bytes, and verifies actual registered candidate readers before admission', 'Actual PNG materials, continued edits/ticks, enabled two-slot domain handoff and generation ownership are checked', 'Optional-stage initialization failure/unknown cleanup, bad CFL, midbatch revision exhaustion, failed candidate and capture registration/unknown boundaries return all eight owner types to zero', 'Typed wide flag and gravel count boundaries reject invalid runtime configuration before RD allocation'], 'provisional_evidence': [identity(OUT/'g6_visual_boot01_sources.zip'), identity(OUT/'g6_visual_matrix02_sources.zip'), identity(OUT/'g6_visual_independent02.json')], 'source_tool_difference': 'Visual matrix runner was archived before adding only the handoff_visuals whitelist label. Current runtime source hashes match across all groups; each archive retains its actual runner.', 'pending': ['Prescribed tide/wave native capture/restore and actual geometry-backed tide_mode3 boundary', 'Formal main/test1 three-entry and UI wiring; legacy writer/fallback retirement; gravel spawn intent integration', 'Continuously advancing preview readiness and full formal open-stroke/close/unknown lifecycle matrix', 'G7 configuration-only extension audit and G8 full visible load cost/long stability'], 'formal_entries_changed': False, 'performance_pass': False}
    TARGET.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({'component_pass': True, 'G6_pass': False, 'GPU_cases': result['GPU_cases'], 'GPU_checks': result['GPU_probe_checks'], 'common_sources': len(common), 'report': str(TARGET.resolve())}))


if __name__ == '__main__':
    main()
