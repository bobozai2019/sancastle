/* Owned observer glue, Windows x64 only. No game/business methods. */
#include <gum/guminterceptor.h>
typedef unsigned int U32;
typedef unsigned long long U64;
typedef struct { U64 object; int id; U32 kind; U32 bits; U32 dirty; long long qpc; } Entry;
typedef struct { U32 dirty_count; U32 overflow; U64 compute_calls; U64 global_calls; U64 drains; U64 updates; } Counts;
extern Entry cache_entries[];
extern U32 dirty_indices[];
extern Counts cache_counts[];
extern unsigned char cache_lock[];
extern void InitializeCriticalSection(void *);
extern void EnterCriticalSection(void *);
extern void LeaveCriticalSection(void *);
extern int QueryPerformanceCounter(long long *);
extern U32 GetLastError(void);
extern void SetLastError(U32);

void init(void){InitializeCriticalSection(cache_lock);}

static void record(U32 kind,void *object,int id,float value){
 U32 error=GetLastError(),i,slot;U64 key=(U64)object;union {float f;U32 bits;} v;v.f=value;
 EnterCriticalSection(cache_lock);
 if(kind==1)cache_counts->compute_calls++;else cache_counts->global_calls++;
 slot=(U32)((key>>4)^((U32)id*2654435761U)^(kind*2246822519U))&(CACHE_CAPACITY-1);
 for(i=0;i<CACHE_CAPACITY;i++){
  Entry *e=&cache_entries[(slot+i)&(CACHE_CAPACITY-1)];
  if(e->kind==0||(e->object==key&&e->id==id&&e->kind==kind)){
   if(e->kind==0||e->bits!=v.bits){
    e->object=key;e->id=id;e->kind=kind;e->bits=v.bits;QueryPerformanceCounter(&e->qpc);cache_counts->updates++;
    if(!e->dirty){e->dirty=1;dirty_indices[cache_counts->dirty_count++]=(slot+i)&(CACHE_CAPACITY-1);}
   }
   break;
  }
 }
 if(i==CACHE_CAPACITY)cache_counts->overflow++;
 LeaveCriticalSection(cache_lock);SetLastError(error);
}

void compute_enter(GumInvocationContext *ic){
 if(!ic->cpu_context->xmm){EnterCriticalSection(cache_lock);cache_counts->overflow++;LeaveCriticalSection(cache_lock);return;}
 record(1,gum_invocation_context_get_nth_argument(ic,0),(int)(U64)gum_invocation_context_get_nth_argument(ic,1),ic->cpu_context->xmm[2].s[0]);
}
void global_enter(GumInvocationContext *ic){
 if(!ic->cpu_context->xmm){EnterCriticalSection(cache_lock);cache_counts->overflow++;LeaveCriticalSection(cache_lock);return;}
 record(2,(void*)0,(int)(U64)gum_invocation_context_get_nth_argument(ic,0),ic->cpu_context->xmm[1].s[0]);
}

U32 drain(Entry *output,U32 capacity){
 U32 i,n;EnterCriticalSection(cache_lock);n=cache_counts->dirty_count;
 if(n>capacity){cache_counts->overflow++;LeaveCriticalSection(cache_lock);return 0;}
 for(i=0;i<n;i++){
  Entry *e=&cache_entries[dirty_indices[i]];output[i].object=e->object;output[i].id=e->id;output[i].kind=e->kind;output[i].bits=e->bits;output[i].qpc=e->qpc;output[i].dirty=0;e->dirty=0;
 }
 cache_counts->dirty_count=0;cache_counts->drains++;LeaveCriticalSection(cache_lock);return n;
}
