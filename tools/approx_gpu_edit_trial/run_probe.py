import os
import subprocess
import sys
from datetime import datetime
from index_sources import manifest
import json
from pathlib import Path

root = Path(__file__).resolve().parents[2]
probe = next((a.split('=',1)[1] for a in sys.argv[1:] if a.startswith('--probe=')),'functional')
run_id = probe + '_' + datetime.now().strftime('%Y%m%d_%H%M%S_%f')
output = root / 'test_output/approx_gpu_edit_trial' / run_id
output.mkdir(parents=True, exist_ok=False)
(output/'candidate_sources.json').write_text(json.dumps(manifest(),indent=2),encoding='utf-8')
command = [r'D:\game\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe',
           '--path', str(root), '--rendering-driver', 'd3d12', '--script',
           'res://tests/experiments/approx_gpu_edit/'+probe+'_probe.gd','--', '--run-id='+run_id] + [a for a in sys.argv[1:] if not a.startswith('--probe=')]
(output / 'command.txt').write_text(subprocess.list2cmdline(command), encoding='utf-8')
result = subprocess.run(command, capture_output=True, encoding='utf-8', errors='replace', timeout=100)
(output / 'stdout.log').write_text(result.stdout, encoding='utf-8')
(output / 'stderr.log').write_text(result.stderr, encoding='utf-8')
print(result.stdout[-3000:])
print(result.stderr[-3000:])
print('EXIT', result.returncode)
print('RUN',run_id)
marker = 'PASS: trial functional' if probe=='functional' else 'PASS: '+probe
failed = result.returncode != 0 or any(s in result.stderr for s in ['ERROR:', 'SCRIPT ERROR', 'SHADER ERROR']) or marker not in result.stdout
(output / 'validation.json').write_text(__import__('json').dumps({'accepted':not failed,'exit':result.returncode}),encoding='utf-8')
raise SystemExit(1 if failed else 0)
