"""Read-only Windows process inventory for exclusive Godot performance windows."""
import ctypes
from ctypes import wintypes

class Entry(ctypes.Structure):
    _fields_=[('dwSize',wintypes.DWORD),('cntUsage',wintypes.DWORD),('th32ProcessID',wintypes.DWORD),
              ('th32DefaultHeapID',ctypes.c_size_t),('th32ModuleID',wintypes.DWORD),('cntThreads',wintypes.DWORD),
              ('th32ParentProcessID',wintypes.DWORD),('pcPriClassBase',wintypes.LONG),('dwFlags',wintypes.DWORD),
              ('szExeFile',wintypes.WCHAR*260)]

def godot_processes():
    kernel=ctypes.WinDLL('kernel32',use_last_error=True)
    kernel.CreateToolhelp32Snapshot.restype=wintypes.HANDLE
    kernel.CreateToolhelp32Snapshot.argtypes=[wintypes.DWORD,wintypes.DWORD]
    kernel.Process32FirstW.argtypes=[wintypes.HANDLE,ctypes.POINTER(Entry)]
    kernel.Process32NextW.argtypes=[wintypes.HANDLE,ctypes.POINTER(Entry)]
    kernel.CloseHandle.argtypes=[wintypes.HANDLE]
    handle=kernel.CreateToolhelp32Snapshot(2,0)
    if handle==ctypes.c_void_p(-1).value:
        raise ctypes.WinError(ctypes.get_last_error())
    result=[]
    try:
        entry=Entry();entry.dwSize=ctypes.sizeof(Entry)
        valid=kernel.Process32FirstW(handle,ctypes.byref(entry))
        while valid:
            if 'godot' in entry.szExeFile.lower():
                result.append({'pid':int(entry.th32ProcessID),'name':entry.szExeFile})
            valid=kernel.Process32NextW(handle,ctypes.byref(entry))
    finally:kernel.CloseHandle(handle)
    return result

if __name__=='__main__':
    import json
    print(json.dumps(godot_processes()))
