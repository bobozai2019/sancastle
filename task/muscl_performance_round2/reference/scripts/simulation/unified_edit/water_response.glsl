#[compute]
#version 450
// UE_LAYOUT
#define GLOBAL_SUMMARY (256u*UE_SUMMARY_WORD_COUNT)
layout(local_size_x=256) in;
layout(set=0,binding=0,std430) readonly buffer Command {uint c[];};
layout(set=0,binding=1,std430) readonly buffer Cells {uint v[];};
layout(set=0,binding=2,std430) buffer Summary {uint s[];};
layout(set=0,binding=3,std430) buffer Decision {uint d[];};
layout(set=0,binding=4,std430) buffer Control {uint control[];};
struct InputCell {vec4 bed_water;vec4 flow;};
layout(set=0,binding=5,std430) buffer Input {InputCell inputs[];};
layout(set=0,binding=6,std430) buffer Candidate {vec4 candidate[];};
layout(set=0,binding=7,std430) buffer Receipt {uint w[];};
layout(set=0,binding=8,std430) buffer Scratch {int scratch[];};
layout(set=0,binding=9,std430) buffer Bridge {uint bridge[];};
layout(set=0,binding=10,r32f) uniform readonly image2D rock;
layout(set=0,binding=11,r32f) uniform readonly image2D sand;
layout(set=0,binding=12,r32f) uniform image2D water0;
layout(set=0,binding=13,r32f) uniform image2D water1;
layout(set=0,binding=14,r32f) uniform image2D sediment0;
layout(set=0,binding=15,r32f) uniform image2D sediment1;
layout(set=0,binding=16,r32f) uniform image2D qx0;
layout(set=0,binding=17,r32f) uniform image2D qx1;
layout(set=0,binding=18,r32f) uniform image2D qz0;
layout(set=0,binding=19,r32f) uniform image2D qz1;
layout(set=0,binding=20,r8) uniform readonly image2D obstacle;
layout(set=0,binding=21,std430) buffer Dispatch {uint groups[];};
layout(push_constant,std430) uniform Params {uint mode,pad0,pad1,pad2;}p;
shared vec4 values[256];
shared vec2 absolute_values[256];
shared uvec4 meta[256];
shared ivec4 bounds[256];
shared uint masks[256];
shared uint invalids[256];
float cf(uint at){return uintBitsToFloat(c[at]);}
float vf(uint k,uint at){return uintBitsToFloat(v[k+at]);}
bool finite_value(float a){return !isnan(a)&&!isinf(a);}
float ulp(float a){uint exponent=(floatBitsToUint(abs(a))>>23u)&255u;return exponent==0u?uintBitsToFloat(1u):exp2(float(int(exponent)-150));}
bool valid_cell(ivec2 q){return c[UE_C_OPERATION_WORD]==UE_OP_TARGET_HEIGHT||(q.x>=int(c[UE_C_RECT_X_WORD])&&q.y>=int(c[UE_C_RECT_Z_WORD])&&q.x<int(c[UE_C_RECT_X_WORD]+c[UE_C_RECT_W_WORD])&&q.y<int(c[UE_C_RECT_Z_WORD]+c[UE_C_RECT_H_WORD]));}
bool material_changed(uint k){return v[k+4u]!=v[k+5u]||v[k+6u]!=v[k+8u]||v[k+7u]!=v[k+9u];}
void mark(inout uvec2 mask,uint x,uint z){
 uint cell=(z/32u)*8u+x/32u;mask[cell/32u]|=1u<<(cell%32u);
 if(x%32u==0u&&x>0u){uint j=cell-1u;mask[j/32u]|=1u<<(j%32u);}
 if(z%32u==0u&&z>0u){uint j=cell-8u;mask[j/32u]|=1u<<(j%32u);}
 if(x%32u==0u&&z%32u==0u&&x>0u&&z>0u){uint j=cell-9u;mask[j/32u]|=1u<<(j%32u);}
}
void main(){
 uint i=gl_GlobalInvocationID.x,l=gl_LocalInvocationID.x,k=i*UE_CELL_WORD_COUNT;ivec2 q=ivec2(i%256u,i/256u);
 if(p.mode!=0u&&(d[8]!=0u||control[1]!=0u))return;
 if(p.mode==0u){
  if(i==0u){for(uint j=0u;j<32u;j++){w[j]=0u;bridge[j]=0u;}bridge[20]=256u;bridge[19]=c[UE_C_CELL_SIZE_M_WORD];bridge[21]=c[UE_C_WATER_POLICY_WORD];for(uint at=0u;at<3u;at++){groups[at*3u]=(d[8]==0u&&control[1]==0u)?1u:0u;groups[at*3u+1u]=1u;groups[at*3u+2u]=1u;}}
  if(d[8]!=0u||control[1]!=0u)return;
  float bed=imageLoad(rock,q).r+imageLoad(sand,q).r,next=bed;
  if(valid_cell(q)&&vf(k,UE_CELL_WEIGHT)>0.0)next=imageLoad(rock,q).r+vf(k,UE_CELL_NEW_VALUE);
  inputs[i].bed_water=vec4(bed,next,imageLoad(water0,q).r,imageLoad(sediment0,q).r);
  inputs[i].flow=vec4(imageLoad(qx0,q).r,imageLoad(qz0,q).r,imageLoad(obstacle,q).r,0);
  return;
 }
 if(p.mode==1u){
  vec4 old=candidate[i];scratch[i]=floatBitsToInt(old.z);scratch[65536u+i]=floatBitsToInt(old.w);scratch[131072u+i]=scratch[i];scratch[196608u+i]=scratch[65536u+i];
  if(w[0]!=1u||c[UE_C_WATER_POLICY_WORD]<2u||cf(UE_C_SPEED_M_S_WORD)==0.0||old.x<=0.001||!valid_cell(q)||vf(k,UE_CELL_WEIGHT)<=0.0)return;
  vec2 dq=vec2(0);
  // B: use the actual accepted bed delta once; water/sediment stay unchanged.
  if(c[UE_C_WATER_POLICY_WORD]==2u){
   float db=inputs[i].bed_water.y-inputs[i].bed_water.x;
   if(db==0.0||inputs[i].flow.z>=0.5)return;
   vec2 point=(vec2(q)+0.5-128.0)*0.125;
   vec2 a=vec2(cf(UE_C_START_X_WORD),cf(UE_C_START_Z_WORD));
   vec2 segment=vec2(cf(UE_C_END_X_WORD),cf(UE_C_END_Z_WORD))-a;
   float len2=dot(segment,segment);
   vec2 radial=point-a-segment*(len2>1e-6?clamp(dot(point-a,segment)/len2,0.0,1.0):0.0);
   float distance=length(radial);
   dq=distance>0.0?old.x*(radial/distance)*cf(UE_C_SPEED_M_S_WORD)*(db/0.2):vec2(0);
  }else if(c[UE_C_OPERATION_WORD]==UE_OP_VOLUME_DELTA){
   if(cf(UE_C_STRENGTH_WORD)==0.0)return;
   vec2 point=(vec2(q)+0.5-128.0)*0.125,a=vec2(cf(UE_C_START_X_WORD),cf(UE_C_START_Z_WORD)),b=vec2(cf(UE_C_END_X_WORD),cf(UE_C_END_Z_WORD)),segment=b-a,radial=point-a;
   float length_squared=dot(segment,segment);
   if(length_squared>1e-6){float t=dot(radial,segment)/length_squared;if(t>=1.0)radial=point-b;else if(t>0.0){float side=radial.x*segment.y-radial.y*segment.x;radial=vec2(segment.y,-segment.x)*sign(side);}}
   float distance=length(radial);vec2 change=distance>0.0?radial/distance*vf(k,UE_CELL_WEIGHT)*cf(UE_C_SPEED_M_S_WORD):vec2(0);dq=old.x*change;
  }else{
   float raised=max(0.0,vf(k,UE_CELL_NEW_VALUE)-vf(k,UE_CELL_OLD_VALUE));if(raised==0.0)return;
   dq=old.x*vec2(vf(k,UE_CELL_DIRECTION_X),vf(k,UE_CELL_DIRECTION_Z))*raised*cf(UE_C_SPEED_M_S_WORD);
  }
  vec2 raw=vec2(dq.x==0.0?old.z:old.z+dq.x,dq.y==0.0?old.w:old.w+dq.y);
  scratch[131072u+i]=floatBitsToInt(raw.x);scratch[196608u+i]=floatBitsToInt(raw.y);
  float speed=length(raw/old.x);if(speed>4.0){raw*=4.0/speed;atomicAdd(w[21],1u);}candidate[i].zw=raw;return;
 }
 if(p.mode==4u){
  if(d[9]==0u)return;
  vec4 value=candidate[i];imageStore(water0,q,vec4(value.x));imageStore(water1,q,vec4(value.x));imageStore(sediment0,q,vec4(value.y));imageStore(sediment1,q,vec4(value.y));
  imageStore(qx0,q,vec4(value.z));imageStore(qx1,q,vec4(value.z));imageStore(qz0,q,vec4(value.w));imageStore(qz1,q,vec4(value.w));return;
 }
 if(p.mode==2u){
  if(w[0]!=1u||w[1]!=0u){if(i==0u)d[8]=UE_ERROR_WATER_CANDIDATE_INVALID;return;}
  vec4 old=vec4(inputs[i].bed_water.zw,inputs[i].flow.xy),next=candidate[i];bool valid=valid_cell(q),bed_touch=valid&&vf(k,UE_CELL_WEIGHT)>0.0;
  bool bed_change=valid&&(v[k]!=v[k+1u]),material_change=valid&&material_changed(k),water_change=any(notEqual(old,next));
  bool changed=bed_change||material_change||water_change,touched=old.x>0.001||water_change||bed_touch;
  float area=0.015625;values[l]=vec4((next.xy-old.xy)*area,touched?2.0*ulp(max(abs(old.x),abs(next.x)))*area:0.0,touched?2.0*ulp(max(abs(old.y),abs(next.y)))*area:0.0);
  absolute_values[l]=touched?abs(next.xy-old.xy)*area:vec2(0);uvec2 dirty=uvec2(0);if(changed)mark(dirty,uint(q.x),uint(q.y));
  meta[l]=uvec4(uint(changed),uint(touched),dirty);bounds[l]=changed?ivec4(q,q):ivec4(256,256,-1,-1);
  masks[l]=(bed_change?UE_FIELD_BED:0u)|(material_change?UE_FIELD_MATERIAL:0u)|(old.x!=next.x?UE_FIELD_WATER:0u)|(old.y!=next.y?UE_FIELD_SUSPENDED:0u)|(any(notEqual(old.zw,next.zw))?UE_FIELD_MOMENTUM:0u);
  invalids[l]=uint(any(isnan(next))||any(isinf(next))||next.x<0.0||next.y<0.0);barrier();
  for(uint stride=128u;stride>0u;stride>>=1u){if(l<stride){values[l]+=values[l+stride];absolute_values[l]+=absolute_values[l+stride];meta[l].xy+=meta[l+stride].xy;meta[l].zw|=meta[l+stride].zw;bounds[l].xy=min(bounds[l].xy,bounds[l+stride].xy);bounds[l].zw=max(bounds[l].zw,bounds[l+stride].zw);masks[l]|=masks[l+stride];invalids[l]|=invalids[l+stride];}barrier();}
  if(l==0u){uint base=gl_WorkGroupID.x*UE_SUMMARY_WORD_COUNT;for(uint j=0u;j<UE_SUMMARY_WORD_COUNT;j++)s[base+j]=0u;
   s[base+UE_SUMMARY_WATER_ERROR]=floatBitsToUint(values[0].x);s[base+UE_SUMMARY_SEDIMENT_ERROR]=floatBitsToUint(values[0].y);s[base+UE_SUMMARY_WATER_ULP_BUDGET]=floatBitsToUint(values[0].z);s[base+UE_SUMMARY_SEDIMENT_ULP_BUDGET]=floatBitsToUint(values[0].w);s[base+UE_SUMMARY_WATER_ABSOLUTE_DELTA]=floatBitsToUint(absolute_values[0].x);s[base+UE_SUMMARY_SEDIMENT_ABSOLUTE_DELTA]=floatBitsToUint(absolute_values[0].y);
   s[base+UE_SUMMARY_CHANGED_CELLS]=meta[0].x;s[base+UE_SUMMARY_WATER_TOUCHED]=meta[0].y;s[base+UE_SUMMARY_DIRTY_LOW]=meta[0].z;s[base+UE_SUMMARY_DIRTY_HIGH]=meta[0].w;s[base+UE_SUMMARY_RECT_MIN_X]=uint(bounds[0].x);s[base+UE_SUMMARY_RECT_MIN_Z]=uint(bounds[0].y);s[base+UE_SUMMARY_RECT_MAX_X]=uint(bounds[0].z);s[base+UE_SUMMARY_RECT_MAX_Z]=uint(bounds[0].w);s[base+UE_SUMMARY_CHANGED_FIELDS]=masks[0];s[base+UE_SUMMARY_INVALID_FLAGS]=invalids[0];
  }return;
 }
 if(p.mode==3u){
  if(i!=0u)return;
  vec4 sum=vec4(0),corr=vec4(0);vec2 absolute_sum=vec2(0),ac=vec2(0);uint changed=0u,touched=0u,fields=0u,bad=0u;uvec2 dirty=uvec2(0);uvec4 rect=uvec4(256,256,0,0);
  for(uint group=0u;group<256u;group++){uint base=group*UE_SUMMARY_WORD_COUNT;
   vec4 term=vec4(uintBitsToFloat(s[base+UE_SUMMARY_WATER_ERROR]),uintBitsToFloat(s[base+UE_SUMMARY_SEDIMENT_ERROR]),uintBitsToFloat(s[base+UE_SUMMARY_WATER_ULP_BUDGET]),uintBitsToFloat(s[base+UE_SUMMARY_SEDIMENT_ULP_BUDGET]));precise vec4 y=term-corr;precise vec4 next=sum+y;corr=(next-sum)-y;sum=next;
   vec2 av=vec2(uintBitsToFloat(s[base+UE_SUMMARY_WATER_ABSOLUTE_DELTA]),uintBitsToFloat(s[base+UE_SUMMARY_SEDIMENT_ABSOLUTE_DELTA]));precise vec2 ay=av-ac;precise vec2 an=absolute_sum+ay;ac=(an-absolute_sum)-ay;absolute_sum=an;
   changed+=s[base+UE_SUMMARY_CHANGED_CELLS];touched+=s[base+UE_SUMMARY_WATER_TOUCHED];fields|=s[base+UE_SUMMARY_CHANGED_FIELDS];bad|=s[base+UE_SUMMARY_INVALID_FLAGS];dirty|=uvec2(s[base+UE_SUMMARY_DIRTY_LOW],s[base+UE_SUMMARY_DIRTY_HIGH]);
   rect.xy=min(rect.xy,uvec2(s[base+UE_SUMMARY_RECT_MIN_X],s[base+UE_SUMMARY_RECT_MIN_Z]));if(s[base+UE_SUMMARY_CHANGED_CELLS]>0u)rect.zw=max(rect.zw,uvec2(s[base+UE_SUMMARY_RECT_MAX_X],s[base+UE_SUMMARY_RECT_MAX_Z]));
  }
  float u=5.9604644775390625e-8;vec2 eps=max(vec2(1e-7),sum.zw+max(vec2(1e-8),(8.0*u+2.0*(float(touched)+256.0)*u*u)*absolute_sum));
  float moved=uintBitsToFloat(w[4]),retained=uintBitsToFloat(w[5]);
  if(bad!=0u||any(isnan(sum))||any(isinf(sum))||any(greaterThan(abs(sum.xy),eps))||!finite_value(moved)||!finite_value(retained)||moved<0.0||retained<0.0){d[8]=UE_ERROR_WATER_CANDIDATE_INVALID;return;}
  if(changed>0u&&control[10]==0xffffffffu&&control[11]==0x7fffffffu){control[1]|=32u;return;}
  d[9]=changed;d[12]=touched;d[16]=floatBitsToUint(sum.x);d[17]=floatBitsToUint(eps.x);d[18]=floatBitsToUint(sum.y);d[19]=floatBitsToUint(eps.y);d[20]=w[17];d[21]=w[18];d[22]=w[4];d[23]=w[5];
  uint base=GLOBAL_SUMMARY;s[base+UE_SUMMARY_CHANGED_CELLS]=changed;s[base+UE_SUMMARY_WATER_TOUCHED]=touched;s[base+UE_SUMMARY_CHANGED_FIELDS]=fields;s[base+UE_SUMMARY_DIRTY_LOW]=dirty.x;s[base+UE_SUMMARY_DIRTY_HIGH]=dirty.y;s[base+UE_SUMMARY_RECT_MIN_X]=rect.x;s[base+UE_SUMMARY_RECT_MIN_Z]=rect.y;s[base+UE_SUMMARY_RECT_MAX_X]=rect.z;s[base+UE_SUMMARY_RECT_MAX_Z]=rect.w;
  s[base+UE_SUMMARY_WATER_ERROR]=d[16];s[base+UE_SUMMARY_WATER_ULP_BUDGET]=floatBitsToUint(sum.z);s[base+UE_SUMMARY_WATER_ABSOLUTE_DELTA]=floatBitsToUint(absolute_sum.x);s[base+UE_SUMMARY_SEDIMENT_ERROR]=d[18];s[base+UE_SUMMARY_SEDIMENT_ULP_BUDGET]=floatBitsToUint(sum.w);s[base+UE_SUMMARY_SEDIMENT_ABSOLUTE_DELTA]=floatBitsToUint(absolute_sum.y);
 }
}
