"""C01/C02 local request validation. This does not establish GPU pairing."""
import argparse
import hashlib
import json
import re
from pathlib import Path


def identity(path):
    path = Path(path).resolve()
    if not path.is_file():
        return dict(path=path.as_posix(), exists=False, size_bytes=None, sha256=None)
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b''):
            digest.update(chunk)
    return dict(path=path.as_posix(), exists=True, size_bytes=path.stat().st_size, sha256=digest.hexdigest())


def validate(request):
    errors = []

    def fail(code, message):
        errors.append(dict(code=code, message=message, selector=request.get('selector'),
                           artifact_refs=[], retry_condition='Correct request and use a new output directory'))

    required = ['schema_version', 'run_id', 'mode', 'operation', 'source', 'selector',
                'fixed_inputs', 'repeat_index', 'replay_instance_id', 'variation',
                'output_root', 'environment', 'tool']
    for field in required:
        if field not in request:
            fail('FIELD_MISSING', field)
    if errors:
        return errors
    if request['schema_version'] != '1.0' or not re.fullmatch(r'[A-Za-z0-9_-]+', request['run_id']):
        fail('SCHEMA_INVALID', 'Version or run_id')
    if request['mode'] not in ['static_audit', 'rdc_replay', 'native_reference', 'replay_instrumented', 'runtime_trace', 'godot_probe']:
        fail('UNSUPPORTED_BACKEND', 'Unknown mode')
    if request['operation'] not in ['audit', 'sync_graph', 'snapshot_pair', 'repeat', 'trace', 'compare']:
        fail('SCHEMA_INVALID', 'Unknown operation')
    out = Path(request['output_root'])
    if not out.is_absolute() or not str(out).isascii() or out.exists():
        fail('OUTPUT_INVALID', 'Requires a new absolute ASCII output directory')
    parent = out.parent
    while not parent.exists() and parent != parent.parent:
        parent = parent.parent
    if not parent.is_dir():
        fail('OUTPUT_INVALID', 'Output ancestor is not a writable directory')
    sources = request['source'] if isinstance(request['source'], list) else [request['source']]
    for source in sources:
        actual = identity(source['source_path'])
        if actual['sha256'] != source['source_sha256'] or actual['size_bytes'] != source['source_size']:
            fail('SOURCE_IDENTITY_MISMATCH', source['source_path'])
        if out.resolve().is_relative_to(Path(source['source_path']).resolve().parent):
            fail('OUTPUT_INVALID', 'Output must be outside original source directory')
    for artifact in request['fixed_inputs']:
        actual = identity(artifact['path'])
        if actual['size_bytes'] != artifact['size_bytes'] or actual['sha256'] != artifact['sha256']:
            fail('DEPENDENCY_MISSING', artifact['path'])
    selector = request['selector']
    if request['mode'] == 'rdc_replay' and (not isinstance(selector, dict) or
            any(key not in selector for key in ['capture_sha256', 'event_id', 'stage', 'boundary'])):
        fail('SELECTOR_MISMATCH', 'Missing exact capture/event/stage/boundary')
    elif request['mode'] == 'rdc_replay' and selector['capture_sha256'] not in [s['source_sha256'] for s in sources]:
        fail('SELECTOR_MISMATCH', 'Selector is for a different capture')
    if request.get('pairing', {}).get('pairing_kind') in ['same_execution', 'reconstructed_controlled'] and not request['pairing'].get('proof_artifact_ids'):
        fail('PAIRING_UNPROVEN', 'Pair ID is not evidence')
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--request', required=True, type=Path)
    args = parser.parse_args()
    errors = validate(json.loads(args.request.read_text(encoding='utf-8')))
    print(json.dumps(dict(operation_status='failed' if errors else 'complete',
                         verification_status='not_evaluated', errors=errors), indent=2))
    raise SystemExit(1 if errors else 0)


if __name__ == '__main__':
    main()
