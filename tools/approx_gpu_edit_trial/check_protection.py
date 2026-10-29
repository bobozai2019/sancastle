import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parents[2]
base = root/'test_output/approx_gpu_edit_trial/baseline'
identity = json.loads((base/'production_identity.json').read_text(encoding='utf-8-sig'))
changed = []
for item in identity['files']:
    path = Path(item['path'])
    if not path.exists() or hashlib.sha256(path.read_bytes()).hexdigest()!=item['sha256']:
        changed.append(item['path'])
extensions = {'.gd','.glsl','.gdshader','.tscn','.tres','.json','.png','.jpg','.webp'}
expected = {str(Path(x['path']).resolve()).lower() for x in identity['files']}
added = []
for directory in identity['scan_roots']:
    for path in (root/directory).rglob('*'):
        if path.is_file() and path.suffix in extensions and str(path.resolve()).lower() not in expected:
            added.append(str(path))
report = {'checked':len(identity['files']),'changed':changed,'new_scanned_files':added,'accepted':not changed and not added,'scope':'Production configuration source scan and project.godot exact bytes; engine/adapter/flags reported separately.'}
(base/'protection_check.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print(json.dumps(report,ensure_ascii=False))
raise SystemExit(0 if report['accepted'] else 1)
