"""Seal an isolated consumer handoff component without claiming formal G6."""
import hashlib
import json
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT/'test_output/unified_edit_pipeline'
TARGET = ROOT/'task/sandcastle_unified_edit_pipeline/验收/G6_消费者交接组件.json'
RUNS = [('handoff', 'g6_handoff_matrix03'), ('height', 'g6_handoff_height03'), ('views', 'g6_handoff_views03'), ('spine', 'g6_handoff_spine03'), ('capture', 'g6_handoff_capture03')]
AUDITS = ['g6_handoff_independent03.json', 'g6_handoff_height_independent03/result.json', 'g6_handoff_views_independent03/result.json', 'g6_handoff_spine_independent03.json', 'g6_handoff_capture_independent03.json']


def load(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def identity(path):
    return {'path': str(path.resolve()), 'bytes': path.stat().st_size, 'sha256': sha(path)}


def main():
    if TARGET.exists():
        raise SystemExit('Fresh component required')
    sources, runs, audits, archives, cpu = [], [], [], [], []
    manifests = {}
    for label, directory in RUNS:
        path = OUT/directory/'run-manifest.json';data = load(path)
        assert data['pass'] and not data['drift'] and all(r['pass'] for r in data['runs'])
        mapping = {p.replace('\\', '/'): h.lower() for p, h in data['sources'].items()}
        assert all(sha(ROOT/p) == h for p, h in mapping.items())
        sources.append(mapping);manifests[label] = path
        runs.append({'label': label, 'manifest': identity(path), 'cases': [r['case'] for r in data['runs']], 'checks': sum(r['checks'] for r in data['runs'])})
    common = set.intersection(*(set(s) for s in sources))
    assert all(len({s[k] for s in sources}) == 1 for k in common)
    for relative in AUDITS:
        path = OUT/relative;data = load(path);assert data['pass']
        audits.append({**identity(path), 'checks': len(data.get('checks', [])), 'raw_cases': len(data.get('records', []))})
    for label, expected in [('protocol', 212), ('configuration', 87)]:
        path = OUT/('g6_handoff_'+label+'03')/'run-manifest.json';data = load(path)
        assert data['pass'] and not data['drift'] and data['checks'] == expected
        assert all(sha(ROOT/p) == h.lower() for p, h in data['sources'].items())
        manifests[label] = path;cpu.append({'label': label, 'manifest': identity(path), 'checks': expected})
    for label, manifest in manifests.items():
        path = OUT/'g6_handoff_final_sources03'/(label+'.zip')
        with zipfile.ZipFile(path) as archive:
            assert archive.testzip() is None
            index = json.loads(archive.read('evidence/source-index.json'))
            assert all(hashlib.sha256(archive.read(p)).hexdigest() == h for p, h in index.items())
            assert hashlib.sha256(archive.read('evidence/run-manifest.json')).hexdigest() == sha(manifest)
        archives.append({**identity(path), 'sources': len(index), 'all_members_verified': True})
    result = {'role': 'partial_T06_two_static_consumer_slot_handoff_component', 'component_pass': True, 'G6_pass': False, 'completed_objectives': 24, 'total_objectives': 36, 'T06_completed': 0, 'runs': runs, 'GPU_cases': sum(len(r['cases']) for r in runs), 'GPU_probe_checks': sum(r['checks'] for r in runs), 'common_runtime_source_count': len(common), 'common_runtime_source_hashes': {p: sources[0][p] for p in sorted(common)}, 'independent_audits': audits, 'cpu_regressions': cpu, 'source_archives': archives, 'builder': identity(Path(__file__)), 'verified_scope': ['Scene-authored two sets of 64 collision chunks; inactive staging cannot collide before the physics-phase material/active-surface commit', 'Candidate checkpoint generation and all native maps agree before commit, including saved state_seq lower than a previously used surface', 'Old material parameters restored synchronously and new wrappers bound in the same main physics stack; GPU teardown waits frame and actual readback proofs', 'Old held preview rejected by generation after commit; unknown detach keeps all old GPU resources until explicit retry', 'Candidate preflight/initialization failure and cancellation keep current real PNG pixels and ray collision', 'Ten successful continuation/restore cycles reuse both surface slots; eight nested owner types return to zero', 'Old unclaimed results survive GPU retirement, with one 512-result capacity limit across generations', 'Known unrecorded work remains aborted; recorded work with no GPU result stays unknown after lifetime-only proof; failed current work drains for replacement'], 'preserved_failures': [identity(OUT/'g6_handoff_boot01/run-manifest.json'), identity(OUT/'g6_handoff_boot01_sources.zip')], 'pending': ['Enabled local-front/foam/gravel and prescribed tide/wave capture/restore', 'Formal three-entry cutover, actual UI wiring and retirement of reachable legacy writer/fallback paths', 'Continuously advancing preview readiness, full formal scene lifecycle matrix including close/unknown staging', 'G7 configuration extension and G8 full visible load cost/long stability'], 'formal_entries_changed': False, 'performance_pass': False}
    TARGET.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({'component_pass': True, 'G6_pass': False, 'GPU_cases': result['GPU_cases'], 'GPU_checks': result['GPU_probe_checks'], 'common_sources': len(common), 'report': str(TARGET.resolve())}))


if __name__ == '__main__':
    main()
