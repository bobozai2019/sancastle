#[compute]
#version 450
layout(local_size_x=8,local_size_y=8) in;
layout(r32f,set=0,binding=0) uniform readonly image2D bed;
layout(r32f,set=0,binding=1) uniform readonly image2D water;
layout(r32f,set=0,binding=2) uniform readonly image2D qx;
layout(r32f,set=0,binding=3) uniform readonly image2D qz;
layout(rgba32f,set=0,binding=4) uniform readonly image2D edits;
layout(set=0,binding=5,std430) buffer Tiles {vec4 t[];};
shared vec4 a[64];shared vec4 b[64];shared vec4 c[64];shared vec4 d[64];shared vec4 e[64];
void main(){
 ivec2 p=ivec2(gl_GlobalInvocationID.xy);uint i=gl_LocalInvocationIndex;
 float h=imageLoad(water,p).r,z=imageLoad(bed,p).r;
 vec2 q=vec2(imageLoad(qx,p).r,imageLoad(qz,p).r),v=h>.001?q/h:vec2(0);
 vec4 edit=imageLoad(edits,p);float speed=length(v),wave=abs(v.x)+abs(v.y)+2.*sqrt(9.81*max(h,0.));
 bool bad=isnan(h)||isinf(h)||isnan(z)||isinf(z)||any(isnan(q))||any(isinf(q))||h<0.||z<0.;
 vec2 point=(vec2(p)+.5-vec2(imageSize(water))*.5)*.125;
 bool roi=length(point)<1.5;vec2 radial=length(point)>0.?normalize(point):vec2(0);
 a[i]=vec4(h,z,h>.001?dot(q,q)/(2.*h):0.,bad?1.:0.);
 b[i]=vec4(wave,speed,h,-h);c[i]=edit;
 d[i]=vec4(roi?h:0.,roi?dot(q,radial):0.,roi?speed:0.,-z);
 e[i]=vec4(q,0,0);barrier();
 for(uint k=32u;k>0u;k>>=1u){if(i<k){a[i]+=a[i+k];b[i]=max(b[i],b[i+k]);c[i]+=c[i+k];d[i].xyz+=d[i+k].xyz;d[i].w=max(d[i].w,d[i+k].w);e[i]+=e[i+k];}barrier();}
 if(i==0u){uint tile=gl_WorkGroupID.y*gl_NumWorkGroups.x+gl_WorkGroupID.x;t[tile*5u]=a[0];t[tile*5u+1u]=b[0];t[tile*5u+2u]=c[0];t[tile*5u+3u]=d[0];t[tile*5u+4u]=e[0];}
}
