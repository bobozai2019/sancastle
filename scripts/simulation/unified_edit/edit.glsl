#[compute]
#version 450
// UE_LAYOUT
#define UE_REDUCE_BLOCKS (UE_SUMMARY_BUFFER_BYTES/(UE_SUMMARY_WORD_COUNT*4u)-1u)
layout(local_size_x=256) in;
layout(set=0,binding=0,std430) readonly buffer Input {uint input_words[];};
layout(set=0,binding=1,std430) buffer Control {uint control[];};
layout(set=0,binding=2,std430) buffer Command {uint c[];};
layout(set=0,binding=3,std430) buffer Cells {uint v[];};
layout(set=0,binding=4,std430) buffer Summary {uint s[];};
layout(set=0,binding=5,std430) buffer Decision {uint d[];};
layout(set=0,binding=6,std430) buffer Output {uint result[];};
layout(set=0,binding=7,r32f) uniform image2D sand0;
layout(set=0,binding=8,r32f) uniform image2D sand1;
layout(set=0,binding=9,r32f) uniform readonly image2D rock;
layout(set=0,binding=10,r32f) uniform readonly image2D water;
layout(set=0,binding=11,r16f) uniform image2D compact;
layout(set=0,binding=12,rg32f) uniform image2D support0;
layout(set=0,binding=13,rg32f) uniform image2D support1;
layout(set=0,binding=14,std430) buffer AllocationSteps {float step_amount[];};
layout(set=0,binding=15,std430) buffer AllocationBlocks {vec4 allocation[];};
layout(set=0,binding=16,std430) buffer Stroke {uint stroke[];};
layout(set=0,binding=17,std430) readonly buffer Templates {uint templates[];};
layout(set=0,binding=18,r32f) uniform image2D baseline;
layout(set=0,binding=19,rg32f) uniform image2D coverage;
layout(set=0,binding=20,rg32f) uniform image2D candidate_coverage;
layout(set=0,binding=21,r16f) uniform image2D compact1;
layout(set=0,binding=23,r16f) uniform image2D candidate_compaction;
layout(set=0,binding=22,r8) uniform readonly image2D obstacle;
layout(set=0,binding=24,std430) buffer TransferPrefix {vec4 transfer_prefix[];};
layout(set=0,binding=25,std430) buffer TransferState {float tx[];};
layout(set=0,binding=26,r32f) uniform image2D sediment0;
layout(set=0,binding=27,r32f) uniform image2D sediment1;
layout(push_constant,std430) uniform Params {uint mode,index,groups,reserved;}p;
shared vec4 values[256];
shared uvec4 meta[256];
shared ivec4 bounds[256];
shared vec2 extras[256];
shared uint changed_fields[256];
shared uint coverage_changes[256];
shared vec4 sorted_left[256];
shared vec4 sorted_right[256];
shared vec2 received[256];
float cf(uint word){return uintBitsToFloat(c[word]);}
float vf(uint k,uint word){return uintBitsToFloat(v[k+word]);}
bool finite_value(float a){return !isnan(a)&&!isinf(a);}
float ulp(float a){uint exponent=(floatBitsToUint(abs(a))>>23u)&255u;return exponent==0u?uintBitsToFloat(1u):exp2(float(int(exponent)-150));}
uint rb(){return UE_COMPLETION_BYTES/4u+p.index*UE_RESULT_BYTES/4u;}
void put_pair(uint at,uint a,uint b){result[rb()+at]=a;result[rb()+at+1u]=b;}
bool is_control(){return c[UE_C_CONTROL_KIND_WORD]!=UE_CONTROL_NONE;}
bool is_target(){return !is_control()&&c[UE_C_OPERATION_WORD]==UE_OP_TARGET_HEIGHT;}
bool is_volume(){return !is_control()&&c[UE_C_OPERATION_WORD]==UE_OP_VOLUME_DELTA;}
bool is_smooth(){return !is_control()&&c[UE_C_OPERATION_WORD]==UE_OP_REDISTRIBUTE;}
bool is_adjust(){return !is_control()&&c[UE_C_OPERATION_WORD]==UE_OP_FIELD_ADJUST;}
bool is_transfer(){return !is_control()&&c[UE_C_OPERATION_WORD]==UE_OP_TRANSFER;}
bool is_stroke(){return is_target()||is_transfer();}
bool is_suspended(){return !is_control()&&c[UE_C_DESTINATION_WORD]==UE_DEST_SUSPENDED_SAND;}
float capacity(uint k){return max(0.0,vf(k,UE_CELL_TARGET_HEIGHT)-vf(k,UE_CELL_ROCK)-vf(k,UE_CELL_OLD_VALUE));}
void compensated_add(float a,inout float sum,inout float correction){precise float y=a-correction;precise float next=sum+y;correction=(next-sum)-y;sum=next;}
// Sorted per-block prefix sums turn each capped-weight query into 8 binary
// search steps per block instead of another scan over every receiver.
float allocated(float lambda,uint side){
 float sum=0.0,corr=0.0;
 for(uint group=0u;group<p.groups;group++){
  uint base=(group*2u+side)*256u,lo=0u,hi=256u;
  while(lo<hi){uint mid=(lo+hi)/2u;if(transfer_prefix[base+mid].x<=lambda)lo=mid+1u;else hi=mid;}
  vec4 prefix=lo==0u?vec4(0):transfer_prefix[base+lo-1u],total=transfer_prefix[base+255u];
  compensated_add(max(0.0,prefix.y+lambda*max(0.0,total.z-prefix.z)),sum,corr);
 }return sum;
}
bool material_changed(uint k){return !is_suspended()&&(v[k+UE_CELL_NEW_COMPACTION]!=v[k+UE_CELL_OLD_COMPACTION]||v[k+UE_CELL_NEW_TAG]!=v[k+UE_CELL_OLD_TAG]||v[k+UE_CELL_NEW_REFERENCE]!=v[k+UE_CELL_OLD_REFERENCE]);}
bool physical_changed(uint k){return v[k+UE_CELL_NEW_VALUE]!=v[k+UE_CELL_OLD_VALUE]||material_changed(k);}
uint cell_index(uint lane){return is_target()||c[UE_C_CONTROL_KIND_WORD]==UE_CONTROL_BEGIN?lane:(c[UE_C_RECT_Z_WORD]+lane/c[UE_C_RECT_W_WORD])*256u+c[UE_C_RECT_X_WORD]+lane%c[UE_C_RECT_W_WORD];}
bool newer(uvec2 a,uvec2 b){return a.y>b.y||(a.y==b.y&&a.x>b.x);}
bool matches_stroke(){return stroke[0]==1u&&all(equal(uvec2(c[UE_C_STROKE_ID_WORD],c[UE_C_STROKE_ID_WORD+1u]),uvec2(stroke[2],stroke[3])))&&all(equal(uvec2(c[UE_C_BASELINE_TOKEN_WORD],c[UE_C_BASELINE_TOKEN_WORD+1u]),uvec2(stroke[4],stroke[5])));}
vec4 texel(ivec2 q){uint base=4u+(c[UE_C_TEMPLATE_INDEX_WORD]-1u)*(4u+65u*65u*4u)+4u+uint(q.y*65+q.x)*4u;return vec4(uintBitsToFloat(templates[base]),uintBitsToFloat(templates[base+1u]),uintBitsToFloat(templates[base+2u]),uintBitsToFloat(templates[base+3u]));}
vec3 stamp(vec2 q){
 vec2 world=(q+0.5-128.0)*cf(UE_C_CELL_SIZE_M_WORD)-vec2(cf(UE_C_START_X_WORD),cf(UE_C_START_Z_WORD));
 float co=cos(cf(UE_C_YAW_RAD_WORD)),si=sin(cf(UE_C_YAW_RAD_WORD));vec2 local=vec2(co*world.x+si*world.y,-si*world.x+co*world.y)/cf(UE_C_SCALE_XZ_WORD);
 if(any(lessThan(local,vec2(-2)))||any(greaterThan(local,vec2(2))))return vec3(0);
 vec2 uv=(local+2.0)/cf(UE_C_TEMPLATE_SPACING_M_WORD);ivec2 lo=ivec2(floor(uv)),hi=min(lo+1,ivec2(64));vec2 t=fract(uv);
 float h=mix(mix(texel(lo).x,texel(ivec2(hi.x,lo.y)).x,t.x),mix(texel(ivec2(lo.x,hi.y)).x,texel(hi).x,t.x),t.y);
 return vec3(h*cf(UE_C_HEIGHT_M_WORD)+cf(UE_C_DATUM_Y_M_WORD),texel(ivec2(floor(uv+0.5))).yz);
}
void error(uint code){d[8]=code;}
void mark_dirty(inout uvec2 mask,uint x,uint z){
 uint chunk=(z/32u)*8u+x/32u;
 mask[chunk/32u]|=1u<<(chunk%32u);
 if(x%32u==0u&&x>0u){uint j=chunk-1u;mask[j/32u]|=1u<<(j%32u);}
 if(z%32u==0u&&z>0u){uint j=chunk-8u;mask[j/32u]|=1u<<(j%32u);}
 if(x%32u==0u&&z%32u==0u&&x>0u&&z>0u){uint j=chunk-9u;mask[j/32u]|=1u<<(j%32u);}
}
void main(){
 uint lane=gl_GlobalInvocationID.x,l=gl_LocalInvocationID.x;
 if(p.mode==0u){
  if(lane!=0u)return;
  uint offset=UE_HEADER_BYTES/4u+p.index*UE_COMMAND_BYTES/4u;
  for(uint j=0u;j<UE_COMMAND_BYTES/4u;j++)c[j]=input_words[offset+j];
  for(uint j=0u;j<32u;j++)d[j]=0u;
  for(uint j=0u;j<UE_RESULT_BYTES/4u;j++)result[rb()+j]=0u;
  result[rb()+UE_R_MAGIC_WORD]=UE_RESULT_MAGIC;result[rb()+UE_R_VERSION_WORD]=UE_VERSION;result[rb()+UE_R_STRIDE_WORD]=UE_RESULT_BYTES;
  put_pair(UE_R_COMMAND_ID_WORD,c[UE_C_COMMAND_ID_WORD],c[UE_C_COMMAND_ID_WORD+1u]);
  put_pair(UE_R_GENERATION_WORD,c[UE_C_GENERATION_WORD],c[UE_C_GENERATION_WORD+1u]);
  put_pair(UE_R_STROKE_ID_WORD,c[UE_C_STROKE_ID_WORD],c[UE_C_STROKE_ID_WORD+1u]);
  put_pair(UE_R_BASELINE_TOKEN_WORD,c[UE_C_BASELINE_TOKEN_WORD],c[UE_C_BASELINE_TOKEN_WORD+1u]);
  put_pair(UE_R_SAMPLE_INDEX_WORD,c[UE_C_SAMPLE_INDEX_WORD],c[UE_C_SAMPLE_INDEX_WORD+1u]);
  put_pair(UE_R_INPUT_REVISION_WORD,control[10],control[11]);put_pair(UE_R_OUTPUT_REVISION_WORD,control[10],control[11]);
  put_pair(UE_R_BATCH_SEQ_WORD,input_words[UE_H_BATCH_SEQ_WORD],input_words[UE_H_BATCH_SEQ_WORD+1u]);
  put_pair(UE_R_LEASE_ID_WORD,input_words[UE_H_LEASE_ID_WORD],input_words[UE_H_LEASE_ID_WORD+1u]);
  result[rb()+UE_R_SLOT_ID_WORD]=input_words[UE_H_SLOT_ID_WORD];result[rb()+UE_R_COMPLETION_PHASE_WORD]=1u;
  result[rb()+UE_R_PROFILE_VERSION_WORD]=c[UE_C_PROFILE_VERSION_WORD];result[rb()+UE_R_LEDGER_WORD]=is_control()?UE_LEDGER_UNCHANGED:c[UE_C_LEDGER_WORD];
  for(uint j=0u;j<8u;j++){result[rb()+UE_R_DOMAIN_HASH_WORD+j]=c[UE_C_DOMAIN_HASH_WORD+j];result[rb()+UE_R_EFFECTIVE_HASH_WORD+j]=c[UE_C_EFFECTIVE_HASH_WORD+j];}
  bool valid=c[UE_C_MAGIC_WORD]==UE_COMMAND_MAGIC&&c[UE_C_VERSION_WORD]==UE_VERSION&&c[UE_C_STRIDE_WORD]==UE_COMMAND_BYTES
   &&c[UE_C_GENERATION_WORD]==control[2]&&c[UE_C_GENERATION_WORD+1u]==control[3];
  for(uint j=0u;j<8u;j++)valid=valid&&c[UE_C_DOMAIN_HASH_WORD+j]==input_words[UE_H_DOMAIN_HASH_WORD+j];
  if(!valid){control[1]|=2u;return;}
  if(control[1]!=0u)return;
  if(c[UE_C_SIM_TICK_WORD+1u]>control[7]||(c[UE_C_SIM_TICK_WORD+1u]==control[7]&&c[UE_C_SIM_TICK_WORD]>control[6])){error(UE_ERROR_STALE_TICK);return;}
  if(is_control()){
   result[rb()+UE_R_LEDGER_WORD]=UE_LEDGER_UNCHANGED;
   if(c[UE_C_CONTROL_KIND_WORD]==UE_CONTROL_BEGIN){
    if(stroke[0]!=0u)error(UE_ERROR_INVALID_BASELINE);
   }else if(!matches_stroke())error(UE_ERROR_INVALID_BASELINE);
   return;
  }
  bool local_field=is_smooth()||is_adjust();
  if((!is_volume()&&!is_stroke()&&!local_field)||(c[UE_C_DESTINATION_WORD]!=(is_adjust()?UE_DEST_MATERIAL:UE_DEST_BED_SAND)&&!(is_volume()&&is_suspended()&&c[UE_C_VOLUME_SIGN_WORD]==UE_SIGN_ADD))||(is_volume()&&c[UE_C_MATERIAL_POLICY_WORD]!=UE_MATERIAL_PLAIN)||((local_field||is_transfer())&&c[UE_C_MATERIAL_POLICY_WORD]!=UE_MATERIAL_PRESERVE)||(local_field&&c[UE_C_SHAPE_WORD]!=UE_SHAPE_DISK)){error(UE_ERROR_UNSUPPORTED_PROFILE);return;}
  if(is_stroke()){
   if(!matches_stroke()||(stroke[8]!=0u&&!newer(uvec2(c[UE_C_SAMPLE_INDEX_WORD],c[UE_C_SAMPLE_INDEX_WORD+1u]),uvec2(stroke[6],stroke[7])))){error(UE_ERROR_INVALID_BASELINE);return;}
   if(is_transfer()){
    if(c[UE_C_SHAPE_WORD]!=UE_SHAPE_SWEPT_CAPSULE){error(UE_ERROR_UNSUPPORTED_PROFILE);return;}
    for(uint j=0u;j<32u;j++)tx[j]=0.0;
   }else if(c[UE_C_SHAPE_WORD]==UE_SHAPE_HEIGHT_STAMP){
    uint index=c[UE_C_TEMPLATE_INDEX_WORD];
    if(index==0u||index>templates[0]){error(UE_ERROR_TEMPLATE_MISMATCH);return;}
    if(templates[4u+(index-1u)*(4u+65u*65u*4u)]==0u){error(UE_ERROR_INVALID_PLACEMENT);return;}
   }else if(c[UE_C_SHAPE_WORD]!=UE_SHAPE_SWEPT_CAPSULE){error(UE_ERROR_UNSUPPORTED_PROFILE);return;}
   stroke[8]=1u;stroke[6]=c[UE_C_SAMPLE_INDEX_WORD];stroke[7]=c[UE_C_SAMPLE_INDEX_WORD+1u];
   return;
  }
  if(!finite_value(cf(UE_C_STRENGTH_WORD))||cf(UE_C_STRENGTH_WORD)<0.0||cf(UE_C_STRENGTH_WORD)>1.0||cf(UE_C_RADIUS_M_WORD)<=0.0||cf(UE_C_RADIUS_M_WORD)>4.0){error(UE_ERROR_INVALID_COMMAND);return;}
  if(local_field)return;
  float request=cf(UE_C_AMOUNT_M3_WORD)*cf(UE_C_STRENGTH_WORD);
  if(!finite_value(request)||request<0.0||cf(UE_C_RADIUS_M_WORD)<=0.0||cf(UE_C_RADIUS_M_WORD)>4.0){error(UE_ERROR_INVALID_COMMAND);return;}
  d[0]=floatBitsToUint(request);d[1]=d[0];
  if(cf(UE_C_AVAILABLE_M3_WORD)+cf(UE_C_LEGACY_EPSILON_M3_WORD)<request)error(UE_ERROR_BUDGET_EXCEEDED);
  return;
 }
 if(control[1]!=0u)return;
 if(p.mode==8u){
  if(lane!=0u)return;
  uint outcome=d[8]!=0u?UE_OUTCOME_REJECTED:(d[9]>0u?UE_OUTCOME_APPLIED:UE_OUTCOME_NO_CHANGE);
  result[rb()+UE_R_OUTCOME_WORD]=outcome;result[rb()+UE_R_ERROR_CODE_WORD]=d[8];
  if(is_control()){
   if(d[8]==0u){
    if(c[UE_C_CONTROL_KIND_WORD]==UE_CONTROL_BEGIN){stroke[0]=1u;for(uint j=0u;j<2u;j++){stroke[2u+j]=c[UE_C_STROKE_ID_WORD+j];stroke[4u+j]=c[UE_C_BASELINE_TOKEN_WORD+j];}stroke[8]=0u;stroke[9]=0u;}
    else stroke[0]=0u;
   }return;
  }
  float request=cf(UE_C_AMOUNT_M3_WORD)*cf(UE_C_STRENGTH_WORD);
  if(c[UE_C_OPERATION_WORD]==UE_OP_VOLUME_DELTA)result[rb()+(c[UE_C_VOLUME_SIGN_WORD]==UE_SIGN_ADD?UE_R_SOURCE_M3_WORD:UE_R_SINK_M3_WORD)]=floatBitsToUint(request);
  if(d[8]==0u&&d[14]!=0u){result[rb()+UE_R_COVERAGE_CHANGED_WORD]=1u;result[rb()+UE_R_CHANGED_FIELDS_WORD]=UE_FIELD_COVERAGE;}
  if(outcome==UE_OUTCOME_APPLIED){
   uint low=control[10]+1u;control[11]+=uint(low==0u);control[10]=low;
   put_pair(UE_R_OUTPUT_REVISION_WORD,control[10],control[11]);
   uint base=UE_REDUCE_BLOCKS*UE_SUMMARY_WORD_COUNT;
   result[rb()+UE_R_CHANGED_FIELDS_WORD]=s[base+UE_SUMMARY_CHANGED_FIELDS]|(d[14]!=0u?UE_FIELD_COVERAGE:0u);
   result[rb()+UE_R_CHANGED_CELLS_WORD]=s[base+UE_SUMMARY_CHANGED_CELLS];
   result[rb()+UE_R_DIRTY_LOW_WORD]=s[base+UE_SUMMARY_DIRTY_LOW];result[rb()+UE_R_DIRTY_HIGH_WORD]=s[base+UE_SUMMARY_DIRTY_HIGH];
   result[rb()+UE_R_RECT_X_WORD]=s[base+UE_SUMMARY_RECT_MIN_X];result[rb()+UE_R_RECT_Z_WORD]=s[base+UE_SUMMARY_RECT_MIN_Z];
   result[rb()+UE_R_RECT_W_WORD]=s[base+UE_SUMMARY_RECT_MAX_X]-s[base+UE_SUMMARY_RECT_MIN_X]+1u;
   result[rb()+UE_R_RECT_H_WORD]=s[base+UE_SUMMARY_RECT_MAX_Z]-s[base+UE_SUMMARY_RECT_MIN_Z]+1u;
   float net=uintBitsToFloat(s[base+UE_SUMMARY_NET_VOLUME]);float removed=uintBitsToFloat(s[base+UE_SUMMARY_REMOVED]);
   result[rb()+UE_R_ADDED_M3_WORD]=floatBitsToUint(max(0.0,net+removed));result[rb()+UE_R_REMOVED_M3_WORD]=floatBitsToUint(removed);
   if(is_transfer()){
    result[rb()+UE_R_TRANSFERRED_M3_WORD]=floatBitsToUint(removed);
    result[rb()+UE_R_LEFT_RECEIVED_M3_WORD]=s[base+UE_SUMMARY_LEFT_RECEIVED];result[rb()+UE_R_RIGHT_RECEIVED_M3_WORD]=s[base+UE_SUMMARY_RIGHT_RECEIVED];
    result[rb()+UE_R_EPS_TRANSFER_M3_WORD]=d[11];
   }
   if(is_target())result[rb()+UE_R_SOURCE_M3_WORD]=result[rb()+UE_R_ADDED_M3_WORD];
   result[rb()+UE_R_EPS_SAND_M3_WORD]=d[11];result[rb()+UE_R_SAND_ERROR_M3_WORD]=d[10];
   if(is_suspended()){result[rb()+UE_R_EPS_SEDIMENT_M3_WORD]=d[11];result[rb()+UE_R_SEDIMENT_ERROR_M3_WORD]=d[10];}
   if(c[UE_C_WATER_POLICY_WORD]>0u){result[rb()+UE_R_WATER_ERROR_M3_WORD]=d[16];result[rb()+UE_R_EPS_WATER_M3_WORD]=d[17];result[rb()+UE_R_SEDIMENT_ERROR_M3_WORD]=d[18];result[rb()+UE_R_EPS_SEDIMENT_M3_WORD]=d[19];result[rb()+UE_R_IMPULSE_X_M4_S_WORD]=d[20];result[rb()+UE_R_IMPULSE_Z_M4_S_WORD]=d[21];result[rb()+UE_R_DISPLACED_WATER_M3_WORD]=d[22];result[rb()+UE_R_RETAINED_WATER_M3_WORD]=d[23];}
   result[rb()+UE_R_MAX_CELL_DELTA_M_WORD]=s[base+UE_SUMMARY_MAX_DELTA];result[rb()+UE_R_ABSOLUTE_VOLUME_DELTA_M3_WORD]=s[base+UE_SUMMARY_SAND_ABSOLUTE_DELTA];
  }
  result[rb()+UE_R_TOUCHED_CELLS_WORD]=d[12];
  return;
 }
 if(d[8]!=0u)return;
 uint count=is_target()||c[UE_C_CONTROL_KIND_WORD]==UE_CONTROL_BEGIN?65536u:(is_control()?0u:c[UE_C_RECT_W_WORD]*c[UE_C_RECT_H_WORD]),i=lane<count?cell_index(lane):0u,k=i*UE_CELL_WORD_COUNT;
 ivec2 q=ivec2(i%256u,i/256u);float area=cf(UE_C_CELL_SIZE_M_WORD)*cf(UE_C_CELL_SIZE_M_WORD),eps=cf(UE_C_LEGACY_EPSILON_M3_WORD);
 if(p.mode==1u){
  if(lane>=count)return;
  for(uint j=0u;j<UE_CELL_WORD_COUNT;j++)v[k+j]=0u;
  step_amount[i]=0.0;
  vec2 a=vec2(cf(UE_C_START_X_WORD),cf(UE_C_START_Z_WORD)),b=vec2(cf(UE_C_END_X_WORD),cf(UE_C_END_Z_WORD));
  vec2 pos=(vec2(q)+0.5-128.0)*cf(UE_C_CELL_SIZE_M_WORD),segment=b-a,closest=a;
  float l2=dot(segment,segment);if(l2>(is_target()?1e-12:1e-6))closest+=segment*clamp(dot(pos-a,segment)/l2,0.0,1.0);
  float distance=length(pos-closest),radius=cf(UE_C_RADIUS_M_WORD),weight=0.0;
  if(!is_control()&&!is_stroke())weight=distance<=radius?max(0.001,1.0-distance/radius):0.0;
  float bed_sand=imageLoad(sand0,q).r,old=is_suspended()?imageLoad(sediment0,q).r:bed_sand;vec2 support=imageLoad(support0,q).xy;
  if(is_suspended()&&(imageLoad(water,q).r<=cf(UE_C_DRY_DEPTH_M_WORD)||imageLoad(obstacle,q).r>=0.5))weight=0.0;
  v[k+UE_CELL_OLD_VALUE]=floatBitsToUint(old);v[k+UE_CELL_NEW_VALUE]=floatBitsToUint(old);
  v[k+UE_CELL_ROCK]=floatBitsToUint(imageLoad(rock,q).r);v[k+UE_CELL_WATER]=floatBitsToUint(imageLoad(water,q).r);
  v[k+UE_CELL_OLD_COMPACTION]=floatBitsToUint(imageLoad(compact,q).r);v[k+UE_CELL_NEW_COMPACTION]=v[k+UE_CELL_OLD_COMPACTION];
  v[k+UE_CELL_OLD_TAG]=floatBitsToUint(support.x);v[k+UE_CELL_OLD_REFERENCE]=floatBitsToUint(support.y);
  v[k+UE_CELL_NEW_TAG]=v[k+UE_CELL_OLD_TAG];v[k+UE_CELL_NEW_REFERENCE]=v[k+UE_CELL_OLD_REFERENCE];
  v[k+UE_CELL_WEIGHT]=floatBitsToUint(weight);v[k+UE_CELL_FLAGS]=weight>0.0?UE_FLAG_TOUCHED:0u;
  if(!finite_value(old)||old<0.0||!finite_value(support.x)||!finite_value(support.y)||support.x<0.0||support.x>bed_sand||(support.x>0.0?support.y!=bed_sand:support.y!=0.0))v[k+UE_CELL_FLAGS]|=UE_FLAG_INVALID_VALUE;
  if(!finite_value(vf(k,UE_CELL_OLD_COMPACTION))||vf(k,UE_CELL_OLD_COMPACTION)<0.0||vf(k,UE_CELL_OLD_COMPACTION)>1.0)v[k+UE_CELL_FLAGS]|=UE_FLAG_INVALID_VALUE;
  float r=vf(k,UE_CELL_ROCK),bed=r+bed_sand;
  if(is_suspended()&&(!finite_value(vf(k,UE_CELL_WATER))||vf(k,UE_CELL_WATER)<0.0))v[k+UE_CELL_FLAGS]|=UE_FLAG_INVALID_VALUE;
  if(!finite_value(r)||!finite_value(bed))v[k+UE_CELL_FLAGS]|=UE_FLAG_INVALID_VALUE;
  if(c[UE_C_CONTROL_KIND_WORD]==UE_CONTROL_BEGIN){v[k+UE_CELL_BASELINE]=floatBitsToUint(bed);return;}
  if(is_transfer()){
   float base=imageLoad(baseline,q).r,target=bed,next=old;vec2 previous=imageLoad(coverage,q).xy,cv=previous;uint flags=0u;
   if(l2>1e-12){
    // Canonical endpoint order fixes geometry; side ownership retains the
    // original directed segment and precise zero-side tie.
    bool reverse=a.x>b.x||(a.x==b.x&&a.y>b.y);vec2 ga=reverse?b:a,gb=reverse?a:b,gab=gb-ga;
    vec2 near=ga+gab*clamp(dot(pos-ga,gab)/dot(gab,gab),0.0,1.0),delta=pos-near;
    float dist=length(delta),inner=cf(UE_C_TRENCH_WIDTH_M_WORD)*0.5,shoulder=cf(UE_C_SHOULDER_WIDTH_M_WORD);
    precise float cross_x=(pos.x-a.x)*segment.y;precise float cross_z=(pos.y-a.y)*segment.x;precise float side=cross_z-cross_x;
    if(dist<inner){
     float profile=max(0.0,1.0-dist*dist/(inner*inner));target=max(r,base-cf(UE_C_DEPTH_M_WORD)*profile);
     if(previous.y>0.0)target=max(r,profile<=previous.y?previous.x:min(target,previous.x));
     next=min(old,max(0.0,target-r));flags=UE_FLAG_TOUCHED|UE_FLAG_DONOR;weight=1.0;cv=vec2(target,max(profile,previous.y));
    }else if(dist<inner+shoulder&&previous.y==0.0&&imageLoad(obstacle,q).r==0.0){
     target=base+cf(UE_C_RIDGE_HEIGHT_M_WORD);weight=sin(3.141592653589793*(dist-inner)/shoulder);
     if(weight>0.0)flags=UE_FLAG_TOUCHED|(side>=0.0?UE_FLAG_LEFT:UE_FLAG_RIGHT);
    }
    vec2 outward=dist>0.0?delta/dist:vec2(0);v[k+UE_CELL_DIRECTION_X]=floatBitsToUint(outward.x);v[k+UE_CELL_DIRECTION_Z]=floatBitsToUint(outward.y);
   }
   v[k+UE_CELL_BASELINE]=floatBitsToUint(base);v[k+UE_CELL_TARGET_HEIGHT]=floatBitsToUint(target);v[k+UE_CELL_NEW_VALUE]=floatBitsToUint(next);
   v[k+UE_CELL_WEIGHT]=floatBitsToUint(weight);v[k+UE_CELL_FLAGS]|=flags;
   if(flags!=0u&&imageLoad(obstacle,q).r>0.0)v[k+UE_CELL_FLAGS]|=UE_FLAG_OBSTACLE;
   if(!finite_value(base)||!finite_value(target)||!finite_value(next)||next<0.0)v[k+UE_CELL_FLAGS]|=UE_FLAG_INVALID_VALUE;
   imageStore(candidate_coverage,q,vec4(cv,0,0));return;
  }
  if(is_target()){
   float base=imageLoad(baseline,q).r,target=bed,next=old;vec2 previous=imageLoad(coverage,q).xy,cv=previous,outward=vec2(0);bool touched=false;
   if(c[UE_C_SHAPE_WORD]==UE_SHAPE_HEIGHT_STAMP){
    vec3 sample_value=stamp(vec2(q));
    if(sample_value.y>=0.5&&imageLoad(obstacle,q).r<=0.0){target=sample_value.x;next=max(old,target-r);touched=true;cv=vec2(target,1.0);}
    vec2 downhill=vec2(stamp(vec2(q)-vec2(1,0)).x-stamp(vec2(q)+vec2(1,0)).x,stamp(vec2(q)-vec2(0,1)).x-stamp(vec2(q)+vec2(0,1)).x);
    outward=length(downhill)>0.0?normalize(downhill):vec2(0);
   }else{
    float inner=cf(UE_C_TOP_WIDTH_M_WORD)*0.5,outer=cf(UE_C_BOTTOM_WIDTH_M_WORD)*0.5;
    float profile=distance<=inner?1.0:(distance<outer?(outer-distance)/max(outer-inner,1e-8):0.0);
    bool hit=dot(segment,segment)>1e-12&&profile>0.0;
    outward=distance>0.0?(pos-closest)/distance:vec2(0);
    if(l2>1e-12&&(hit||previous.y>0.0)){target=hit?base+cf(UE_C_HEIGHT_M_WORD)*profile:previous.x;if(previous.y>0.0)target=max(target,previous.x);next=max(old,target-r);touched=true;cv=vec2(target,1.0);}
   }
   v[k+UE_CELL_NEW_VALUE]=floatBitsToUint(next);
   v[k+UE_CELL_BASELINE]=floatBitsToUint(base);v[k+UE_CELL_TARGET_HEIGHT]=floatBitsToUint(target);v[k+UE_CELL_WEIGHT]=floatBitsToUint(touched?1.0:0.0);
   v[k+UE_CELL_DIRECTION_X]=floatBitsToUint(outward.x);v[k+UE_CELL_DIRECTION_Z]=floatBitsToUint(outward.y);
   if(touched)v[k+UE_CELL_FLAGS]|=UE_FLAG_TOUCHED;
   if(touched&&imageLoad(obstacle,q).r>0.0)v[k+UE_CELL_FLAGS]|=UE_FLAG_OBSTACLE;
   if(!finite_value(base)||!finite_value(target)||!finite_value(next)||next<0.0)v[k+UE_CELL_FLAGS]|=UE_FLAG_INVALID_VALUE;
   imageStore(candidate_coverage,q,vec4(cv,0,0));
  }
  return;
 }
 if(p.mode==9u){
  if(!is_transfer())return;
  const float sentinel=3.402823466e38;
  vec4 entry=vec4(sentinel,0,0,float(l));uint side=0u;
  if(lane<count){
   uint flags=v[k+UE_CELL_FLAGS];float cap=capacity(k),w=vf(k,UE_CELL_WEIGHT);
   side=(flags&UE_FLAG_LEFT)!=0u?1u:((flags&UE_FLAG_RIGHT)!=0u?2u:0u);
   if(side!=0u&&cap>0.0&&w>0.0)entry=vec4(min(sentinel,cap/w),cap,w,float(l));
  }
  sorted_left[l]=side==1u?entry:vec4(sentinel,0,0,float(l));sorted_right[l]=side==2u?entry:vec4(sentinel,0,0,float(l));barrier();
  for(uint size=2u;size<=256u;size*=2u)for(uint stride=size/2u;stride>0u;stride/=2u){
   uint other=l^stride;vec4 a=sorted_left[l],b=sorted_left[other],ar=sorted_right[l],br=sorted_right[other];
   bool gt=a.x>b.x||(a.x==b.x&&a.w>b.w),gtr=ar.x>br.x||(ar.x==br.x&&ar.w>br.w),lower=((l&size)==0u)==((l&stride)==0u);barrier();
   sorted_left[l]=lower?(gt?b:a):(gt?a:b);sorted_right[l]=lower?(gtr?br:ar):(gtr?ar:br);barrier();
  }
  if(l==0u){
   vec2 cap=vec2(0),weight=vec2(0),cc=vec2(0),cw=vec2(0);
   for(uint j=0u;j<256u;j++){
    vec4 a=sorted_left[j],b=sorted_right[j];compensated_add(a.y,cap.x,cc.x);compensated_add(a.z,weight.x,cw.x);compensated_add(b.y,cap.y,cc.y);compensated_add(b.z,weight.y,cw.y);
    transfer_prefix[(gl_WorkGroupID.x*2u)*256u+j]=vec4(a.x,cap.x,weight.x,0);transfer_prefix[(gl_WorkGroupID.x*2u+1u)*256u+j]=vec4(b.x,cap.y,weight.y,0);
   }
  }return;
 }
 if(p.mode==10u){
  if(!is_transfer()||lane!=0u)return;
  // No donor mass means exactly no receiver proposal. A finite bisection
  // upper bound would otherwise leave a tiny positive lambda at target zero.
  if(tx[4]<=0.0){tx[7]=0.0;tx[8]=0.0;return;}
  for(uint side=0u;side<2u;side++){
   float lo=0.0,hi=0.0;
   for(uint group=0u;group<p.groups;group++){
    uint base=(group*2u+side)*256u,lower=0u,upper=256u;
    while(lower<upper){uint mid=(lower+upper)/2u;if(transfer_prefix[base+mid].x<3.402823466e38)lower=mid+1u;else upper=mid;}
    if(lower>0u)hi=max(hi,transfer_prefix[base+lower-1u].x);
   }
   for(uint iteration=0u;iteration<48u;iteration++){
    float previous_lo=lo,previous_hi=hi,middle=lo+(hi-lo)*0.5;
    if(allocated(middle,side)<tx[4]*0.5)lo=middle;else hi=middle;
    if(previous_lo==lo&&previous_hi==hi)break;
   }
   tx[7u+side]=lo+(hi-lo)*0.5;
  }return;
 }
 if(p.mode==11u){
  if(!is_transfer()||lane!=0u)return;
  // Keep the frozen two row-major, at-most-one-ULP corrections per receiver.
  // Both sides are independent, so one range walk services both.
  for(uint round=0u;round<2u;round++){
   vec2 sum=vec2(0),corr=vec2(0);
   for(uint j=0u;j<count;j++){
    uint at=cell_index(j)*UE_CELL_WORD_COUNT,flags=v[at+UE_CELL_FLAGS];
    if((flags&UE_FLAG_LEFT)!=0u)compensated_add(vf(at,UE_CELL_NEW_VALUE)-vf(at,UE_CELL_OLD_VALUE),sum.x,corr.x);
    if((flags&UE_FLAG_RIGHT)!=0u)compensated_add(vf(at,UE_CELL_NEW_VALUE)-vf(at,UE_CELL_OLD_VALUE),sum.y,corr.y);
   }
   vec2 residue=vec2(tx[4]*0.5)-sum;
   for(uint j=0u;j<count;j++){
    uint at=cell_index(j)*UE_CELL_WORD_COUNT,flags=v[at+UE_CELL_FLAGS];if((flags&(UE_FLAG_LEFT|UE_FLAG_RIGHT))==0u)continue;
    uint side=(flags&UE_FLAG_LEFT)!=0u?0u:1u;float old=vf(at,UE_CELL_OLD_VALUE),next=vf(at,UE_CELL_NEW_VALUE),step=ulp(next);
    float corrected=clamp(next+clamp(residue[side],-step,step),old,old+capacity(at));v[at+UE_CELL_NEW_VALUE]=floatBitsToUint(corrected);residue[side]-=corrected-next;
   }
  }return;
 }
 if(p.mode==12u){
  if(is_control()||is_suspended()||lane>=count||vf(k,UE_CELL_WEIGHT)<=0.0||is_adjust())return;
  float old=vf(k,UE_CELL_OLD_VALUE),next=vf(k,UE_CELL_NEW_VALUE),delta=next-old;
  float tag=max(vf(k,UE_CELL_OLD_TAG)-max(-delta,0.0),0.0),comp=vf(k,UE_CELL_OLD_COMPACTION);
  if(is_transfer()&&delta>0.0){
   if(!finite_value(tx[4])||!finite_value(tx[5])||!finite_value(tx[6])||tx[4]<=0.0||tx[5]<0.0||tx[5]>tx[4]||tx[6]<0.0||tx[6]>1.0){v[k+UE_CELL_FLAGS]|=UE_FLAG_INVALID_VALUE;return;}
   tag+=delta*tx[5]/tx[4];comp=clamp((old*comp+delta*tx[6])/next,0.0,1.0);
  }else if(c[UE_C_MATERIAL_POLICY_WORD]==UE_MATERIAL_MOLDED&&delta>0.0){tag+=delta;comp=max(comp,0.9501953125);}
  tag=clamp(tag,0.0,max(next,0.0));v[k+UE_CELL_NEW_TAG]=floatBitsToUint(tag);v[k+UE_CELL_NEW_REFERENCE]=floatBitsToUint(tag>0.0?next:0.0);
  imageStore(candidate_compaction,q,vec4(comp));return;
 }
 if(p.mode==4u){
  if(is_control()||is_target())return;
  if(lane>=count)return;
  float weight=vf(k,UE_CELL_WEIGHT),old=vf(k,UE_CELL_OLD_VALUE),next=vf(k,UE_CELL_NEW_VALUE);step_amount[i]=0.0;
  if(weight<=0.0)return;
  if(is_transfer()){
   uint flags=v[k+UE_CELL_FLAGS];
   if(p.reserved==0u){if((flags&UE_FLAG_DONOR)!=0u)v[k+UE_CELL_NEW_VALUE]=floatBitsToUint(max(0.0,old-max(0.0,old-next)*tx[3]));return;}
   if(p.reserved==1u){if((flags&(UE_FLAG_LEFT|UE_FLAG_RIGHT))!=0u)v[k+UE_CELL_NEW_VALUE]=floatBitsToUint(min(old+capacity(k),old+min(capacity(k),tx[(flags&UE_FLAG_LEFT)!=0u?7:8]*weight)));return;}
   if((flags&UE_FLAG_DONOR)!=0u){vec2 cv=imageLoad(candidate_coverage,q).xy;cv.x=max(cv.x,next+vf(k,UE_CELL_ROCK));imageStore(candidate_coverage,q,vec4(cv,0,0));}
   return;
  }
  if(is_adjust()){
   float value=clamp(vf(k,UE_CELL_OLD_COMPACTION)+0.2*cf(UE_C_STRENGTH_WORD)*weight,0.0,1.0);
   // Quantize through the same native image format as the authority. The next
   // dispatch reads this private image before reduction/validation; no physical
   // field changes until the common conditional commit.
   imageStore(candidate_compaction,q,vec4(value));
   return;
  }
  if(is_smooth()){
   next=p.reserved==0u?mix(old,uintBitsToFloat(d[3]),cf(UE_C_STRENGTH_WORD)*weight):max(0.0,next+uintBitsToFloat(d[6]));
  }else if(c[UE_C_VOLUME_SIGN_WORD]==UE_SIGN_ADD){
   float amount=uintBitsToFloat(d[0])*weight/uintBitsToFloat(d[2]);next=old+amount/area;step_amount[i]=amount;
  }else if(uintBitsToFloat(d[1])>eps&&uintBitsToFloat(d[3])>eps){
   float take=min(next*area,uintBitsToFloat(d[1])*weight/uintBitsToFloat(d[3]));next-=take/area;step_amount[i]=take;
  }
  v[k+UE_CELL_NEW_VALUE]=floatBitsToUint(next);
  if(is_suspended())return;
  return;
 }
 if(p.mode==7u){
  if(lane>=count)return;
  if(is_control()){
   if(c[UE_C_CONTROL_KIND_WORD]==UE_CONTROL_BEGIN){imageStore(baseline,q,vec4(vf(k,UE_CELL_BASELINE)));imageStore(coverage,q,vec4(0));}
   return;
  }
  if(is_stroke()&&d[14]!=0u)imageStore(coverage,q,imageLoad(candidate_coverage,q));
  if(d[9]==0u)return;
  if(!physical_changed(k))return;
  if(is_suspended()){imageStore(sediment0,q,vec4(vf(k,UE_CELL_NEW_VALUE)));imageStore(sediment1,q,vec4(vf(k,UE_CELL_NEW_VALUE)));return;}
  if(v[k+UE_CELL_OLD_VALUE]!=v[k+UE_CELL_NEW_VALUE]){float next=vf(k,UE_CELL_NEW_VALUE);imageStore(sand0,q,vec4(next));imageStore(sand1,q,vec4(next));}
  if(v[k+UE_CELL_NEW_TAG]!=v[k+UE_CELL_OLD_TAG]||v[k+UE_CELL_NEW_REFERENCE]!=v[k+UE_CELL_OLD_REFERENCE]){vec4 tag=vec4(vf(k,UE_CELL_NEW_TAG),vf(k,UE_CELL_NEW_REFERENCE),0,0);imageStore(support0,q,tag);imageStore(support1,q,tag);}
  if(v[k+UE_CELL_NEW_COMPACTION]!=v[k+UE_CELL_OLD_COMPACTION]){imageStore(compact,q,vec4(vf(k,UE_CELL_NEW_COMPACTION)));imageStore(compact1,q,vec4(vf(k,UE_CELL_NEW_COMPACTION)));}
  return;
 }
 if(p.mode==2u||p.mode==5u){
  values[l]=vec4(0);extras[l]=vec2(0);received[l]=vec2(0);meta[l]=uvec4(0);bounds[l]=ivec4(256,256,-1,-1);changed_fields[l]=0u;coverage_changes[l]=0u;
  if(lane<count){
   float w=vf(k,UE_CELL_WEIGHT),old=vf(k,UE_CELL_OLD_VALUE),next=vf(k,UE_CELL_NEW_VALUE);uint flags=v[k+UE_CELL_FLAGS]&~(UE_FLAG_TOUCHED|UE_FLAG_DONOR|UE_FLAG_LEFT|UE_FLAG_RIGHT);
   if(p.mode==5u&&!is_suspended()&&w>0.0)v[k+UE_CELL_NEW_COMPACTION]=floatBitsToUint(imageLoad(candidate_compaction,q).r);
   if(p.mode==2u){
    if(is_transfer()){
     uint bits=v[k+UE_CELL_FLAGS];float moved=(bits&UE_FLAG_DONOR)!=0u?max(0.0,old-next):0.0;
     if(p.reserved==0u)values[l]=vec4(moved,(bits&UE_FLAG_LEFT)!=0u?capacity(k):0.0,(bits&UE_FLAG_RIGHT)!=0u?capacity(k):0.0,0);
     else values[l]=vec4(moved,min(max(vf(k,UE_CELL_OLD_TAG),0.0),moved),moved*vf(k,UE_CELL_OLD_COMPACTION),0);
    }else if(is_smooth())values[l]=w<=0.0?vec4(0):(p.reserved==0u?vec4(old*w,w,old,1.0):vec4(next,0,0,0));
    else values[l]=vec4(w,w>0.0&&next*area>eps?w:0.0,w>0.0?step_amount[i]:0.0,0);
    meta[l].w=flags;
   }
   else if(w>0.0){
    float delta=(next-old)*area;
    values[l]=vec4(delta,max(-delta,0.0),2.0*ulp(max(abs(next),abs(old)))*area,abs(delta));extras[l].x=abs(next-old);
    if(is_transfer()){uint bits=v[k+UE_CELL_FLAGS];received[l]=vec2((bits&UE_FLAG_LEFT)!=0u?max(delta,0.0):0.0,(bits&UE_FLAG_RIGHT)!=0u?max(delta,0.0):0.0);}
    meta[l].x=uint(physical_changed(k));meta[l].y=1u;meta[l].w=flags;
    if(!finite_value(next)||next<0.0)meta[l].w|=UE_FLAG_INVALID_VALUE;
    float new_compact=vf(k,UE_CELL_NEW_COMPACTION),new_tag=vf(k,UE_CELL_NEW_TAG),new_ref=vf(k,UE_CELL_NEW_REFERENCE);
    if(!is_suspended()&&(!finite_value(new_compact)||new_compact<0.0||new_compact>1.0||!finite_value(new_tag)||!finite_value(new_ref)||new_tag<0.0||new_tag>next||(new_tag>0.0?new_ref!=next:new_ref!=0.0)))meta[l].w|=UE_FLAG_INVALID_VALUE;
    if(physical_changed(k)){uvec2 dirty=uvec2(0);mark_dirty(dirty,uint(q.x),uint(q.y));meta[l].z=dirty.x;extras[l].y=uintBitsToFloat(dirty.y);bounds[l]=ivec4(q,q);if(next!=old)changed_fields[l]|=is_suspended()?UE_FIELD_SUSPENDED:UE_FIELD_BED;if(material_changed(k))changed_fields[l]|=UE_FIELD_MATERIAL;}
   }
   if(p.mode==5u&&is_stroke())coverage_changes[l]=uint(any(notEqual(imageLoad(coverage,q).xy,imageLoad(candidate_coverage,q).xy)));
  }
  barrier();
  for(uint stride=128u;stride>0u;stride>>=1u){
   if(l<stride){values[l]+=values[l+stride];received[l]+=received[l+stride];changed_fields[l]|=changed_fields[l+stride];coverage_changes[l]|=coverage_changes[l+stride];
    if(p.mode==2u){meta[l].w|=meta[l+stride].w;}
    else{extras[l].x=max(extras[l].x,extras[l+stride].x);extras[l].y=uintBitsToFloat(floatBitsToUint(extras[l].y)|floatBitsToUint(extras[l+stride].y));meta[l].xy+=meta[l+stride].xy;meta[l].zw|=meta[l+stride].zw;bounds[l].xy=min(bounds[l].xy,bounds[l+stride].xy);bounds[l].zw=max(bounds[l].zw,bounds[l+stride].zw);}
   }barrier();
  }
  if(l==0u){uint base=gl_WorkGroupID.x*UE_SUMMARY_WORD_COUNT;for(uint j=0u;j<UE_SUMMARY_WORD_COUNT;j++)s[base+j]=0u;
   if(p.mode==2u){allocation[gl_WorkGroupID.x]=values[0];}
   else{s[base+UE_SUMMARY_NET_VOLUME]=floatBitsToUint(values[0].x);s[base+UE_SUMMARY_REMOVED]=floatBitsToUint(values[0].y);s[base+UE_SUMMARY_SAND_ULP_BUDGET]=floatBitsToUint(values[0].z);s[base+UE_SUMMARY_SAND_ABSOLUTE_DELTA]=floatBitsToUint(values[0].w);s[base+UE_SUMMARY_MAX_DELTA]=floatBitsToUint(extras[0].x);s[base+UE_SUMMARY_CHANGED_CELLS]=meta[0].x;s[base+UE_SUMMARY_TOUCHED_CELLS]=meta[0].y;s[base+UE_SUMMARY_DIRTY_LOW]=meta[0].z;s[base+UE_SUMMARY_DIRTY_HIGH]=floatBitsToUint(extras[0].y);s[base+UE_SUMMARY_RECT_MIN_X]=uint(bounds[0].x);s[base+UE_SUMMARY_RECT_MIN_Z]=uint(bounds[0].y);s[base+UE_SUMMARY_RECT_MAX_X]=uint(bounds[0].z);s[base+UE_SUMMARY_RECT_MAX_Z]=uint(bounds[0].w);}
   s[base+UE_SUMMARY_INVALID_FLAGS]=meta[0].w;s[base+UE_SUMMARY_CHANGED_FIELDS]=changed_fields[0];s[base+UE_SUMMARY_COVERAGE_CHANGED]=coverage_changes[0];
   if(p.mode==5u){s[base+UE_SUMMARY_LEFT_RECEIVED]=floatBitsToUint(received[0].x);s[base+UE_SUMMARY_RIGHT_RECEIVED]=floatBitsToUint(received[0].y);}
  }return;
 }
 if(p.mode==3u||p.mode==6u){
  if(lane!=0u)return;
  uint base=UE_REDUCE_BLOCKS*UE_SUMMARY_WORD_COUNT;
  for(uint j=0u;j<UE_SUMMARY_WORD_COUNT;j++)s[base+j]=0u;
  s[base+UE_SUMMARY_RECT_MIN_X]=256u;s[base+UE_SUMMARY_RECT_MIN_Z]=256u;
  vec4 sum=vec4(0),correction=vec4(0);vec2 side_sum=vec2(0),side_corr=vec2(0);float max_delta=0.0;
  for(uint group=0u;group<p.groups;group++){
   uint b=group*UE_SUMMARY_WORD_COUNT;
   vec4 term=p.mode==3u?allocation[group]:vec4(uintBitsToFloat(s[b+UE_SUMMARY_NET_VOLUME]),uintBitsToFloat(s[b+UE_SUMMARY_REMOVED]),uintBitsToFloat(s[b+UE_SUMMARY_SAND_ULP_BUDGET]),uintBitsToFloat(s[b+UE_SUMMARY_SAND_ABSOLUTE_DELTA]));
   precise vec4 y=term-correction;precise vec4 next=sum+y;correction=(next-sum)-y;sum=next;
   s[base+UE_SUMMARY_INVALID_FLAGS]|=s[b+UE_SUMMARY_INVALID_FLAGS];
   s[base+UE_SUMMARY_CHANGED_FIELDS]|=s[b+UE_SUMMARY_CHANGED_FIELDS];
   s[base+UE_SUMMARY_COVERAGE_CHANGED]|=s[b+UE_SUMMARY_COVERAGE_CHANGED];
   if(p.mode==6u){
    compensated_add(uintBitsToFloat(s[b+UE_SUMMARY_LEFT_RECEIVED]),side_sum.x,side_corr.x);compensated_add(uintBitsToFloat(s[b+UE_SUMMARY_RIGHT_RECEIVED]),side_sum.y,side_corr.y);
    for(uint j=UE_SUMMARY_CHANGED_CELLS;j<=UE_SUMMARY_TOUCHED_CELLS;j++)s[base+j]+=s[b+j];
    s[base+UE_SUMMARY_DIRTY_LOW]|=s[b+UE_SUMMARY_DIRTY_LOW];s[base+UE_SUMMARY_DIRTY_HIGH]|=s[b+UE_SUMMARY_DIRTY_HIGH];
    s[base+UE_SUMMARY_RECT_MIN_X]=min(s[base+UE_SUMMARY_RECT_MIN_X],s[b+UE_SUMMARY_RECT_MIN_X]);s[base+UE_SUMMARY_RECT_MIN_Z]=min(s[base+UE_SUMMARY_RECT_MIN_Z],s[b+UE_SUMMARY_RECT_MIN_Z]);
    if(s[b+UE_SUMMARY_CHANGED_CELLS]>0u){s[base+UE_SUMMARY_RECT_MAX_X]=max(s[base+UE_SUMMARY_RECT_MAX_X],s[b+UE_SUMMARY_RECT_MAX_X]);s[base+UE_SUMMARY_RECT_MAX_Z]=max(s[base+UE_SUMMARY_RECT_MAX_Z],s[b+UE_SUMMARY_RECT_MAX_Z]);}
    max_delta=max(max_delta,uintBitsToFloat(s[b+UE_SUMMARY_MAX_DELTA]));
   }
  }
  if(s[base+UE_SUMMARY_INVALID_FLAGS]!=0u){error((s[base+UE_SUMMARY_INVALID_FLAGS]&UE_FLAG_OBSTACLE)!=0u?UE_ERROR_INVALID_PLACEMENT:UE_ERROR_CANDIDATE_INVALID);return;}
  if(is_control())return;
  if(p.mode==3u){
   if(is_transfer()){
    if(p.reserved==0u){tx[0]=sum.x;tx[1]=sum.y;tx[2]=sum.z;float limit=min(min(sum.x,max(0.0,cf(UE_C_TRANSFER_BUDGET_M3_WORD))/area),2.0*min(sum.y,sum.z));tx[3]=sum.x>0.0?limit/sum.x:0.0;}
    else{tx[4]=sum.x;tx[5]=sum.y;tx[6]=sum.x>0.0?sum.z/sum.x:0.0;}
    return;
   }
   if(is_smooth()){
    if(p.reserved==0u){
     if(sum.y<=1e-7||sum.w<=0.0){error(UE_ERROR_INVALID_PLACEMENT);return;}
     d[2]=floatBitsToUint(sum.y);d[3]=floatBitsToUint(sum.x/sum.y);d[4]=floatBitsToUint(sum.z);d[5]=floatBitsToUint(sum.w);
    }else d[6]=floatBitsToUint((uintBitsToFloat(d[4])-sum.x)/uintBitsToFloat(d[5]));
    return;
   }
   d[2]=floatBitsToUint(sum.x);d[3]=floatBitsToUint(sum.y);
   if(p.reserved!=0u){d[1]=floatBitsToUint(uintBitsToFloat(d[1])-sum.z);d[4]=floatBitsToUint(uintBitsToFloat(d[4])+sum.z);}
   if(sum.x<=0.0&&!is_target())error(is_adjust()?UE_ERROR_INVALID_PLACEMENT:UE_ERROR_OUT_OF_DOMAIN);
  }else{
   float actual=abs(sum.x),nominal=c[UE_C_VOLUME_SIGN_WORD]==UE_SIGN_ADD?uintBitsToFloat(d[0]):uintBitsToFloat(d[4]);
   if(!finite_value(actual)||!finite_value(sum.w)||!finite_value(sum.z)){error(UE_ERROR_CANDIDATE_INVALID);return;}
   float u=5.9604644775390625e-8,budget=max(1e-7,sum.z+max(1e-8,((is_volume()?4.0:8.0)*u+2.0*(float(s[base+UE_SUMMARY_TOUCHED_CELLS])+(is_volume()?0.0:256.0))*u*u)*sum.w));
   if(is_transfer()){
    nominal=0.0;
    if(actual>2.0*budget||abs(sum.y-side_sum.x-side_sum.y)>2.0*budget||abs(side_sum.x-side_sum.y)>2.0*budget){error(UE_ERROR_CANDIDATE_INVALID);return;}
    if(sum.y>cf(UE_C_TRANSFER_BUDGET_M3_WORD)+budget){error(UE_ERROR_BUDGET_EXCEEDED);return;}
    // Existing transfer validation permits 2*eps for net/side balance. Report
    // that actual bound, so the common result codec checks the same bound.
    budget*=2.0;
   }else if(is_target()){
    nominal=actual;
    if(sum.x<0.0||sum.x>cf(UE_C_ADD_BUDGET_M3_WORD)+budget){error(UE_ERROR_BUDGET_EXCEEDED);return;}
   }else if(is_smooth()){
    nominal=0.0;
    if(actual>budget||actual/area>max(1e-5,2e-6*abs(uintBitsToFloat(d[4])))){error(UE_ERROR_CANDIDATE_INVALID);return;}
   }else if(is_adjust()){
    nominal=0.0;budget=0.0;
    if(actual!=0.0||sum.w!=0.0){error(UE_ERROR_CANDIDATE_INVALID);return;}
   }else if(!finite_value(actual)||abs(actual-nominal)>budget||actual>cf(UE_C_AVAILABLE_M3_WORD)+eps){error(UE_ERROR_CANDIDATE_INVALID);return;}
   if(s[base+UE_SUMMARY_CHANGED_CELLS]>0u&&control[10]==0xffffffffu&&control[11]==0x7fffffffu){control[1]|=32u;return;}
   d[9]=s[base+UE_SUMMARY_CHANGED_CELLS];d[10]=floatBitsToUint(is_smooth()||is_transfer()?sum.x:actual-nominal);d[11]=floatBitsToUint(budget);d[12]=s[base+UE_SUMMARY_TOUCHED_CELLS];
   d[14]=s[base+UE_SUMMARY_COVERAGE_CHANGED];
   s[base+UE_SUMMARY_NET_VOLUME]=floatBitsToUint(sum.x);s[base+UE_SUMMARY_REMOVED]=floatBitsToUint(sum.y);s[base+UE_SUMMARY_SAND_ABSOLUTE_DELTA]=floatBitsToUint(sum.w);s[base+UE_SUMMARY_MAX_DELTA]=floatBitsToUint(max_delta);
   s[base+UE_SUMMARY_LEFT_RECEIVED]=floatBitsToUint(side_sum.x);s[base+UE_SUMMARY_RIGHT_RECEIVED]=floatBitsToUint(side_sum.y);
   if(is_suspended()){s[base+UE_SUMMARY_SEDIMENT_ERROR]=d[10];s[base+UE_SUMMARY_SEDIMENT_ULP_BUDGET]=floatBitsToUint(sum.z);s[base+UE_SUMMARY_SEDIMENT_ABSOLUTE_DELTA]=floatBitsToUint(sum.w);s[base+UE_SUMMARY_SEDIMENT_TOUCHED]=s[base+UE_SUMMARY_TOUCHED_CELLS];}
   if(is_transfer()){s[base+UE_SUMMARY_DONOR_MOVED]=floatBitsToUint(tx[4]);s[base+UE_SUMMARY_DONOR_TAGGED]=floatBitsToUint(tx[5]);s[base+UE_SUMMARY_DONOR_COMPACTION_SUM]=floatBitsToUint(tx[4]*tx[6]);s[base+UE_SUMMARY_NOMINAL_CUT]=floatBitsToUint(tx[0]);}
  }return;
 }
}
