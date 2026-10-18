"""Seal a verified delivery; fail closed on missing gates or source drift."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[2]


def read(path):
    return json.loads(path.read_text('utf-8-sig'))


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024*1024), b''):
            value.update(block)
    return value.hexdigest()


def main():
    parser = argparse.ArgumentParser()
    for name in ['matrix', 'cost', 'long', 'architecture', 'output']:
        parser.add_argument('--'+name, type=Path, required=True)
    args = parser.parse_args()
    for name in ['matrix', 'cost', 'long', 'architecture', 'output']:
        setattr(args, name, getattr(args, name).resolve())
    subprocess.run([sys.executable, str(ROOT/'tools/docs/build_execution_guide.py'), '--check'], cwd=ROOT, check=True)
    for name in ['probe_ABI_v3.json', 'height_snapshot_ABI_v3.json', 'C03_G6_运动预算补订.json', 'C04_G6_接触补订.json', 'C05_G6_来源兼容补订.json']:
        assert read(ROOT/'task/sandcastle_floating_props/契约'/name)['status'] == 'frozen', name
    spec = importlib.util.spec_from_file_location('audit', ROOT/'tools/unified_edit_pipeline/audit_architecture.py')
    audit = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(audit)
    sources, _, _ = audit.graph()
    hashes = {p: hashlib.sha256(raw).hexdigest() for p, raw in sources.items()}
    architecture = read(args.architecture/'report.json')
    assert architecture['pass'] and architecture['sources'] == hashes
    progress = read(args.matrix/'progress.json')
    assert progress['complete'] and progress['passed'] and len(progress['rows']) == progress['total']
    identities = []
    functional_checks = 0
    independent_checks = 0
    evidence = {}
    for row in progress['rows']:
        folder = Path(row.get('evidence_dir', args.matrix/row['name'])).resolve()
        manifest = read(folder/'run-manifest.json')
        assert row['passed'] and manifest['pass'] and not manifest['drift']
        assert all(manifest['sources'].get(p) == h for p, h in hashes.items()), row['name']
        identities.append(manifest['engine_sha256'])
        functional_checks += manifest['checks']
        for path in folder.glob('independent_*.json'):
            value = read(path)
            assert value.get('pass', value.get('passed', False)), path
            independent_checks += len(value['checks'])
        for path in folder.glob('*.json'):
            evidence[path.relative_to(ROOT).as_posix()] = digest(path)
    cost = read(args.cost/'comparison.json')
    assert cost['passed'], 'cost gate'
    for folder in args.cost.iterdir():
        if not folder.is_dir() or not (folder/'run-manifest.json').exists():
            continue
        manifest = read(folder/'run-manifest.json')
        assert manifest['pass'] and not manifest['drift']
        assert all(manifest['sources'].get(p) == h for p, h in hashes.items()), folder.name
        identities.append(manifest['engine_sha256'])
        for path in folder.glob('*.json'):
            evidence[path.relative_to(ROOT).as_posix()] = digest(path)
    long_manifest = read(args.long/'run-manifest.json')
    long_result = read(args.long/'probe.json')
    long_independent = read(args.long/'independent_physics.json')
    assert long_manifest['pass'] and long_result['pass'] and long_independent['pass']
    assert not long_manifest['drift']
    changes = [p for p, h in hashes.items() if long_manifest['sources'].get(p) != h]
    allowed = {'scripts/simulation/unified_edit/configuration.gd',
               'scripts/simulation/unified_edit/checkpoint_codec.gd',
               'scripts/simulation/unified_edit/consumer_checkpoint_sources.gd',
               'assets/unified_edit/floating_props_source_catalog.variant'}
    assert set(changes) <= allowed, changes
    identities.append(long_manifest['engine_sha256'])
    assert len(set(identities)) == 1
    for folder in [args.long, args.architecture]:
        for path in folder.glob('*.json'):
            evidence[path.relative_to(ROOT).as_posix()] = digest(path)
    # Include exact test/verification tools and current documentation/contracts.
    for base in ['tests/floating_props', 'tools/floating_props', 'task/sandcastle_floating_props']:
        for path in (ROOT/base).rglob('*'):
            if path.is_file() and path.suffix in {'.gd', '.tscn', '.tres', '.gdshader', '.py', '.md', '.json'}:
                sources.setdefault(path.relative_to(ROOT).as_posix(), path.read_bytes())
    for name in ['README.md', '漂浮道具.md', '当前项目技术方案.md', '当前技术规格.md', '主场景操作.md', '场景切换与功能复用.md', 'unified-edit-extension-guide.md', 'project-execution-guide.html', 'project-execution-guide.sources.json']:
        path = ROOT/'docs'/name
        sources[path.relative_to(ROOT).as_posix()] = path.read_bytes()
    for name in ['tools/unified_edit_pipeline/architecture_policy.json', 'tools/unified_edit_pipeline/audit_architecture.py', 'tools/unified_edit_pipeline/audit_formal_scenes.gd', 'tools/docs/build_unified_execution_guide.py', 'project.godot']:
        sources[name] = (ROOT/name).read_bytes()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    with zipfile.ZipFile(output/'final_sources.zip', 'x', zipfile.ZIP_DEFLATED) as archive:
        for path, raw in sorted(sources.items()):
            archive.writestr(path, raw)
    assert all((ROOT/path).read_bytes() == raw for path, raw in sources.items()), 'delivery source changed during seal'
    report = dict(schema=1, status='frozen', passed=True,
                  production_sources=hashes,
                  delivery_sources={p: hashlib.sha256(b).hexdigest() for p, b in sources.items()},
                  evidence=evidence, engine_sha256=identities[0],
                  final_matrix=str(args.matrix), final_matrix_functional_checks=functional_checks,
                  final_matrix_independent_checks=independent_checks,
                  long_run=str(args.long), long_run_post_physics_identity_changes=changes,
                  source_scope='The300s physical implementation is identical; later deterministic configuration hashing/strict known-source validation changes have final initialization/migration/lifecycle regressions. No claim of byte-identical long-run source after that nonphysical fix.',
                  cost=str(args.cost), architecture=str(args.architecture),
                  final_sources_zip_sha256=digest(output/'final_sources.zip'))
    (output/'index.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print('DELIVERY_SEAL', True, 'sources', len(sources), 'functional', functional_checks, 'independent', independent_checks)


if __name__ == '__main__':
    main()
