"""RenderDoc event timestamps on local replay, not live-game profiling."""
import hashlib
import json
import os
import time
import traceback
from pathlib import Path

ROOT = Path('D:/godot/project/sandcastle')
SCRIPT = ROOT / 'docs/competitor/tools/measure_shader_execution_replay.py'
SOURCE = ROOT / 'sandcastlegame/test1.rdc'
OUT = Path(os.environ['SHADER_TIMING_OUT'])
assert OUT.is_absolute() and str(OUT).isascii()
OUT.mkdir(parents=True, exist_ok=False)

def identity(p):
    return dict(path=p.as_posix(), bytes=p.stat().st_size, sha256=hashlib.sha256(p.read_bytes()).hexdigest())

def save(name,data):
    (OUT/name).write_text(json.dumps(data,indent=2),encoding='utf-8')

report = dict(source=identity(SOURCE),script=identity(SCRIPT),runs=[],success=False,
              limitation='RenderDoc instrumented replay on this host, no original frame CPU/GPU utilization, VSync, or live-game timing claim.')
controller = cap = None
try:
    import renderdoc as rd
    assert report['source']['sha256'] == '761aa980c2426f75a1fa7364bf6d2655ff4dd20ea76566e630ee5b53ea0ec5b2'
    report['version'] = rd.GetVersionString()
    report['tool'] = identity(Path('D:/other_software/RenderDoc/qrenderdoc.exe'))
    report['command'] = 'D:/other_software/RenderDoc/qrenderdoc.exe --python ' + SCRIPT.as_posix()
    report['environment'] = {'SHADER_TIMING_OUT': str(OUT)}
    save('progress.json',{'phase':'open'})
    cap = rd.OpenCaptureFile()
    report['open'] = str(cap.OpenFile(str(SOURCE), '', None))
    status, controller = cap.OpenCapture(rd.ReplayOptions(), None)
    report['replay'] = str(status)
    assert controller is not None
    api = controller.GetAPIProperties()
    report['api'] = {k:str(getattr(api,k)) for k in dir(api) if not k.startswith('_') and not callable(getattr(api,k)) and k not in ['this','thisown']}
    counters = controller.EnumerateCounters()
    report['counters'] = [str(c) for c in counters]
    assert rd.GPUCounter.EventGPUDuration in counters, 'EventGPUDuration unavailable'
    desc = controller.DescribeCounter(rd.GPUCounter.EventGPUDuration)
    report['duration_counter'] = {k:str(getattr(desc,k)) for k in dir(desc) if not k.startswith('_') and not callable(getattr(desc,k)) and k not in ['this','thisown']}
    for index in range(3):
        save('progress.json',{'phase':'fetch_counters','run':index})
        start = time.monotonic()
        data = controller.FetchCounters([rd.GPUCounter.EventGPUDuration])
        rows = [dict(event=r.eventId,counter=str(r.counter),seconds=r.value.d) for r in data]
        save('run_%d.json'%index,rows)
        report['runs'].append(dict(index=index,wall_seconds=time.monotonic()-start,data=identity(OUT/('run_%d.json'%index))))
        save('manifest_partial.json',report)
    report['source_after'] = identity(SOURCE)
    report['success'] = report['source_after']==report['source'] and all(r['data']['bytes']>2 for r in report['runs'])
except Exception:
    report['error'] = traceback.format_exc()
finally:
    if controller: controller.Shutdown()
    if cap: cap.Shutdown()
    save('manifest.json',report)
os._exit(0 if report['success'] else 1)
