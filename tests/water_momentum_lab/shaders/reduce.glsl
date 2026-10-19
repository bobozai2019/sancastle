#[compute]
#version 450
layout(local_size_x=256) in;
layout(set=0,binding=0,std430) readonly buffer Tiles {vec4 t[];};
layout(set=0,binding=1,std430) buffer Result {vec4 result[8];};
layout(set=0,binding=2,std430) buffer Step {vec4 params;};
layout(push_constant,std430) uniform P {uint tiles;uint advance;uint pad0;uint pad1;} p;
shared vec4 a[256];shared vec4 b[256];shared vec4 c[256];shared vec4 d[256];shared vec4 e[256];
void main(){
 uint i=gl_LocalInvocationIndex;a[i]=vec4(0);b[i]=vec4(0,0,0,-1e20);c[i]=vec4(0);d[i]=vec4(0,0,0,-1e20);e[i]=vec4(0);
 for(uint n=i;n<p.tiles;n+=256u){a[i]+=t[n*5u];b[i]=max(b[i],t[n*5u+1u]);c[i]+=t[n*5u+2u];d[i].xyz+=t[n*5u+3u].xyz;d[i].w=max(d[i].w,t[n*5u+3u].w);e[i]+=t[n*5u+4u];}barrier();
 for(uint k=128u;k>0u;k>>=1u){if(i<k){a[i]+=a[i+k];b[i]=max(b[i],b[i+k]);c[i]+=c[i+k];d[i].xyz+=d[i+k].xyz;d[i].w=max(d[i].w,d[i+k].w);e[i]+=e[i+k];}barrier();}
 if(i==0u){
  float dt=min(1./120.,.35*.125/max(b[0].x,1e-8));
  params=vec4(dt/.125,.125,0.,0.);
  result[0]=a[0]*vec4(.015625,.015625,.015625,1.);result[1]=b[0];result[2]=c[0];result[3]=d[0];result[4]=e[0];
  if(p.advance==1u){result[5].x+=dt;result[5].y+=1.;}result[5].z=dt;
 }
}
