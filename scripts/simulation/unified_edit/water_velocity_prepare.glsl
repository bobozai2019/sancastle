#[compute]
#version 450
// Velocity-only candidate preparation. No connectivity or authority writes.
// Two GPU dispatches separate per-cell work from the final receipt decision.
layout(local_size_x=256) in;
layout(constant_id=0) const uint MODE=0u;
struct InputCell {vec4 bed_water;vec4 flow;};
layout(set=0,binding=0,std430) readonly buffer Input {InputCell inputs[];};
layout(set=0,binding=1,std430) buffer Candidate {vec4 candidate[];};
layout(set=0,binding=2,std430) buffer Scratch {int scratch[];};
layout(set=0,binding=3,std430) buffer Receipt {uint receipt[];};
layout(set=0,binding=4,std430) buffer Checks {uvec2 checks[];};
layout(set=0,binding=5,std430) readonly buffer Decision {uint decision[];};
layout(set=0,binding=6,std430) readonly buffer Control {uint control[];};
shared uvec2 first_error[256];
shared uint enabled;

void main(){
 uint i=gl_GlobalInvocationID.x,l=gl_LocalInvocationID.x;
 // Publish the decision once per group before any group-wide reductions.
 if(l==0u)enabled=(decision[8]==0u&&control[1]==0u)?1u:0u;
 barrier();
 if(enabled==0u)return;
 if(MODE==0u){
  vec4 v=inputs[i].bed_water,f=inputs[i].flow;
  candidate[i]=vec4(v.zw,f.xy);
  scratch[i]=-1;scratch[131072u+i]=-1;scratch[196608u+i]=-1;scratch[262144u+i]=-1;
  // Match the legacy first invalid cell, including finite-before-negative
  // precedence and the deliberately unused flow.w component.
  uint error=(any(isnan(v))||any(isinf(v))||any(isnan(f.xyz))||any(isinf(f.xyz)))?1u:((v.z<0.0||v.w<0.0)?2u:0u);
  first_error[l]=uvec2(error==0u?0xffffffffu:i,error);
 }else{
  first_error[l]=checks[l];
 }
 barrier();
 for(uint stride=128u;stride>0u;stride>>=1u){
  if(l<stride&&first_error[l+stride].x<first_error[l].x)first_error[l]=first_error[l+stride];
  barrier();
 }
 if(MODE==0u){
  if(l==0u)checks[gl_WorkGroupID.x]=first_error[0];
 }else if(l<32u){
  uint error=first_error[0].y;
  receipt[l]=l==0u?(error==0u?1u:2u):(l==1u?error:0u);
 }
}
