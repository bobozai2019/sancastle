#[compute]
#version 450
layout(local_size_x=8,local_size_y=8) in;
layout(set=0,binding=0,rgba32f) uniform image2D roots;
layout(set=0,binding=1,rgba32f) uniform image2D motion;
layout(set=0,binding=2,r32f) uniform readonly image2D rock;
layout(set=0,binding=3,r32f) uniform readonly image2D sand;
layout(set=0,binding=4,r32f) uniform readonly image2D water_depth;
layout(set=0,binding=5,r32f) uniform readonly image2D momentum_x;
layout(set=0,binding=6,r32f) uniform readonly image2D momentum_z;
layout(set=0,binding=7,r8) uniform readonly image2D obstacle;
layout(set=0,binding=8,std430) readonly buffer Control {uint control[];};
layout(set=0,binding=9,std430) readonly buffer Settings {vec4 settings[];};
layout(push_constant,std430) uniform Phase {uint mode;} phase;

uint hash32(uint v){v^=v>>16u;v*=0x7feb352du;v^=v>>15u;v*=0x846ca68bu;return v^(v>>16u);}
float random01(uint v){return float(hash32(v)>>8u)/16777216.0;}
float noise(vec2 p){
 ivec2 q=ivec2(floor(p));vec2 f=fract(p);f=f*f*(3.0-2.0*f);
 uint k=uint(q.x)*0x165667b1u+uint(q.y)*0x27d4eb2du;
 return mix(mix(random01(k),random01(k+0x165667b1u),f.x),mix(random01(k+0x27d4eb2du),random01(k+0x3e2b52deu),f.x),f.y);
}
float bed_cell(ivec2 q){q=clamp(q,ivec2(0),ivec2(255));return imageLoad(rock,q).r+imageLoad(sand,q).r;}
float bed_at(vec2 xz){
 vec2 p=(xz/32.0+0.5)*256.0-0.5;ivec2 q=ivec2(floor(p));vec2 f=fract(p);
 float a=bed_cell(q),b=bed_cell(q+ivec2(1,0)),c=bed_cell(q+ivec2(0,1)),d=bed_cell(q+ivec2(1,1));
 return f.x+f.y<=1.0?a+f.x*(b-a)+f.y*(c-a):d+(1.0-f.x)*(c-d)+(1.0-f.y)*(b-d);
}
vec3 water_cell(ivec2 q){q=clamp(q,ivec2(0),ivec2(255));return vec3(imageLoad(water_depth,q).r,imageLoad(momentum_x,q).r,imageLoad(momentum_z,q).r);}
vec3 water_at(vec2 xz){
 vec2 p=(xz/32.0+0.5)*256.0-0.5;ivec2 q=ivec2(floor(p));vec2 f=fract(p);
 return mix(mix(water_cell(q),water_cell(q+ivec2(1,0)),f.x),mix(water_cell(q+ivec2(0,1)),water_cell(q+ivec2(1,1)),f.x),f.y);
}
void main(){
 ivec2 at=ivec2(gl_GlobalInvocationID.xy);if(any(greaterThanEqual(at,ivec2(128,144))))return;
 // VEG_GUARD
 float dt = 0.0; // VEG_DT
 uint id=uint(at.y*128+at.x);uint count=uint(settings[1].y);uint kind=id/count;uint local_id=id%count;
 uint seed=uint(settings[1].x)+id*0x9e3779b9u;
 vec4 habitat=settings[2u+kind*3u],distribution=settings[3u+kind*3u],response=settings[4u+kind*3u];
 if(phase.mode==1u){
  vec2 grid=vec2(float(local_id%64u)+random01(seed),float(local_id/64u)+random01(seed+61u))/vec2(64.0,32.0);
  vec2 xz=mix(settings[0].xy,settings[0].zw,grid);float y=bed_at(xz);vec3 w=water_at(xz);
  ivec2 cell=clamp(ivec2((xz/32.0+0.5)*256.0),ivec2(0),ivec2(255));
  vec2 slope=vec2(bed_at(xz+vec2(0.0625,0))-bed_at(xz-vec2(0.0625,0)),bed_at(xz+vec2(0,0.0625))-bed_at(xz-vec2(0,0.0625)))/0.125;
  float patch_value=noise(xz*0.30+vec2(3.1,7.7));
  bool alive=w.x>=habitat.x&&w.x<=habitat.y&&y>=distribution.x&&y<=distribution.y&&length(slope)<=response.x;
  alive=alive&&patch_value>=response.y&&patch_value<=response.z&&random01(seed+197u)<distribution.z*smoothstep(response.y,min(response.y+0.12,response.z),patch_value)&&imageLoad(obstacle,cell).r<0.5&&imageLoad(sand,cell).r>0.02;
  float size=mix(habitat.z,habitat.w,random01(seed+113u));
  imageStore(roots,at,vec4(xz.x,y,xz.y,alive?size:0.0));imageStore(motion,at,vec4(0));return;
 }
 vec4 root=imageLoad(roots,at);if(root.w<=0.0)return;
 root.y=min(root.y,bed_at(root.xz));imageStore(roots,at,root);
 if(dt<=0.0)return;
 vec4 old=imageLoad(motion,at);vec3 w=water_at(root.xz);vec2 velocity=w.yz/max(w.x,0.005);
 vec2 target=velocity*distribution.w*smoothstep(0.002,0.05,w.x);
 target*=min(1.0,0.65/max(length(target),0.0001));
 // Exact critically damped response: stable with the accepted GPU dt.
 float omega=response.w;vec2 delta=old.xy-target;vec2 c=old.zw+omega*delta;float decay=exp(-omega*dt);
 vec2 bend=target+(delta+c*dt)*decay;vec2 speed=(old.zw-omega*c*dt)*decay;
 imageStore(motion,at,vec4(bend,speed));
}
