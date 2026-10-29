#[compute]
#version 450
// UE_LAYOUT
layout(local_size_x=256) in;
layout(set=0,binding=0,std430) readonly buffer Command {uint c[];};
layout(set=0,binding=1,std430) readonly buffer Stamp {uint stamp[];};
layout(set=0,binding=2,std430) readonly buffer Templates {uint templates[];};
layout(set=0,binding=3,std430) buffer Blocks {uint blocks[];};
layout(set=0,binding=4,std430) buffer Result {uint result[];};
layout(set=0,binding=5,std430) readonly buffer Identity {uint identity[];};
layout(set=0,binding=6,r32f) uniform readonly image2D rock;
layout(set=0,binding=7,r32f) uniform readonly image2D sand;
layout(set=0,binding=8,r32f) uniform readonly image2D water;
layout(set=0,binding=9,r8) uniform readonly image2D obstacle;
layout(set=0,binding=10,r32f) uniform readonly image2D baseline;
layout(set=0,binding=11,std430) readonly buffer Stroke {uint stroke[];};
layout(set=0,binding=12,r32f) uniform readonly image2D clock_value;
layout(push_constant,std430) uniform Params {uint mode,pad0,pad1,pad2;}p;
shared vec4 amounts[256];shared uvec2 counts[256];shared uint flags[256];
float cf(uint k){return uintBitsToFloat(c[k]);}
bool finite_value(float v){return !isnan(v)&&!isinf(v);}
bool footprint(vec2 world){
 vec2 a=vec2(cf(UE_C_START_X_WORD),cf(UE_C_START_Z_WORD)),b=vec2(cf(UE_C_END_X_WORD),cf(UE_C_END_Z_WORD));
 if(c[UE_C_SHAPE_WORD]==UE_SHAPE_HEIGHT_STAMP){
  float co=cos(cf(UE_C_YAW_RAD_WORD)),si=sin(cf(UE_C_YAW_RAD_WORD));vec2 d=world-a;
  vec2 local=vec2(co*d.x+si*d.y,-si*d.x+co*d.y)/cf(UE_C_SCALE_XZ_WORD);
  if(any(lessThan(local,vec2(-2)))||any(greaterThan(local,vec2(2))))return false;
  uint index=c[UE_C_TEMPLATE_INDEX_WORD];if(index==0u||index>templates[0])return false;
  ivec2 texel=ivec2(floor((local+2.0)/cf(UE_C_TEMPLATE_SPACING_M_WORD)+0.5));
  uint base=4u+(index-1u)*(4u+65u*65u*4u)+4u+uint(texel.y*65+texel.x)*4u;
  return uintBitsToFloat(templates[base+1u])>=0.5;
 }
 vec2 segment=b-a;float l2=dot(segment,segment);vec2 near=a+(l2>0.0?clamp(dot(world-a,segment)/l2,0.0,1.0):0.0)*segment;
 float radius=cf(UE_C_RADIUS_M_WORD);
 if(c[UE_C_OPERATION_WORD]==UE_OP_TARGET_HEIGHT)radius=0.5*cf(UE_C_BOTTOM_WIDTH_M_WORD);
 if(c[UE_C_OPERATION_WORD]==UE_OP_TRANSFER)radius=0.5*cf(UE_C_TRENCH_WIDTH_M_WORD)+cf(UE_C_SHOULDER_WIDTH_M_WORD);
 return radius>0.0&&distance(world,near)<=radius;
}
void main(){
 uint i=gl_GlobalInvocationID.x,l=gl_LocalInvocationID.x;
 if(p.mode==0u){
  ivec2 q=ivec2(i%256u,i/256u);bool inside=footprint((vec2(q)+0.5-128.0)*0.125);
  float s=imageLoad(sand,q).r,h=imageLoad(water,q).r,bed=imageLoad(rock,q).r+s;
  amounts[l]=inside?vec4(bed,bed,h,0):vec4(3.402823466e38,-3.402823466e38,0,0);
  counts[l]=uvec2(uint(inside),uint(inside&&imageLoad(obstacle,q).r>=0.5));
  flags[l]=inside&&(!finite_value(s)||!finite_value(h)||!finite_value(bed)||s<0.0||h<0.0)?256u:0u;barrier();
  for(uint step=128u;step>0u;step>>=1u){if(l<step){amounts[l].x=min(amounts[l].x,amounts[l+step].x);amounts[l].yz=max(amounts[l].yz,amounts[l+step].yz);counts[l]+=counts[l+step];flags[l]|=flags[l+step];}barrier();}
  if(l==0u){uint b=gl_WorkGroupID.x*8u;blocks[b]=floatBitsToUint(amounts[0].x);blocks[b+1u]=floatBitsToUint(amounts[0].y);blocks[b+2u]=floatBitsToUint(amounts[0].z);blocks[b+3u]=counts[0].x;blocks[b+4u]=counts[0].y;blocks[b+5u]=flags[0];}return;
 }
 if(i!=0u)return;
 for(uint j=0u;j<24u;j++)result[j]=0u;
 result[0]=1u;result[2]=identity[2];result[3]=identity[3];for(uint j=0u;j<8u;j++)result[4u+j]=stamp[j];
 float low=3.402823466e38,high=-3.402823466e38,h=0;uint count=0u,obs=0u,bad=0u;
 for(uint j=0u;j<256u;j++){uint b=j*8u;low=min(low,uintBitsToFloat(blocks[b]));high=max(high,uintBitsToFloat(blocks[b+1u]));h=max(h,uintBitsToFloat(blocks[b+2u]));count+=blocks[b+3u];obs+=blocks[b+4u];bad|=blocks[b+5u];}
 if(identity[0]!=stamp[0]||identity[1]!=stamp[1])bad|=2u;
 if(count==0u){bad|=4096u;low=0.0;high=0.0;}
 bool using_baseline=c[UE_C_HEIGHT_REFERENCE_WORD]==UE_HEIGHT_STROKE_BASELINE&&stroke[0]==1u&&all(equal(uvec2(stroke[2],stroke[3]),uvec2(c[UE_C_STROKE_ID_WORD],c[UE_C_STROKE_ID_WORD+1u])))&&all(equal(uvec2(stroke[4],stroke[5]),uvec2(c[UE_C_BASELINE_TOKEN_WORD],c[UE_C_BASELINE_TOKEN_WORD+1u])));
 ivec2 point=clamp(ivec2(floor(vec2(cf(UE_C_START_X_WORD),cf(UE_C_START_Z_WORD))/0.125+128.0)),ivec2(0),ivec2(255));
 float base=using_baseline?imageLoad(baseline,point).r:imageLoad(rock,point).r+imageLoad(sand,point).r;
 if(c[UE_C_HEIGHT_REFERENCE_WORD]==UE_HEIGHT_FIXED_WORLD)base=cf(UE_C_DATUM_Y_M_WORD);
 result[1]=bad;result[12]=floatBitsToUint(base);result[13]=floatBitsToUint(low);result[14]=floatBitsToUint(high);result[15]=floatBitsToUint(h);result[16]=count;result[17]=obs;result[18]=uint(using_baseline);result[19]=floatBitsToUint(imageLoad(clock_value,ivec2(0)).r);
}
