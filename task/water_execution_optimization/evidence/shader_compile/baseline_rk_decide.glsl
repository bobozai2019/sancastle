
#version 450
layout(local_size_x=64) in;
layout(set=0,binding=0,rg32f) uniform readonly image2D speed_tiles;
layout(set=0,binding=1,std430) buffer Decision {uint d[];};
layout(set=0,binding=2,std430) buffer Trial {uint tr[];};
layout(set=0,binding=3,std430) buffer Safety {uint stats[];};
layout(set=0,binding=4,std430) buffer Audit {uint audit[];};
layout(set=0,binding=5,std430) buffer TrialGroups {uint tg[];};
layout(set=0,binding=6,std430) buffer AcceptGroups {uint ag[];};
layout(set=0,binding=7,std430) buffer Control {uint control[];};
layout(push_constant,std430) uniform Params {uint mode,index;float requested_dt,cell_size;}p;
const float G=9.81;
const float DRY=0.001;
const float VELOCITY_DEPTH=0.005;
const float EPS=1.1920928955078125e-7;
bool finite1(float x){return !isnan(x)&&!isinf(x);}
bool finite4(vec4 x){return !any(isnan(x))&&!any(isinf(x));}
float mc(float l,float r){return l*r>0.0?sign(l)*min(min(2.0*abs(l),2.0*abs(r)),0.5*abs(l+r)):0.0;}
vec4 mc4(vec4 l,vec4 r){return vec4(mc(l.x,r.x),mc(l.y,r.y),mc(l.z,r.z),mc(l.w,r.w));}
// Convex blend of MC and Superbee slopes. Never reduce the Rusanov speed
// bound, add energy, or change the wet/dry and positivity safeguards.
float retained_slope(float l,float r,float retention){
 float base=mc(l,r);
 if(retention<=0.0||l*r<=0.0)return base;
 float sharp=sign(l)*max(min(2.0*abs(l),abs(r)),min(abs(l),2.0*abs(r)));
 return mix(base,sharp,retention);
}
vec4 retained_slopes(vec4 l,vec4 r,float retention){return vec4(retained_slope(l.x,r.x,retention),retained_slope(l.y,r.y,retention),retained_slope(l.z,r.z,retention),retained_slope(l.w,r.w,retention));}
vec4 cap_state(vec4 a,out bool limited){
 limited=false;
 if(a.x<=DRY){a.yz=vec2(0.0);return a;}
 float length_q=length(a.yz),cap=a.x*max(1.5,3.0*sqrt(G*a.x));
 if(length_q>cap){a.yz*=cap/length_q;limited=true;}
 return a;
}

// stats[] and tr[] must be bound before including this file.
void add_float(uint at,float value){
 if(value==0.0)return;
 uint old=stats[at],seen;
 do{seen=old;old=atomicCompSwap(stats[at],seen,floatBitsToUint(uintBitsToFloat(seen)+value));}while(old!=seen);
}
void add_counter(uint at,uint amount){
 if(amount==0u)return;
 uint old=atomicAdd(stats[at],amount);
 if(old>0xffffffffu-amount)atomicAdd(stats[at+1u],1u);
}
float nonnegative(float value,float magnitude,uint base,uint count_offset,uint volume_offset,float area){
 if(!finite1(value)){atomicOr(tr[14],1u);return 0.0;}
 if(value<0.0){
  float bound=min(2e-6,8.0*EPS*magnitude);
  if(-value>bound){atomicOr(tr[14],2u);return 0.0;}
  add_counter(base+count_offset,1u);add_float(base+volume_offset,-value*area);return 0.0;
 }
 return value;
}

shared float sx[64],sz[64];
void groups(bool is_active,bool accepted){
 uint j=p.index*3u;tg[j]=is_active?32u:0u;tg[j+1u]=32u;tg[j+2u]=1u;
 ag[j]=accepted?32u:0u;ag[j+1u]=32u;ag[j+2u]=1u;
}
void fatal(uint flags){
 tr[14]|=flags;tr[6]=0u;tr[7]=0u;d[4]=2u;
 control[1]|=(flags&8u)!=0u?32u:16u;
 if(p.mode>=2u&&p.mode<=5u&&p.index<64u)audit[p.index*8u+6u]=tr[14];
 if(p.index<64u)groups(false,false);
}
void main(){
 uint lane=gl_LocalInvocationID.x;
 if(p.mode==2u||p.mode==3u||p.mode==7u){
  float ax=0.0,az=0.0;ivec2 size=imageSize(speed_tiles);
  for(uint j=lane;j<uint(size.x*size.y);j+=64u){vec2 a=imageLoad(speed_tiles,ivec2(j%uint(size.x),j/uint(size.x))).xy;ax=max(ax,a.x);az=max(az,a.y);}
  sx[lane]=ax;sz[lane]=az;barrier();
  for(uint stride=32u;stride>0u;stride>>=1u){if(lane<stride){sx[lane]=max(sx[lane],sx[lane+stride]);sz[lane]=max(sz[lane],sz[lane+stride]);}barrier();}
 }
 if(lane!=0u)return;
 if(p.mode==0u){
  for(uint j=0u;j<16u;j++)d[j]=0u;
  for(uint j=0u;j<32u;j++)tr[j]=0u;
  for(uint j=8u;j<32u;j++)stats[j]=0u;
  for(uint j=0u;j<512u;j++)audit[j]=0u;
  for(uint j=0u;j<192u;j++){tg[j]=0u;ag[j]=0u;}
  tr[0]=floatBitsToUint(p.requested_dt);tr[2]=0x7f7fffffu;tr[11]=floatBitsToUint(p.cell_size);tr[12]=p.index;
  d[6]=tr[0];d[8]=tr[11];
  if(control[1]!=0u||!finite1(p.requested_dt)||p.requested_dt<=0.0||!finite1(p.cell_size)||p.cell_size<=0.0){fatal(4u);return;}
  if(control[6]==0xffffffffu&&control[7]==0x7fffffffu){fatal(8u);return;}
  return;
 }
 if(p.mode==1u){
  tr[10]=p.index;tr[7]=0u;tr[16]=0u;
  for(uint j=16u;j<32u;j++)stats[j]=0u;
  bool is_active=control[1]==0u&&tr[14]==0u&&tr[13]==0u&&uintBitsToFloat(tr[1])<uintBitsToFloat(tr[0]);
  tr[6]=is_active?1u:0u;groups(is_active,false);audit[p.index*8u]=p.index;
  return;
 }
 if(p.mode==7u){if(tr[14]!=0u)fatal(tr[14]);else if(!finite1(sx[0]+sz[0]))fatal(1u);return;}
 if(p.mode==6u){
  d[1]=tr[4];d[3]=tr[1];d[5]=0u;d[10]=tr[5];
  if(control[1]!=0u||tr[14]!=0u)d[4]=2u;
  else d[4]=uintBitsToFloat(tr[1])<uintBitsToFloat(tr[0])?1u:0u;
  return;
 }
 if(p.mode==4u){if(tr[14]!=0u)fatal(tr[14]);return;}
 if(p.mode==5u){
  if(tr[7]==0u||control[1]!=0u)return;
  tr[1]=floatBitsToUint(uintBitsToFloat(tr[1])+uintBitsToFloat(tr[3]));tr[4]++;tr[2]=0x7f7fffffu;
  for(uint base=0u;base<=8u;base+=8u){
   for(uint j=0u;j<=4u;j+=2u){add_counter(base+j,stats[16u+j]);add_counter(base+j,stats[24u+j]);atomicAdd(stats[base+j+1u],stats[17u+j]+stats[25u+j]);}
   add_counter(base+4u,tr[16]);
   add_float(base+6u,0.5*(uintBitsToFloat(stats[22])+uintBitsToFloat(stats[30])));
   add_float(base+7u,0.5*(uintBitsToFloat(stats[23])+uintBitsToFloat(stats[31])));
  }
  d[1]=tr[4];d[3]=tr[1];audit[p.index*8u+5u]=tr[1];return;
 }
 if(tr[6]==0u||control[1]!=0u)return;
 if(tr[14]!=0u){fatal(tr[14]);return;}
 float sum_speed=max(sx[0]+sz[0],0.01);
 if(!finite1(sum_speed)){fatal(1u);return;}
 d[0]=floatBitsToUint(max(uintBitsToFloat(d[0]),sum_speed));
 if(p.mode==2u){
  tr[8]=floatBitsToUint(sum_speed);
  float remaining=uintBitsToFloat(tr[0])-uintBitsToFloat(tr[1]);
  float dt=min(min(remaining,0.2*uintBitsToFloat(tr[11])/sum_speed),uintBitsToFloat(tr[2]));
  if(!finite1(dt)||dt<=0.0){fatal(4u);return;}
  if(uintBitsToFloat(tr[1])+dt==uintBitsToFloat(tr[1])){tr[13]=1u;tr[6]=0u;groups(false,false);return;}
  tr[3]=floatBitsToUint(dt);d[2]=tr[3];d[9]=floatBitsToUint(dt/uintBitsToFloat(tr[11]));
  audit[p.index*8u+1u]=tr[3];audit[p.index*8u+3u]=tr[8];return;
 }
 if(p.mode==3u){
  tr[9]=floatBitsToUint(sum_speed);audit[p.index*8u+4u]=tr[9];
  float dt=uintBitsToFloat(tr[3]);
  if(dt>0.2*uintBitsToFloat(tr[11])/sum_speed*(1.0+8.0*EPS)){
   tr[5]++;tr[2]=floatBitsToUint(dt*0.5);tr[7]=0u;groups(true,false);return;
  }
  uint low=control[10]+tr[4]+1u,high=control[11]+uint(low<control[10]);
  if(high>0x7fffffffu){fatal(8u);return;}
  tr[7]=1u;groups(true,true);audit[p.index*8u+2u]=1u;
 }
}
