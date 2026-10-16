"""Read-only Windows process/NVML telemetry, no shell helpers in measured windows."""
import ctypes as c
import time
from ctypes import wintypes as w

k=c.WinDLL("kernel32",use_last_error=True)
k.OpenProcess.argtypes=[w.DWORD,w.BOOL,w.DWORD];k.OpenProcess.restype=w.HANDLE
k.CloseHandle.argtypes=[w.HANDLE]
k.CreateToolhelp32Snapshot.argtypes=[w.DWORD,w.DWORD];k.CreateToolhelp32Snapshot.restype=w.HANDLE
class ProcessEntry(c.Structure):
    _fields_=[("size",w.DWORD),("usage",w.DWORD),("pid",w.DWORD),("heap",c.c_size_t),("module",w.DWORD),
              ("threads",w.DWORD),("parent",w.DWORD),("priority",w.LONG),("flags",w.DWORD),("exe",w.WCHAR*260)]
k.Process32FirstW.argtypes=[w.HANDLE,c.POINTER(ProcessEntry)];k.Process32NextW.argtypes=[w.HANDLE,c.POINTER(ProcessEntry)]
class Memory(c.Structure):
    _fields_=[("size",w.DWORD),("faults",w.DWORD)]+[(name,c.c_size_t) for name in
        ["peak_rss","rss","peak_paged","paged","peak_nonpaged","nonpaged","pagefile","peak_pagefile","private"]]
k.K32GetProcessMemoryInfo.argtypes=[w.HANDLE,c.POINTER(Memory),w.DWORD]
k.GetProcessTimes.argtypes=[w.HANDLE,c.POINTER(w.FILETIME),c.POINTER(w.FILETIME),c.POINTER(w.FILETIME),c.POINTER(w.FILETIME)]

def process_list():
    handle=k.CreateToolhelp32Snapshot(2,0);entry=ProcessEntry();entry.size=c.sizeof(entry);rows=[]
    try:
        ok=k.Process32FirstW(handle,c.byref(entry))
        while ok:
            if "godot" in entry.exe.lower() or entry.exe.lower() in ["blender.exe"]:
                rows.append({"pid":entry.pid,"name":entry.exe,"threads":entry.threads})
            ok=k.Process32NextW(handle,c.byref(entry))
    finally:k.CloseHandle(handle)
    return rows

class Telemetry:
    def __init__(self,pid):
        self.handle=k.OpenProcess(0x1000|0x10,False,pid)
        self.nvml=None;self.device=c.c_void_p()
        try:
            self.nvml=c.WinDLL("C:/Windows/System32/nvml.dll")
            if self.nvml.nvmlInit_v2()!=0 or self.nvml.nvmlDeviceGetHandleByIndex_v2(0,c.byref(self.device))!=0:self.nvml=None
        except OSError:pass
    def sample(self):
        row={"monotonic_ns":time.monotonic_ns(),"utc_ns":time.time_ns(),"processes":process_list()}
        if self.handle:
            memory=Memory();memory.size=c.sizeof(memory)
            if k.K32GetProcessMemoryInfo(self.handle,c.byref(memory),memory.size):row.update(rss_bytes=memory.rss,private_bytes=memory.private)
            created=w.FILETIME();exited=w.FILETIME();kernel=w.FILETIME();user=w.FILETIME()
            if k.GetProcessTimes(self.handle,c.byref(created),c.byref(exited),c.byref(kernel),c.byref(user)):
                row["process_cpu_us"]=((kernel.dwHighDateTime<<32)+kernel.dwLowDateTime+(user.dwHighDateTime<<32)+user.dwLowDateTime)//10
        if self.nvml:
            class Util(c.Structure):_fields_=[("gpu",c.c_uint),("memory",c.c_uint)]
            util=Util();clock=c.c_uint();temperature=c.c_uint()
            if self.nvml.nvmlDeviceGetUtilizationRates(self.device,c.byref(util))==0:row.update(gpu_percent=util.gpu,gpu_memory_percent=util.memory)
            if self.nvml.nvmlDeviceGetClockInfo(self.device,0,c.byref(clock))==0:row["graphics_clock_mhz"]=clock.value
            if self.nvml.nvmlDeviceGetTemperature(self.device,0,c.byref(temperature))==0:row["gpu_temperature_c"]=temperature.value
        return row
    def close(self):
        if self.handle:k.CloseHandle(self.handle);self.handle=None
        if self.nvml:self.nvml.nvmlShutdown();self.nvml=None
