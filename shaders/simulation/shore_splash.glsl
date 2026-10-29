#[compute]
#version 450
layout(local_size_x=8,local_size_y=8) in;
layout(set=0,binding=0,rgba32f) uniform image2D positions;
layout(set=0,binding=1,rgba32f) uniform image2D velocities;
layout(set=0,binding=2,rgba32f) uniform writeonly image2D position_view;
layout(set=0,binding=3,rgba32f) uniform writeonly image2D velocity_view;
layout(set=0,binding=4,r32f) uniform readonly image2D rock;
layout(set=0,binding=5,r32f) uniform readonly image2D sand;
layout(set=0,binding=6,r32f) uniform readonly image2D water_depth;
layout(set=0,binding=7,rg32f) uniform readonly image2D momentum;

layout(set=0,binding=8,r8) uniform readonly image2D obstacle;
layout(set=0,binding=9,std430) readonly buffer Control {uint control[];};
layout(push_constant,std430) uniform Settings {vec4 bounds;} settings;

uint hash32(uint v){v^=v>>16u;v*=0x7feb352du;v^=v>>15u;v*=0x846ca68bu;return v^(v>>16u);}
float random01(uint v){return float(hash32(v)>>8u)/16777216.0;}
ivec2 cell_at(vec2 xz){return clamp(ivec2((xz/32.0+0.5)*256.0),ivec2(0),ivec2(255));}
float bed_cell(ivec2 q){q=clamp(q,ivec2(0),ivec2(255));return imageLoad(rock,q).r+imageLoad(sand,q).r;}
float bed_at(vec2 xz){
 vec2 p=(xz/32.0+0.5)*256.0-0.5;ivec2 q=ivec2(floor(p));vec2 f=fract(p);
 float a=bed_cell(q),b=bed_cell(q+ivec2(1,0)),c=bed_cell(q+ivec2(0,1)),d=bed_cell(q+ivec2(1,1));
 return f.x+f.y<=1.0?a+f.x*(b-a)+f.y*(c-a):d+(1.0-f.x)*(c-d)+(1.0-f.y)*(b-d);
}
void main(){
 if(control[1]!=0u)return; // Only sealed successful work may update/publish.
 ivec2 at=ivec2(gl_GlobalInvocationID.xy);if(at.x>=64||at.y>=16)return;
 uint id=uint(at.y*64+at.x);
 float dt=uintBitsToFloat(control[9]);
 vec4 p=imageLoad(positions,at),v=imageLoad(velocities,at);
 bool was_alive=p.w>0.0;
 if(was_alive){
  if(dt>0.0){
   p.xyz+=v.xyz*dt+vec3(0.0,-4.9*dt*dt,0.0);
   v.y-=9.8*dt;v.xz*=exp(-0.65*dt);p.w=max(p.w-dt,0.0);
  }
  ivec2 q=cell_at(p.xz);float floor_y=bed_at(p.xz)+max(imageLoad(water_depth,q).r,0.0);
  if(any(lessThan(p.xz,settings.bounds.xy))||any(greaterThan(p.xz,settings.bounds.zw))||p.y<=floor_y+0.003||imageLoad(obstacle,q).r>0.5)p.w=0.0;
 }
 // A died slot waits one work unit before attempting a fresh splash.
 // Spawn rate is per accepted simulation second, never render-frame based.
 if(!was_alive&&dt>0.0){
  uint seed=hash32(id*0x9e3779b9u+control[6]*0x85ebca6bu+control[7]+62143u);
  for(uint attempt=0u;attempt<8u;attempt++){
   uint k=seed+attempt*0x27d4eb2du;
   vec2 xz=mix(settings.bounds.xy,settings.bounds.zw,vec2(random01(k),random01(k+17u)));
   ivec2 q=cell_at(xz);float h=imageLoad(water_depth,q).r;
   if(h<0.004||h>0.18||imageLoad(sand,q).r<0.02||imageLoad(obstacle,q).r>0.5)continue;
   vec2 flow=imageLoad(momentum,q).rg/max(h,0.02);
   flow*=min(1.0,3.0/max(length(flow),0.0001));
   vec2 slope=vec2(bed_cell(q+ivec2(1,0))-bed_cell(q-ivec2(1,0)),bed_cell(q+ivec2(0,1))-bed_cell(q-ivec2(0,1)))/0.25;
   if(length(slope)<0.04)continue;
   vec2 shore_normal=normalize(slope);float hit_speed=max(dot(flow,shore_normal),0.0);
   if(hit_speed<0.28)continue;
   float eta=bed_at(xz)+h;
   vec2 ahead=xz+shore_normal*0.25;ivec2 ahead_q=cell_at(ahead);
   bool bank=imageLoad(water_depth,ahead_q).r<0.004||bed_at(ahead)>eta-0.008;
   if(!bank||random01(k+37u)>min(1.0,dt*36.0*smoothstep(0.28,1.2,hit_speed)))continue;
   float lifetime=mix(0.25,0.60,random01(k+41u));
   vec2 tangent=vec2(-shore_normal.y,shore_normal.x);
   vec2 horizontal=flow*0.30-shore_normal*hit_speed*0.45+tangent*(random01(k+53u)-0.5)*0.7;
   p=vec4(xz.x,eta+0.018,xz.y,lifetime);
   v=vec4(horizontal.x,clamp(0.65+hit_speed*0.8,0.65,2.5)*(0.8+0.4*random01(k+71u)),horizontal.y,lifetime);
   break;
  }
 }
 imageStore(positions,at,p);imageStore(velocities,at,v);
 imageStore(position_view,at,p);imageStore(velocity_view,at,v);
}
