import ctypes as c, time, json, argparse
from ctypes import wintypes as w
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--pid',type=int,required=True);p.add_argument('--output',required=True);p.add_argument('--dump-path');p.add_argument('--heartbeat');p.add_argument('--active-window-us',type=int,default=6000000);a=p.parse_args()
k=c.WinDLL('kernel32',use_last_error=True)
class TE(c.Structure):
 _fields_=[('size',w.DWORD),('usage',w.DWORD),('tid',w.DWORD),('pid',w.DWORD),('base',w.LONG),('delta',w.LONG),('flags',w.DWORD)]
k.OpenProcess.argtypes=[w.DWORD,w.BOOL,w.DWORD];k.OpenProcess.restype=w.HANDLE
k.OpenThread.argtypes=[w.DWORD,w.BOOL,w.DWORD];k.OpenThread.restype=w.HANDLE
k.CreateToolhelp32Snapshot.argtypes=[w.DWORD,w.DWORD];k.CreateToolhelp32Snapshot.restype=w.HANDLE
for name in ['GetProcessTimes','GetThreadTimes']:
 f=getattr(k,name);f.argtypes=[w.HANDLE,c.POINTER(w.FILETIME),c.POINTER(w.FILETIME),c.POINTER(w.FILETIME),c.POINTER(w.FILETIME)];f.restype=w.BOOL
k.CloseHandle.argtypes=[w.HANDLE];k.CloseHandle.restype=w.BOOL
for name in ['Thread32First','Thread32Next']:
 f=getattr(k,name);f.argtypes=[w.HANDLE,c.POINTER(TE)];f.restype=w.BOOL
k.GetExitCodeProcess.argtypes=[w.HANDLE,c.POINTER(w.DWORD)];k.GetExitCodeProcess.restype=w.BOOL
k.GetThreadDescription.argtypes=[w.HANDLE,c.POINTER(c.c_void_p)];k.GetThreadDescription.restype=c.c_long
k.LocalFree.argtypes=[c.c_void_p];k.LocalFree.restype=c.c_void_p
adv=c.WinDLL('advapi32',use_last_error=True)
class Lock(c.Structure):
 _fields_=[('name',w.WCHAR*128),('timeout',c.c_longlong),('alertable',w.BOOL)]
class Thread(c.Structure):
 _fields_=[('pid',w.DWORD),('tid',w.DWORD),('wait_ms',w.DWORD),('switches',w.DWORD)]
class Payload(c.Union):
 _fields_=[('lock',Lock),('thread',Thread)]
class Node(c.Structure):
 _fields_=[('type',w.DWORD),('status',w.DWORD),('value',Payload)]
assert c.sizeof(Node)==280
adv.OpenThreadWaitChainSession.argtypes=[w.DWORD,c.c_void_p];adv.OpenThreadWaitChainSession.restype=w.HANDLE
adv.CloseThreadWaitChainSession.argtypes=[w.HANDLE]
adv.GetThreadWaitChain.argtypes=[w.HANDLE,c.c_size_t,w.DWORD,w.DWORD,c.POINTER(w.DWORD),c.POINTER(Node),c.POINTER(w.BOOL)];adv.GetThreadWaitChain.restype=w.BOOL
session=adv.OpenThreadWaitChainSession(0,None)
thread_info={};chains=[];chain_next=0;dump_events=[];dump_attempted=False
if a.dump_path:
 dbg=c.WinDLL('C:/Program Files (x86)/Windows Kits/10/Debuggers/x64/dbghelp.dll',use_last_error=True)
 dbg.MiniDumpWriteDump.argtypes=[w.HANDLE,w.DWORD,w.HANDLE,w.DWORD,c.c_void_p,c.c_void_p,c.c_void_p];dbg.MiniDumpWriteDump.restype=w.BOOL
 k.CreateFileW.argtypes=[w.LPCWSTR,w.DWORD,w.DWORD,c.c_void_p,w.DWORD,w.DWORD,w.HANDLE];k.CreateFileW.restype=w.HANDLE
handle=k.OpenProcess(0x1000,False,a.pid);threads={};rows=[];errors=[];start=time.monotonic();scan=0
if not handle: raise OSError(c.get_last_error(),'OpenProcess')
def cpu(h,thread=False):
 created,exited,kernel,user=(w.FILETIME() for _ in range(4))
 if not getattr(k,'GetThreadTimes' if thread else 'GetProcessTimes')(h,c.byref(created),c.byref(exited),c.byref(kernel),c.byref(user)): return None
 return ((kernel.dwHighDateTime<<32)+kernel.dwLowDateTime+(user.dwHighDateTime<<32)+user.dwLowDateTime)/10
while time.monotonic()-start<180:
 code=w.DWORD()
 if not k.GetExitCodeProcess(handle,c.byref(code)) or code.value!=259: break
 if time.monotonic()>=scan:
  snap=k.CreateToolhelp32Snapshot(4,0);entry=TE();entry.size=c.sizeof(TE)
  if snap and snap!=c.c_void_p(-1).value:
   found=k.Thread32First(snap,c.byref(entry))
   while found:
    if entry.pid==a.pid and entry.tid not in threads:
     h=k.OpenThread(0x0800,False,entry.tid)
     if h:
      threads[entry.tid]=h
      ptr=c.c_void_p();description=''
      if k.GetThreadDescription(h,c.byref(ptr))==0 and ptr.value:
       description=c.wstring_at(ptr.value);k.LocalFree(ptr)
      created,exited,kernel,user=(w.FILETIME() for _ in range(4))
      k.GetThreadTimes(h,c.byref(created),c.byref(exited),c.byref(kernel),c.byref(user))
      thread_info[entry.tid]={'description':description,'created_100ns':(created.dwHighDateTime<<32)+created.dwLowDateTime}
    found=k.Thread32Next(snap,c.byref(entry))
   k.CloseHandle(snap)
  scan=time.monotonic()+.25
 if a.dump_path and not dump_attempted and a.heartbeat:
  try:
   raw=Path(a.heartbeat).read_bytes()
   if len(raw)==16:
    import struct
    begun,beat=struct.unpack('<QQ',raw);now=time.time_ns()//1000
    if begun>0 and now-beat>=200000 and 0<now-begun<a.active_window_us:
     dump_attempted=True;event={'utc_start_us':now,'heartbeat_us':beat,'natural_stale_us':now-beat}
     ph=k.OpenProcess(0x0410,False,a.pid)
     fh=k.CreateFileW(a.dump_path,0x40000000,0,None,1,0x80,None)
     if ph and fh and fh!=c.c_void_p(-1).value:
      event['ok']=bool(dbg.MiniDumpWriteDump(ph,a.pid,fh,0x1000,None,None,None));event['error']=0 if event['ok'] else c.get_last_error()
     else: event.update(ok=False,error=c.get_last_error())
     if ph:k.CloseHandle(ph)
     if fh and fh!=c.c_void_p(-1).value:k.CloseHandle(fh)
     event['utc_end_us']=time.time_ns()//1000;dump_events.append(event)
  except (OSError,ValueError): pass
 row={'utc_us':time.time_ns()//1000,'process_cpu_us':cpu(handle),'threads':{str(t):value for t,h in threads.items() if (value:=cpu(h,True)) is not None}}
 rows.append(row)
 if session and thread_info and time.monotonic()>=chain_next:
  earliest=min(thread_info,key=lambda t:thread_info[t]['created_100ns'])
  selected={earliest}|{t for t,v in thread_info.items() if 'render' in v['description'].lower()}
  for tid in selected:
   nodes=(Node*16)();number=w.DWORD(16);cycle=w.BOOL()
   ok=adv.GetThreadWaitChain(session,0,0,tid,c.byref(number),nodes,c.byref(cycle))
   record={'utc_us':time.time_ns()//1000,'tid':tid,'ok':bool(ok),'error':0 if ok else c.get_last_error(),'cycle':bool(cycle.value),'nodes':[]}
   if ok:
    for node in nodes[:min(number.value,16)]:
     item={'type':node.type,'status':node.status}
     if node.type==8: item.update(pid=node.value.thread.pid,tid=node.value.thread.tid,wait_ms=node.value.thread.wait_ms,switches=node.value.thread.switches)
     else: item['name']=node.value.lock.name
     record['nodes'].append(item)
   chains.append(record)
  chain_next=time.monotonic()+.1
 time.sleep(.01)
for h in threads.values(): k.CloseHandle(h)
k.CloseHandle(handle)
if session: adv.CloseThreadWaitChainSession(session)
Path(a.output).write_text(json.dumps({'pid':a.pid,'scope':'own-process CPU time sampling; no stack/native function attribution','period_target_ms':10,'scan_thread_ms':250,'thread_info':thread_info,'wait_chains':chains,'dump_events':dump_events,'wait_chain_out_of_process_follow':False,'samples':rows,'errors':errors},separators=(',',':')),encoding='utf-8')
