#[compute]
#version 450
// UE_LAYOUT
layout(local_size_x=1) in;
layout(set=0,binding=0,std430) readonly buffer Input {uint input_words[];};
layout(set=0,binding=1,std430) buffer Control {uint control[];};
layout(set=0,binding=2,std430) buffer Output {uint result[];};
layout(set=0,binding=4,r32f) uniform writeonly image2D completed_clock;
void pair_out(uint at,uint low,uint high){result[at]=low;result[at+1u]=high;}
void main(){
 uint count=input_words[UE_H_COMMAND_COUNT_WORD];
 if(control[1]==0u){uint low=control[4]+1u;control[5]+=uint(low==0u);control[4]=low;}
 uint accepted=0u,rejected=0u;
 for(uint index=0u;index<count&&index<UE_MAX_COMMANDS;index++){
  uint base=UE_COMPLETION_BYTES/4u+index*UE_RESULT_BYTES/4u;
  uint outcome=result[base+UE_R_OUTCOME_WORD];
  if(outcome==UE_OUTCOME_REJECTED)rejected++;
  else if(outcome==UE_OUTCOME_APPLIED||outcome==UE_OUTCOME_NO_CHANGE)accepted++;
  else if(control[1]==0u)control[1]|=4u;
  pair_out(base+UE_R_STATE_SEQ_WORD,control[4],control[5]);
  pair_out(base+UE_R_APPLIED_TICK_WORD,control[6],control[7]);
 }
 result[UE_DONE_MAGIC_WORD]=UE_COMPLETION_MAGIC;result[UE_DONE_VERSION_WORD]=UE_VERSION;
 result[UE_DONE_STRIDE_WORD]=UE_COMPLETION_BYTES;result[UE_DONE_RESULT_COUNT_WORD]=count;
 pair_out(UE_DONE_GENERATION_WORD,control[2],control[3]);
 pair_out(UE_DONE_BATCH_SEQ_WORD,input_words[UE_H_BATCH_SEQ_WORD],input_words[UE_H_BATCH_SEQ_WORD+1u]);
 pair_out(UE_DONE_LEASE_ID_WORD,input_words[UE_H_LEASE_ID_WORD],input_words[UE_H_LEASE_ID_WORD+1u]);
 pair_out(UE_DONE_STATE_SEQ_WORD,control[4],control[5]);pair_out(UE_DONE_SIM_TICK_WORD,control[6],control[7]);
 pair_out(UE_DONE_REVISION_WORD,control[10],control[11]);
 result[UE_DONE_SLOT_ID_WORD]=input_words[UE_H_SLOT_ID_WORD];
 result[UE_DONE_STATE_WORD]=control[1]==0u?UE_STATE_COMPLETE:UE_STATE_FATAL;
 result[UE_DONE_ERROR_FLAGS_WORD]=control[1];result[UE_DONE_RESULT_STRIDE_WORD]=UE_RESULT_BYTES;
 result[UE_DONE_ADVANCED_TIME_S_WORD]=control[8];result[UE_DONE_ACTUAL_DT_WORD]=control[9];
 result[UE_DONE_ACCEPTED_COUNT_WORD]=accepted;result[UE_DONE_REJECTED_COUNT_WORD]=rejected;
 if(control[1]==0u){control[18]+=accepted;control[19]+=rejected;imageStore(completed_clock,ivec2(0),vec4(uintBitsToFloat(control[8])));}
}
