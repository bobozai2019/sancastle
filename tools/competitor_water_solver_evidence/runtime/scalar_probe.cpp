#include <windows.h>
#include <atomic>
#include <cstring>
#include <iostream>
#include <thread>
struct Context {unsigned expected,bits;int id,index;};
Context contexts[2];std::atomic<unsigned> failures{0},entryErrors{0},exitErrors{0};unsigned globalBits[2];
std::atomic<unsigned> observedEntryError{0};
unsigned bits(float x){unsigned u;std::memcpy(&u,&x,4);return u;}
extern "C" __declspec(dllexport) __declspec(noinline) void probe_compute(void *object,int id,float value){
 Context* c=nullptr;for(int i=0;i<2;i++)if(object==&contexts[i])c=&contexts[i];
 if(!c){failures++;return;}if(c->id!=id||c->expected!=bits(value))failures++;if(GetLastError()!=0x12340000U+c->index){observedEntryError=GetLastError();entryErrors++;failures++;}c->bits=bits(value);SetLastError(0x56780000U+c->index);
}
extern "C" __declspec(dllexport) __declspec(noinline) void probe_global(int id,float value){
 int i=id-1000;if(i<0||i>1){failures++;return;}if(contexts[i].expected!=bits(value))failures++;if(GetLastError()!=0x12340000U+i){observedEntryError=GetLastError();entryErrors++;failures++;}globalBits[i]=bits(value);SetLastError(0x56780000U+i);
}
extern "C" __declspec(dllexport) __declspec(noinline) void probe_done(){volatile int marker=1;(void)marker;}
extern "C" __declspec(dllexport) __declspec(noinline) void probe_checkpoint(int index,unsigned code,void* context){volatile int marker=index;(void)marker;(void)code;(void)context;}
void work(int index){
 auto& c=contexts[index];c.id=857;c.index=index;unsigned initial[]={0,0x80000000,0x3ccccccd,0x7fc12345,0x7f800000,0xff800000};
 for(unsigned j=0;j<10006;j++){
  unsigned code=j<6?initial[j]:(0x3f800000U|((j-6)&65535));float value;std::memcpy(&value,&code,4);c.expected=code;
  SetLastError(0x12340000U+index);probe_compute(&c,c.id,value);if(GetLastError()!=0x56780000U+index){exitErrors++;failures++;}
  SetLastError(0x12340000U+index);probe_global(1000+index,value);if(GetLastError()!=0x56780000U+index){exitErrors++;failures++;}
  if(j<6)probe_checkpoint(index,code,&c);
 }
}
int main(){wchar_t ready[8]={};bool guarded=GetEnvironmentVariableW(L"CODEX_WATER_GUARD_READY",ready,8)==1&&ready[0]==L'1';std::thread a(work,0),b(work,1);a.join();b.join();probe_done();
 std::cout<<"{\"guarded\":"<<(guarded?"true":"false")<<",\"failures\":"<<failures.load()<<",\"entry_error_failures\":"<<entryErrors.load()<<",\"exit_error_failures\":"<<exitErrors.load()<<",\"observed_entry_error\":"<<observedEntryError.load()<<",\"compute0_bits\":"<<contexts[0].bits<<",\"compute1_bits\":"<<contexts[1].bits<<",\"global0_bits\":"<<globalBits[0]<<",\"global1_bits\":"<<globalBits[1]<<"}"<<std::endl;
 return guarded&&failures.load()==0?0:1;}
