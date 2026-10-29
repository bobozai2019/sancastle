#[compute]
#version 450
layout(local_size_x=1) in;
layout(set=0,binding=0,std430) buffer Receipt {uint r[];};
layout(set=0,binding=1,std430) readonly buffer WaterReceipt {uint w[];};
struct InputCell {vec4 bed_water;vec4 flow;};
layout(set=0,binding=2,std430) readonly buffer Input {InputCell inputs[];};
layout(set=0,binding=3,std430) readonly buffer Candidate {vec4 values[];};
layout(set=0,binding=4,std430) readonly buffer Cells {uint v[];};
layout(push_constant,std430) uniform Push {uint n,index,phase,policy,pad0,pad1,pad2,pad3;}p;
void add(float value,inout float sum,inout float correction){precise float y=value-correction;precise float next=sum+y;correction=(next-sum)-y;sum=next;}
float ulp(float a){uint e=(floatBitsToUint(abs(a))>>23u)&255u;return e==0u?uintBitsToFloat(1u):exp2(float(int(e)-127-23));}
void reject(){r[3]=3u;r[20]=17u;r[31]|=512u;r[14]=r[12];r[15]=r[13];r[22]=0u;r[23]=0u;for(uint j=24u;j<30u;j++)r[j]=0u;for(uint j=32u;j<39u;j++)r[j]=0u;for(uint j=40u;j<52u;j++)r[j]=0u;}
void main(){if(r[3]!=1u||p.policy==0u)return;if(w[0]!=1u||w[1]!=0u){reject();return;}
 float error=0,sederror=0,q=0,sq=0,absolute=0,sa=0,c0=0,c1=0,c2=0,c3=0,c4=0,c5=0;uint touched=0;
 for(uint i=0u;i<p.n*p.n;i++){
  vec4 old=vec4(inputs[i].bed_water.zw,inputs[i].flow.xy),next=values[i];
  if(any(isnan(next))||any(isinf(next))||next.x<0.0||next.y<0.0){reject();return;}
  add((next.x-old.x)*0.015625,error,c0);add((next.y-old.y)*0.015625,sederror,c1);
  // The water candidate scans every existing wet component. Those cells,
  // shape-touched cells and actual changes form its predeclared audit union.
  if(old.x>0.001||any(notEqual(old,next))||(v[i*16u+15u]&1u)!=0u){
   touched++;add(2.0*ulp(max(abs(old.x),abs(next.x)))*0.015625,q,c2);add(2.0*ulp(max(abs(old.y),abs(next.y)))*0.015625,sq,c3);
   add(abs(next.x-old.x)*0.015625,absolute,c4);add(abs(next.y-old.y)*0.015625,sa,c5);
  }
 }
 float u=5.960464477539063e-8;
 float eps=max(1e-7,q+max(1e-8,(8.0*u+2.0*(float(touched)+256.0)*u*u)*absolute));
 float seps=max(1e-7,sq+max(1e-8,(8.0*u+2.0*(float(touched)+256.0)*u*u)*sa));
 if(abs(error)>eps||abs(sederror)>seps){reject();return;}
 r[30]=w[3];r[40]=w[4];r[41]=w[5];r[42]=floatBitsToUint(error);r[43]=w[17];r[44]=w[18];r[47]=floatBitsToUint(eps);r[23]=w[21];
}
