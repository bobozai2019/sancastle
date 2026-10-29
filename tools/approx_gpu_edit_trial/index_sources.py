import hashlib
import json
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[2]
def manifest():
    files = []
    for directory in ['tests/experiments/approx_gpu_edit','tools/approx_gpu_edit_trial',
                      'scripts/experiments/approx_gpu_edit','assets/approx_gpu_edit',
                      'shaders/experiments/approx_gpu_edit']:
        for p in sorted((root/directory).rglob('*')):
            if p.is_file() and p.suffix in ['.gd','.glsl','.tscn','.tres','.res','.py']:
                data = p.read_bytes()
                files.append({'path':p.relative_to(root).as_posix(),'size':len(data),'sha256':hashlib.sha256(data).hexdigest(),'mtime_ns':p.stat().st_mtime_ns})
    p = root / 'scenes/approx_gpu_edit.tscn'
    data = p.read_bytes()
    files.append({'path':p.relative_to(root).as_posix(),'size':len(data),'sha256':hashlib.sha256(data).hexdigest(),'mtime_ns':p.stat().st_mtime_ns})
    return files

if __name__ == '__main__':
    (root/'test_output/approx_gpu_edit_trial'/sys.argv[1]/'candidate_sources.json').write_text(json.dumps(manifest(),indent=2),encoding='utf-8')
