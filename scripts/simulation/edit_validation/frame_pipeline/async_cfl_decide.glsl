#[compute]
#version 450
layout(local_size_x=64) in;
layout(set=0,binding=0,r32f) uniform readonly image2D tile_max_in;
layout(set=0,binding=1,std430) buffer Decision {uint d[];};
layout(set=0,binding=2,std430) buffer Indirect {uint groups[];};
layout(set=0,binding=3,std430) buffer Control {uint control[];};
layout(push_constant,std430) uniform Params {float requested_dt,cell_size,courant;uint grid_size;}p;
shared float values[64];
bool finite_value(float x){return !isnan(x)&&!isinf(x);}
void main(){
 uint lane=gl_LocalInvocationID.x;ivec2 size=imageSize(tile_max_in);float speed=0.01;
 for(uint j=lane;j<uint(size.x*size.y);j+=64u){
  float a=imageLoad(tile_max_in,ivec2(j%uint(size.x),j/uint(size.x))).r;
  speed=(!finite_value(a)||a<0.0||speed<0.0)?-1.0:max(speed,a);
 }
 values[lane]=speed;barrier();
 for(uint stride=32u;stride>0u;stride>>=1u){
  if(lane<stride)values[lane]=(values[lane]<0.0||values[lane+stride]<0.0)?-1.0:max(values[lane],values[lane+stride]);
  barrier();
 }
 if(lane!=0u)return;
 for(uint j=0u;j<16u;j++)d[j]=0u;
 float maximum=values[0],actual_dt=0.0,dt=0.0;uint n=0u,status=2u;
 if(control[1]==0u&&maximum>=0.01&&finite_value(p.requested_dt)&&p.requested_dt>0.0&&p.cell_size>0.0){
  float safe_dt=p.courant*p.cell_size/maximum;
  float needed=p.requested_dt/safe_dt;
  n=needed>64.0?64u:max(1u,uint(ceil(needed)));
  actual_dt=min(p.requested_dt,64.0*safe_dt);dt=actual_dt/float(n);status=needed>64.0?1u:0u;
  if(!finite_value(dt)||dt<=0.0){status=2u;n=0u;actual_dt=0.0;dt=0.0;}
 }
 d[0]=floatBitsToUint(maximum);d[1]=n;d[2]=floatBitsToUint(dt);d[3]=floatBitsToUint(actual_dt);
 d[4]=status;d[5]=n&1u;d[6]=floatBitsToUint(p.requested_dt);d[8]=floatBitsToUint(p.cell_size);d[9]=floatBitsToUint(dt/p.cell_size);
 if(status==2u)control[1]|=16u;
 for(uint i=0u;i<64u;i++){groups[i*3u]=i<n?p.grid_size/8u:0u;groups[i*3u+1u]=p.grid_size/8u;groups[i*3u+2u]=1u;}
}
