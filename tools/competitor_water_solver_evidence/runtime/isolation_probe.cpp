#include <windows.h>
#include <shlobj.h>
#include <knownfolders.h>
#include <fstream>
#include <iostream>
#include <string>
int wmain(int argc,wchar_t** argv){
 if(argc!=8)return 2;
 wchar_t guardReady[8]={};bool guardBeforeMain=GetEnvironmentVariableW(L"CODEX_WATER_GUARD_READY",guardReady,8)==1&&guardReady[0]==L'1';
 int renderdocApi=-1;HMODULE rd=GetModuleHandleW(L"renderdoc.dll");if(rd){auto get=reinterpret_cast<int(*)(int,void**)>(GetProcAddress(rd,"RENDERDOC_GetAPI"));void* table=nullptr;if(get)renderdocApi=get(10600,&table);}
 std::wstring entry=std::wstring(argv[2])+L".entry";HANDLE entryFile=CreateFileW(entry.c_str(),GENERIC_WRITE,0,nullptr,CREATE_ALWAYS,FILE_ATTRIBUTE_NORMAL,nullptr);if(entryFile!=INVALID_HANDLE_VALUE)CloseHandle(entryFile);
 PWSTR path=nullptr;HRESULT hr=SHGetKnownFolderPath(FOLDERID_LocalAppDataLow,0,nullptr,&path);
 if(FAILED(hr))return 3;
 std::wstring expected=argv[1];bool correct=std::wstring(path)==expected;CoTaskMemFree(path);
 bool otherFolders=true,legacyFolders=true;
 const KNOWNFOLDERID* ids[]={&FOLDERID_LocalAppData,&FOLDERID_RoamingAppData,&FOLDERID_Profile};
 const int legacyIds[]={CSIDL_LOCAL_APPDATA,CSIDL_APPDATA,CSIDL_PROFILE};
 for(int i=0;i<3;++i){
  path=nullptr;HRESULT result=SHGetKnownFolderPath(*ids[i],0,nullptr,&path);
  if(FAILED(result)||!path||std::wstring(path)!=argv[4+i])otherFolders=false;
  if(path)CoTaskMemFree(path);
  wchar_t oldPath[MAX_PATH]={};result=SHGetFolderPathW(nullptr,legacyIds[i],nullptr,0,oldPath);
  if(FAILED(result)||std::wstring(oldPath)!=argv[4+i])legacyFolders=false;
 }
 HANDLE good=CreateFileW(argv[2],GENERIC_WRITE,0,nullptr,CREATE_ALWAYS,FILE_ATTRIBUTE_NORMAL,nullptr);
 if(good==INVALID_HANDLE_VALUE)return 4;DWORD written=0;WriteFile(good,"isolated",8,&written,nullptr);CloseHandle(good);
 HANDLE bad=CreateFileW(argv[3],GENERIC_WRITE,0,nullptr,CREATE_ALWAYS,FILE_ATTRIBUTE_NORMAL,nullptr);
 bool denied=bad==INVALID_HANDLE_VALUE;DWORD deniedError=GetLastError();if(!denied)CloseHandle(bad);
 HANDLE alias=CreateFileW(argv[7],GENERIC_WRITE,0,nullptr,CREATE_ALWAYS,FILE_ATTRIBUTE_NORMAL,nullptr);
 DWORD aliasWritten=0;if(alias!=INVALID_HANDLE_VALUE){WriteFile(alias,"redirect",8,&aliasWritten,nullptr);CloseHandle(alias);}
 alias=CreateFileW(argv[7],GENERIC_READ,FILE_SHARE_READ,nullptr,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,nullptr);
 DWORD aliasRead=0;char aliasData[8]={};if(alias!=INVALID_HANDLE_VALUE){ReadFile(alias,aliasData,8,&aliasRead,nullptr);CloseHandle(alias);}
 bool aliasCorrect=aliasWritten==8&&aliasRead==8&&std::string(aliasData,8)=="redirect";
 std::wstring renamed=std::wstring(argv[2])+L".renamed",outsideRename=std::wstring(argv[3])+L".renamed";
 bool renameWithin=MoveFileExW(argv[2],renamed.c_str(),MOVEFILE_REPLACE_EXISTING)!=FALSE;
 bool renameOutside=MoveFileExW(renamed.c_str(),outsideRename.c_str(),MOVEFILE_REPLACE_EXISTING)==FALSE;
 HKEY foreign=nullptr;LONG foreignWrite=-1;
 if(RegOpenKeyExW(HKEY_LOCAL_MACHINE,L"SOFTWARE",0,KEY_READ,&foreign)==0){DWORD v=1;foreignWrite=RegSetValueExW(foreign,L"CodexProbeDenied",0,REG_DWORD,reinterpret_cast<BYTE*>(&v),4);RegCloseKey(foreign);}
 STARTUPINFOW si={};si.cb=sizeof(si);PROCESS_INFORMATION pi={};std::wstring command=L"\""+std::wstring(argv[0])+L"\" --child";
 bool childDenied=CreateProcessW(nullptr,command.data(),nullptr,nullptr,FALSE,CREATE_NO_WINDOW,nullptr,nullptr,&si,&pi)==FALSE;
 if(!childDenied){TerminateProcess(pi.hProcess,9);CloseHandle(pi.hThread);CloseHandle(pi.hProcess);}
 HKEY key=nullptr;DWORD disposition=0;const wchar_t* name=L"Software\\CodexWaterSolverEvidence\\IsolationProbe";
 LONG create=RegCreateKeyExW(HKEY_CURRENT_USER,name,0,nullptr,0,KEY_ALL_ACCESS,nullptr,&key,&disposition);
 DWORD value=0x57415452,read=0,bytes=4,type=0;LONG set=-1,query=-1;
 if(!create){set=RegSetValueExW(key,L"value",0,REG_DWORD,reinterpret_cast<const BYTE*>(&value),4);query=RegQueryValueExW(key,L"value",nullptr,&type,reinterpret_cast<BYTE*>(&read),&bytes);RegCloseKey(key);}
 std::cout<<"{\"folder_correct\":"<<(correct?"true":"false")<<",\"other_folders_correct\":"<<(otherFolders?"true":"false")<<",\"legacy_folders_correct\":"<<(legacyFolders?"true":"false")<<",\"owned_write_bytes\":"<<written<<",\"outside_write_denied\":"<<(denied?"true":"false")
 <<",\"deny_error\":"<<deniedError<<",\"rename_within\":"<<(renameWithin?"true":"false")<<",\"rename_outside_denied\":"<<(renameOutside?"true":"false")
 <<",\"foreign_registry_status\":"<<foreignWrite<<",\"child_denied\":"<<(childDenied?"true":"false")
 <<",\"path_redirect_read_write\":"<<(aliasCorrect?"true":"false")
 <<",\"guard_ready_before_main\":"<<(guardBeforeMain?"true":"false")
 <<",\"renderdoc_api_result\":"<<renderdocApi
 <<",\"registry_create\":"<<create<<",\"registry_set\":"<<set<<",\"registry_query\":"<<query<<",\"registry_value\":"<<read<<"}"<<std::endl;
 return guardBeforeMain&&correct&&otherFolders&&legacyFolders&&written==8&&denied&&aliasCorrect&&renameWithin&&renameOutside&&foreignWrite==5&&childDenied&&create==0&&set==0&&query==0&&read==value?0:5;
}
