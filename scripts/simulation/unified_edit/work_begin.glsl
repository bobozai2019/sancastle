#[compute]
#version 450
// UE_LAYOUT
layout(local_size_x=1) in;
layout(set=0,binding=0,std430) readonly buffer Input {uint input_words[];};
layout(set=0,binding=1,std430) buffer Control {uint control[];};
layout(set=0,binding=2,std430) buffer Output {uint result[];};
layout(set=0,binding=3,std430) readonly buffer Guard {uint guard[];};
void main(){
 for(uint j=0u;j<UE_COMPLETION_BYTES/4u;j++)result[j]=0u;
 bool display=input_words[UE_H_MAGIC_WORD]==0x31424455u;
 bool valid=((!display&&input_words[UE_H_MAGIC_WORD]==UE_BATCH_MAGIC&&input_words[UE_H_VERSION_WORD]==UE_VERSION)||(display&&input_words[UE_H_VERSION_WORD]==1u))
  &&input_words[UE_H_STRIDE_WORD]==UE_HEADER_BYTES&&input_words[UE_H_COMMAND_STRIDE_WORD]==UE_COMMAND_BYTES
  &&input_words[UE_H_RESULT_STRIDE_WORD]==UE_RESULT_BYTES&&input_words[UE_H_SLOT_ID_WORD]<UE_WORK_SLOTS
  &&all(equal(uvec2(input_words[UE_H_GENERATION_WORD],input_words[UE_H_GENERATION_WORD+1u]),uvec2(control[2],control[3])));
 for(uint j=0u;j<8u;j++)valid=valid&&input_words[UE_H_DOMAIN_HASH_WORD+j]==guard[j];
 uint count=input_words[UE_H_COMMAND_COUNT_WORD],kind=input_words[UE_H_WORK_KIND_WORD];
 valid=valid&&(display?(kind==2u&&count==1u):((kind==UE_WORK_EDIT&&count>0u&&count<=UE_MAX_COMMANDS)||(kind==UE_WORK_WATER_TICK&&count==0u)));
 if(!valid)control[1]|=2u;
 if(control[4]==0xffffffffu&&control[5]==0x7fffffffu)control[1]|=32u;
 control[9]=0u; // Each work unit reports its own dt; edits advance no time.
}
