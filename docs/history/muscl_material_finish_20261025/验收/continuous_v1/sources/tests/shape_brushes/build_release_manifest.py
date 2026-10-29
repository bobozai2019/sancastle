"""Index the current playable candidate; a manifest never grants gate approval."""
import argparse, hashlib, json, re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TEXT = {'.gd', '.glsl', '.glslinc', '.gdshader', '.tscn', '.tres', '.json', '.godot'}

def digest(path):
    with path.open('rb') as stream:
        value = hashlib.file_digest(stream, 'sha256').hexdigest()
    return value

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--evidence', type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    run = json.loads((args.evidence/'manifest.json').read_text(encoding='utf-8-sig'))
    sources = {ROOT/'project.godot'}
    for folder in ['scripts', 'shaders', 'scenes', 'assets']:
        sources.update(p for p in (ROOT/folder).rglob('*') if p.is_file() and p.suffix in TEXT)
    pending = list(sources)
    missing, output_references = [], []
    while pending:
        source = pending.pop()
        if source.suffix not in TEXT:
            continue
        text = source.read_text(encoding='utf-8-sig')
        for ref in sorted(set(re.findall(r'res://[A-Za-z0-9_./-]+', text))):
            relative = ref.removeprefix('res://')
            path = ROOT/relative
            if relative.startswith(('task/', 'test_output/')):
                output_references.append({'source':source.relative_to(ROOT).as_posix(), 'reference':ref})
            if path.is_file():
                if path not in sources:
                    sources.add(path); pending.append(path)
            elif '.' in path.name and '%' not in ref:
                missing.append({'source':source.relative_to(ROOT).as_posix(), 'reference':ref})
    files = [{'path':p.relative_to(ROOT).as_posix(), 'bytes':p.stat().st_size, 'sha256':digest(p)} for p in sorted(sources)]
    entry_names=['scenes/main.tscn','scenes/playable/test1_capture.tscn','scenes/playable/test1_backwash.tscn']
    reachable={ROOT/name for name in entry_names}|{ROOT/'project.godot'}
    pending=list(reachable)
    dynamic_directories=[]
    while pending:
        source=pending.pop()
        if source.suffix not in TEXT:continue
        for ref in sorted(set(re.findall(r'res://[A-Za-z0-9_./-]+',source.read_text(encoding='utf-8-sig')))):
            path=ROOT/ref.removeprefix('res://')
            if path.is_file() and path not in reachable:
                reachable.add(path);pending.append(path)
            elif path.is_dir():
                dynamic_directories.append({'source':source.relative_to(ROOT).as_posix(),'reference':ref})
    reachable_names={p.relative_to(ROOT).as_posix() for p in reachable}
    canonical = json.dumps(files, sort_keys=True, separators=(',', ':')).encode()
    data = {
        'role':'shape_brush_release_candidate', 'status':'candidate_not_released',
        'engine':{k:run[k] for k in ['engine_path','engine_sha256','engine_version']},
        'entries':entry_names,
        'source_inventory_sha256':hashlib.sha256(canonical).hexdigest(), 'files':files,
        'text_reference_scan_missing':missing, 'task_or_output_references':output_references,
        'entry_literal_files':sorted(reachable_names),
        'missing_in_entry_literal_sources':[r for r in missing if r['source'] in reachable_names],
        'output_references_in_entry_literal_sources':[r for r in output_references if r['source'] in reachable_names],
        'dynamic_directory_references':dynamic_directories,
        'scope':'Runtime text inventory and existing literal resource dependencies, including original tests/ prototype dependencies. Dynamic resource paths require runtime signature and actual-entry evidence; this index alone does not establish dependency closure or gate passage.',
        'functional_run':str(args.evidence.resolve()),
        'open_gates':['G4','G5','G6','G7','G8','G9'],
        'performance_rounds':{'used':3,'maximum':3,'status':'stopped_at_user_limit'},
        'remaining':['strict ordinary/zero-support equivalence','strict 300-tick continuation','checkpoint memory plateau','full release acceptance'],
    }
    (args.output/'release_manifest.json').write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')
    print('RELEASE_CANDIDATE',len(files),'missing_literal_references',len(missing),'task_output_references',len(output_references))

if __name__ == '__main__': main()
