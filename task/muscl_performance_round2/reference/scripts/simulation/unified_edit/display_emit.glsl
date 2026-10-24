#[compute]
#version 450
// UE_LAYOUT
layout(local_size_x=64) in;
layout(set=0,binding=0,rgba32f) uniform readonly image2D candidate;
layout(set=0,binding=1,rgba32f) uniform writeonly image2D current;
layout(set=0,binding=2,std430) readonly buffer Input {uint input_words[];};
layout(set=0,binding=3,std430) buffer Control {uint control[];};
layout(set=0,binding=4,std430) buffer Output {uint result[];};
layout(set=0,binding=5,std430) buffer DisplayMeta {uint meta[];};
layout(push_constant,std430) uniform Params {uint phase;} p;
const uint UDB_MAGIC=0x31424455u,UDC_MAGIC=0x31434455u,UDR_MAGIC=0x31524455u;
uint c(uint word){return input_words[UE_HEADER_BYTES/4u+word];}
bool newer(uvec2 a,uvec2 b){return a.y>b.y||(a.y==b.y&&a.x>b.x);}
void pair_out(uint word,uint low,uint high){uint b=UE_COMPLETION_BYTES/4u;result[b+word]=low;result[b+word+1u]=high;}
void main(){
 if(control[1]!=0u)return;
 uint id=gl_GlobalInvocationID.x,b=UE_COMPLETION_BYTES/4u;
 if(p.phase==0u){
  if(id!=0u)return;
  for(uint j=0u;j<UE_RESULT_BYTES/4u;j++)result[b+j]=0u;
  meta[1]=meta[0];meta[2]=meta[0];meta[3]=0u;meta[4]=0u;meta[5]=0u;
  uint count=c(4u);vec2 point=vec2(uintBitsToFloat(c(48u)),uintBitsToFloat(c(49u)));
  bool valid=input_words[UE_H_MAGIC_WORD]==UDB_MAGIC&&input_words[UE_H_WORK_KIND_WORD]==2u&&input_words[UE_H_COMMAND_COUNT_WORD]==1u;
  valid=valid&&c(0u)==UDC_MAGIC&&c(1u)==1u&&c(2u)==UE_COMMAND_BYTES&&c(3u)==1u&&count>0u&&count<=128u;
  valid=valid&&all(equal(uvec2(c(10u),c(11u)),uvec2(control[2],control[3])))&&newer(uvec2(c(8u),c(9u)),uvec2(meta[16],meta[17]));
  valid=valid&&!newer(uvec2(c(18u),c(19u)),uvec2(control[6],control[7]));
  valid=valid&&!any(isnan(point))&&!any(isinf(point))&&all(lessThanEqual(abs(point),vec2(15.55)));
  for(uint j=0u;j<8u;j++)valid=valid&&c(24u+j)==input_words[UE_H_DOMAIN_HASH_WORD+j]&&c(40u+j)==meta[8u+j];
  if(!valid){meta[5]=1u;return;}
  if(meta[0]>meta[6]||count>meta[6]-meta[0]){meta[5]=2u;return;}
  meta[2]=meta[0]+count;meta[3]=1u;return;
 }
 if(p.phase==1u){
  if(meta[3]==0u||id>=meta[6])return;
  vec4 value=imageLoad(candidate,ivec2(id%64u,id/64u));
  bool valid=!any(isnan(value))&&!any(isinf(value));
  if(id<meta[2])valid=valid&&all(lessThanEqual(abs(value.xz),vec2(16.0)))&&(value.w==0.0||value.w==1.0);
  else valid=valid&&all(equal(value,vec4(0)));
  if(!valid)atomicOr(meta[4],1u);return;
 }
 bool applied=meta[3]!=0u&&meta[4]==0u;
 if(applied&&id<meta[6])imageStore(current,ivec2(id%64u,id/64u),imageLoad(candidate,ivec2(id%64u,id/64u)));
 if(id!=0u)return;
 if(applied)meta[0]=meta[2];
 if(meta[4]!=0u)meta[5]=3u;
 if(newer(uvec2(c(8u),c(9u)),uvec2(meta[16],meta[17]))){meta[16]=c(8u);meta[17]=c(9u);}
 result[b+UE_R_MAGIC_WORD]=UDR_MAGIC;result[b+UE_R_VERSION_WORD]=1u;result[b+UE_R_STRIDE_WORD]=UE_RESULT_BYTES;
 result[b+UE_R_OUTCOME_WORD]=applied?UE_OUTCOME_APPLIED:UE_OUTCOME_REJECTED;
 pair_out(UE_R_COMMAND_ID_WORD,c(8u),c(9u));pair_out(UE_R_GENERATION_WORD,control[2],control[3]);
 pair_out(UE_R_INPUT_REVISION_WORD,control[10],control[11]);pair_out(UE_R_OUTPUT_REVISION_WORD,control[10],control[11]);
 pair_out(UE_R_BATCH_SEQ_WORD,input_words[UE_H_BATCH_SEQ_WORD],input_words[UE_H_BATCH_SEQ_WORD+1u]);
 pair_out(UE_R_LEASE_ID_WORD,input_words[UE_H_LEASE_ID_WORD],input_words[UE_H_LEASE_ID_WORD+1u]);
 result[b+UE_R_SLOT_ID_WORD]=input_words[UE_H_SLOT_ID_WORD];result[b+UE_R_COMPLETION_PHASE_WORD]=1u;
 result[b+UE_R_CHANGED_CELLS_WORD]=applied?c(4u):0u;result[b+UE_R_TOUCHED_CELLS_WORD]=meta[0];
 result[b+UE_R_LEDGER_WORD]=UE_LEDGER_UNCHANGED;result[b+UE_R_PROFILE_VERSION_WORD]=1u;
 result[b+UE_R_ERROR_CODE_WORD]=meta[5];result[b+UE_R_INVALID_FLAGS_WORD]=meta[4];
 for(uint j=0u;j<8u;j++){result[b+UE_R_DOMAIN_HASH_WORD+j]=c(24u+j);result[b+UE_R_EFFECTIVE_HASH_WORD+j]=c(32u+j);}
}
