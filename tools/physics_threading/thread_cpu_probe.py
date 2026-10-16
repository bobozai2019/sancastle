"""Read-only thread CPU times for one verified, self-launched Godot process."""
import argparse, ctypes as c, hashlib, json, time
from ctypes import wintypes as w
from pathlib import Path
from windows_telemetry import k

class ThreadEntry(c.Structure):
    _fields_=[('size',w.DWORD),('usage',w.DWORD),('tid',w.DWORD),('pid',w.DWORD),
              ('priority',w.LONG),('delta_priority',w.LONG),('flags',w.DWORD)]
k.Thread32First.argtypes=[w.HANDLE,c.POINTER(ThreadEntry)];k.Thread32Next.argtypes=k.Thread32First.argtypes
k.OpenThread.argtypes=[w.DWORD,w.BOOL,w.DWORD];k.OpenThread.restype=w.HANDLE
k.GetThreadTimes.argtypes=[w.HANDLE]+[c.POINTER(w.FILETIME)]*4
k.GetThreadDescription.argtypes=[w.HANDLE,c.POINTER(c.c_void_p)];k.GetThreadDescription.restype=w.LONG
k.LocalFree.argtypes=[c.c_void_p];k.LocalFree.restype=c.c_void_p
k.QueryFullProcessImageNameW.argtypes=[w.HANDLE,w.DWORD,w.LPWSTR,c.POINTER(w.DWORD)]

def ft(value):return (value.dwHighDateTime<<32)+value.dwLowDateTime
def threads(pid):
    snap=k.CreateToolhelp32Snapshot(4,0);entry=ThreadEntry();entry.size=c.sizeof(entry);rows=[]
    try:
        ok=k.Thread32First(snap,c.byref(entry))
        while ok:
            if entry.pid==pid:
                handle=k.OpenThread(0x800,False,entry.tid)
                if handle:
                    try:
                        times=[w.FILETIME() for _ in range(4)]
                        if k.GetThreadTimes(handle,*[c.byref(v) for v in times]):
                            description=c.c_void_p();name=None
                            if k.GetThreadDescription(handle,c.byref(description))>=0 and description:
                                try:name=c.wstring_at(description)
                                finally:k.LocalFree(description)
                            rows.append({'tid':entry.tid,'name':name,'created_filetime_100ns':ft(times[0]),
                                         'kernel_us':ft(times[2])//10,'user_us':ft(times[3])//10})
                        else:rows.append({'tid':entry.tid,'error':c.get_last_error()})
                    finally:k.CloseHandle(handle)
            ok=k.Thread32Next(snap,c.byref(entry))
    finally:k.CloseHandle(snap)
    return rows

def run(live_path,output,seconds):
    live=json.loads(Path(live_path).read_text());pid=live['pid'];handle=k.OpenProcess(0x1000,False,pid)
    if not handle:raise RuntimeError('own process not accessible')
    try:
        buffer=c.create_unicode_buffer(32768);size=w.DWORD(len(buffer))
        if not k.QueryFullProcessImageNameW(handle,0,buffer,c.byref(size)):raise RuntimeError('image identity unavailable')
        if Path(buffer.value).resolve()!=Path(live['command'][0]).resolve():raise RuntimeError('PID image mismatch')
        times=[w.FILETIME() for _ in range(4)]
        if not k.GetProcessTimes(handle,*[c.byref(v) for v in times]):raise RuntimeError('creation time unavailable')
        created_ns=(ft(times[0])-116444736000000000)*100
        if abs(live['started_utc_ns']-created_ns)>10000000000:raise RuntimeError('PID creation time mismatch')
        output=Path(output);output.mkdir(parents=True,exist_ok=True)
        (output/'identity.json').write_text(json.dumps({'pid':pid,'image':buffer.value,'created_utc_ns':created_ns,
            'live_process':str(live_path),'tool_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
            'scope':'read-only GetThreadTimes/GetThreadDescription; no suspend, stack capture, main-thread identity guess or formal cost claim'},indent=2))
        previous={};last_us=None;start=time.monotonic()
        with (output/'threads.jsonl').open('w') as stream:
            while time.monotonic()-start<seconds:
                begin=time.monotonic_ns();rows=threads(pid);end=time.monotonic_ns();now_us=end//1000
                for row in rows:
                    if 'error' in row:continue
                    key=(row['tid'],row['created_filetime_100ns']);cpu=row['kernel_us']+row['user_us']
                    if key in previous:row['cpu_delta_us']=cpu-previous[key]
                    previous[key]=cpu
                stream.write(json.dumps({'monotonic_ns':end,'utc_ns':time.time_ns(),'interval_us':now_us-last_us if last_us else None,
                    'observer_wall_us':(end-begin)//1000,'threads':rows})+'\n');stream.flush();last_us=now_us
                if not rows:break
                time.sleep(1)
    finally:k.CloseHandle(handle)
    print('thread samples saved',output)

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--live-process',required=True);p.add_argument('--output',required=True);p.add_argument('--seconds',type=float,default=10);a=p.parse_args()
    run(a.live_process,a.output,a.seconds)
