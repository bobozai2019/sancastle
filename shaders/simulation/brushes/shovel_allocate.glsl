#[compute]
#version 450
layout(local_size_x=1) in;
layout(set=0,binding=0,std430) readonly buffer Command {uint c[];};
layout(set=0,binding=2,std430) buffer Cells {uint v[];};
layout(set=0,binding=3,std430) buffer Scratch {uint s[];};
layout(set=0,binding=6,rg32f) uniform image2D candidate;
layout(set=1,binding=13,r16f) uniform readonly image2D compact0;
layout(set=1,binding=14,r16f) uniform readonly image2D compact1;
layout(set=1,binding=16,rg32f) uniform readonly image2D support0;
layout(set=1,binding=17,rg32f) uniform readonly image2D support1;
layout(push_constant,std430) uniform Push {uint n,x,z,w,h,index,phase,reserved;}p;
float f(uint i){return uintBitsToFloat(c[i]);}
float cell(uint k,uint j){return uintBitsToFloat(v[k+j]);}
float quantum(float value){uint e=(floatBitsToUint(abs(value))>>23u)&255u;return e==0u?uintBitsToFloat(1u):exp2(float(int(e)-127-23));}
void add(float a,inout float sum,inout float corr){float y=a-corr,t=sum+y;corr=(t-sum)-y;sum=t;}
ivec4 bounds;
float capacity(uint k){return max(0.0,cell(k,11)-cell(k,2)-cell(k,0));}
float allocated(float lambda,uint side){
 float sum=0.0,corr=0.0;
 for(int z=bounds.y;z<=bounds.w;z++)for(int x=bounds.x;x<=bounds.z;x++){
  uint k=(uint(z)*p.n+uint(x))*16u;
  if((v[k+15u]&side)!=0u)add(min(capacity(k),lambda*max(0.0,cell(k,12))),sum,corr);
 }return sum;
}
void shoulder(uint side,float target){
 float hi=0.0,lo=0.0;
 for(int z=bounds.y;z<=bounds.w;z++)for(int x=bounds.x;x<=bounds.z;x++){
  uint k=(uint(z)*p.n+uint(x))*16u;
  if((v[k+15u]&side)!=0u&&cell(k,12)>0.0)hi=max(hi,capacity(k)/cell(k,12));
 }
 for(uint iteration=0u;iteration<48u;iteration++){
  float middle=lo+(hi-lo)*0.5;
  if(allocated(middle,side)<target)lo=middle;else hi=middle;
 }
 float lambda=lo+(hi-lo)*0.5,sum=0.0,corr=0.0;
 for(int z=bounds.y;z<=bounds.w;z++)for(int x=bounds.x;x<=bounds.z;x++){
  uint k=(uint(z)*p.n+uint(x))*16u;if((v[k+15u]&side)==0u)continue;
  float old=cell(k,0),next=min(old+capacity(k),old+min(capacity(k),lambda*max(0.0,cell(k,12))));
  v[k+1u]=floatBitsToUint(next);add(next-old,sum,corr);
 }
 // At most two deterministic row-major residual corrections, with at most
 // one total-sand ULP per cell per round. Spread quantization repair instead
 // of concentrating a whole side's residual in its first available cell.
 // Final validate still checks the unchanged frozen mass/permission budget.
 for(uint round=0u;round<2u;round++){
  float residue=target-sum;
  for(int z=bounds.y;z<=bounds.w;z++)for(int x=bounds.x;x<=bounds.z;x++){
   uint k=(uint(z)*p.n+uint(x))*16u;if((v[k+15u]&side)==0u)continue;
   float old=cell(k,0),next=cell(k,1),limit=old+capacity(k);
   float step=quantum(next);
   float corrected=clamp(next+clamp(residue,-step,step),old,limit);v[k+1u]=floatBitsToUint(corrected);residue-=corrected-next;
  }
  sum=0.0;corr=0.0;
  for(int z=bounds.y;z<=bounds.w;z++)for(int x=bounds.x;x<=bounds.z;x++){
   uint k=(uint(z)*p.n+uint(x))*16u;if((v[k+15u]&side)!=0u)add(cell(k,1)-cell(k,0),sum,corr);
  }
 }
}
void main(){
 float outer=f(34)*0.5+f(36);vec2 a=vec2(f(24),f(25)),b=vec2(f(26),f(27));
 ivec2 lower=ivec2(floor((min(a,b)-outer)/f(40)+float(p.n)*0.5-0.5));
 ivec2 upper=ivec2(ceil((max(a,b)+outer)/f(40)+float(p.n)*0.5-0.5));
 bounds=ivec4(clamp(lower,ivec2(0),ivec2(p.n-1u)),clamp(upper,ivec2(0),ivec2(p.n-1u)));
 float cut=0.0,left=0.0,right=0.0,cc=0.0,cl=0.0,cr=0.0;
 for(int z=bounds.y;z<=bounds.w;z++)for(int x=bounds.x;x<=bounds.z;x++){
  uint k=(uint(z)*p.n+uint(x))*16u,bits=v[k+15u];
  if((bits&2u)!=0u)add(max(0.0,cell(k,0)-cell(k,1)),cut,cc);
  if((bits&4u)!=0u)add(capacity(k),left,cl);
  if((bits&8u)!=0u)add(capacity(k),right,cr);
 }
 float limit=min(min(cut,max(0.0,f(39))/0.015625),2.0*min(left,right));
 float scale=cut>0.0?limit/cut:0.0,actual=0.0,tagged=0.0,compact=0.0,ca=0.0,ct=0.0,cm=0.0;
 for(int z=bounds.y;z<=bounds.w;z++)for(int x=bounds.x;x<=bounds.z;x++){
  uint k=(uint(z)*p.n+uint(x))*16u;if((v[k+15u]&2u)==0u)continue;
  float old=cell(k,0),next=max(0.0,old-max(0.0,old-cell(k,1))*scale),moved=old-next;
  v[k+1u]=floatBitsToUint(next);add(moved,actual,ca);
  vec2 tag=p.index==0u?imageLoad(support0,ivec2(x,z)).xy:imageLoad(support1,ivec2(x,z)).xy;
  float comp=p.index==0u?imageLoad(compact0,ivec2(x,z)).x:imageLoad(compact1,ivec2(x,z)).x;
  add(min(max(tag.x,0.0),moved),tagged,ct);add(moved*comp,compact,cm);
 }
 shoulder(4u,actual*0.5);shoulder(8u,actual*0.5);
 // First 4096 words remain the original per-block reduction scratch.
 s[4096]=floatBitsToUint(actual);s[4097]=floatBitsToUint(tagged);s[4098]=floatBitsToUint(actual>0.0?compact/actual:0.0);
 s[4099]=floatBitsToUint(cut);
 for(int z=bounds.y;z<=bounds.w;z++)for(int x=bounds.x;x<=bounds.z;x++){
  uint k=(uint(z)*p.n+uint(x))*16u;
  if((v[k+15u]&2u)!=0u){vec2 cv=imageLoad(candidate,ivec2(x,z)).xy;cv.x=max(cv.x,cell(k,1)+cell(k,2));imageStore(candidate,ivec2(x,z),vec4(cv,0,0));}
  if(cell(k,0)!=cell(k,1)&&cell(k,3)>0.0&&p.phase!=2u)v[k+15u]|=512u;
 }
}
