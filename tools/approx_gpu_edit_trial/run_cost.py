import json
import subprocess
import sys
import threading
import time
from datetime import datetime
from pathlib import Path
from index_sources import manifest

root = Path(__file__).resolve().parents[2]
run_id = 'cost_' + datetime.now().strftime('%Y%m%d_%H%M%S_%f')
output = root / 'test_output/approx_gpu_edit_trial' / run_id
output.mkdir(parents=True, exist_ok=False)
(output/'candidate_sources.json').write_text(json.dumps(manifest(),indent=2),encoding='utf-8')
inventory = subprocess.run(['powershell','-NoProfile','-Command',"Get-Process | Where-Object {$_.ProcessName -match 'godot|renderdoc|blender'} | Select-Object Id,ProcessName,Path | ConvertTo-Json"],capture_output=True,encoding='utf-8',errors='replace',timeout=20)
(output/'gpu_processes_before.json').write_text(inventory.stdout or '[]',encoding='utf-8')
seconds = next((float(a.split('=',1)[1]) for a in sys.argv[1:] if a.startswith('--seconds=')),30)
command = [r'D:\game\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe', '--path',str(root),'--rendering-driver','d3d12','--script','res://tests/experiments/approx_gpu_edit/cost_probe.gd','--','--run-id='+run_id]+sys.argv[1:]
(output/'command.txt').write_text(subprocess.list2cmdline(command),encoding='utf-8')
stop = threading.Event()
telemetry = []
def sample_gpu():
    while not stop.is_set():
        try:
            sample = subprocess.run(['nvidia-smi','--query-gpu=name,driver_version,temperature.gpu,utilization.gpu,clocks.current.graphics,clocks.current.memory,power.draw','--format=csv,noheader,nounits'],capture_output=True,encoding='utf-8',errors='replace',timeout=5)
            telemetry.append({'unix_ns_string':str(time.time_ns()),'values':sample.stdout.strip(),'error':sample.stderr.strip(),'exit':sample.returncode})
        except Exception as error:
            telemetry.append({'error':str(error)})
        stop.wait(1.0)
sampler = threading.Thread(target=sample_gpu,daemon=True)
sampler.start()
try:
    result = subprocess.run(command,capture_output=True,encoding='utf-8',errors='replace',timeout=seconds+100)
    stdout,stderr,code = result.stdout,result.stderr,result.returncode
except subprocess.TimeoutExpired as e:
    stdout = (e.stdout or b'').decode('utf-8',errors='replace') if isinstance(e.stdout,bytes) else (e.stdout or '')
    stderr = (e.stderr or b'').decode('utf-8',errors='replace') if isinstance(e.stderr,bytes) else (e.stderr or '')
    code = -1
stop.set()
sampler.join(timeout=6)
(output/'gpu_telemetry.json').write_text(json.dumps(telemetry,indent=2),encoding='utf-8')
(output/'stdout.log').write_text(stdout,encoding='utf-8')
(output/'stderr.log').write_text(stderr,encoding='utf-8')
failed = code != 0 or 'ERROR:' in stderr or 'PASS: cost operation' not in stdout
if (output/'result.json').exists():
    report = json.loads((output/'result.json').read_text(encoding='utf-8'))
    failed = failed or not report.get('controlled',False)
(output/'validation.json').write_text(json.dumps({'accepted':not failed,'exit':code}),encoding='utf-8')
print(stdout[-1500:]);print(stderr[-1500:]);print('RUN',run_id,'ACCEPTED',not failed,flush=True)
raise SystemExit(1 if failed else 0)
