#[compute]
#version 450
layout(local_size_x=1) in;
layout(set=0,binding=0,std430) readonly buffer Waves {vec4 waves[];};
layout(set=0,binding=1,std430) readonly buffer Control {uint control[];};
layout(set=0,binding=2,std430) buffer Trace {vec4 values[];};
layout(push_constant,std430) uniform Params {uint count;}p;
void main(){
 float time=uintBitsToFloat(control[8]),wave=0.0;
 for(uint j=0u;j<p.count;j++){
  vec4 a=waves[j];float u=(time-a.x)/a.y;
  float envelope=0.0,oscillation=0.0,term=0.0;
  if(u>=0.0&&u<1.0){
   envelope=sin(3.141592653589793*u);
   oscillation=sin(6.283185307179586*u+a.w);
   term=a.z*envelope*envelope*(0.95+0.05*oscillation);
   wave+=term;
  }
  values[j]=vec4(u,envelope,oscillation,term);
 }
 values[128]=vec4(time,min(wave,0.25),float(p.count),1.0);
}
