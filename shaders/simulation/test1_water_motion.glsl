#[compute]
#version 450
// Reconstructed captured equations. Immutable phase inputs replace the original in-place UAV.
layout(local_size_x=8,local_size_y=8,local_size_z=1) in;
layout(rgba32f,set=0,binding=0) uniform restrict readonly image2D state_in;
layout(rgba32f,set=0,binding=1) uniform restrict writeonly image2D state_out;
layout(rgba32f,set=0,binding=2) uniform restrict readonly image2D aux_in;
layout(push_constant,std430) uniform Params { float phase; float clock; float level_override; float drag; } params;
const float DX=0.05859375, DT=0.00732421875, G=16.0, BIAS=0.05;
ivec2 bounded(ivec2 p) {return clamp(p,ivec2(0),imageSize(state_in)-1);}
vec4 at(ivec2 p) {return imageLoad(state_in,bounded(p));}
float depth(vec4 a) {return max(a.z-BIAS,0.0);}
float eta(vec4 a) {return a.w+depth(a);}
float quant_h(float a) {return floor(clamp(a/10.1,0.0,1.0)*16777215.0+0.5)*(10.1/16777215.0);}
vec2 quant_v(vec2 v) {return floor(clamp((v+4.0)*0.125,vec2(0),vec2(1))*16777215.0+0.5)*(8.0/16777215.0)-4.0;}
vec2 sample_velocity(vec2 p) {
 ivec2 q=ivec2(floor(p));vec2 f=fract(p);
 return mix(mix(at(q).xy,at(q+ivec2(1,0)).xy,f.x),mix(at(q+ivec2(0,1)).xy,at(q+ivec2(1,1)).xy,f.x),f.y);
}
void main() {
 ivec2 p=ivec2(gl_GlobalInvocationID.xy);ivec2 size=imageSize(state_in);
 if(any(greaterThanEqual(p,size))) return;
 vec4 c=at(p),l=at(p+ivec2(-1,0)),r=at(p+ivec2(1,0)),t=at(p+ivec2(0,-1)),b=at(p+ivec2(0,1));
 if(params.phase<0.5) {
  vec2 v=c.xy-G*DT*vec2(eta(r)-eta(c),eta(b)-eta(c))/DX;
  v*=1.0-DT*params.drag;
  vec2 uv=(vec2(p)+0.5)/vec2(size);
  vec2 low=smoothstep(vec2(0),vec2(1),uv*20.0),high=smoothstep(vec2(0),vec2(1),(1.0-uv)*20.0);
  float edge=1.0-low.x*low.y*high.x*high.y;
  v*=1.0-DT*edge;
  vec2 rv=p.x==size.x-1?vec2(0):r.xy,bv=p.y==size.y-1?vec2(0):b.xy;
  v=(l.xy+t.xy+rv+bv+1000.0*v)/1004.0;
  float eps=DX*0.0001;
  if((eta(c)<r.w && depth(r)<=eps)||(eta(r)<c.w && depth(c)<=eps)) v.x=0.0;
  if((eta(c)<b.w && depth(b)<=eps)||(eta(b)<c.w && depth(c)<=eps)) v.y=0.0;
  v*=min(1.0,2.0/max(length(v),1e-20));c.xy=quant_v(v);
 } else if(params.phase<1.5) {
  float hc=depth(c),hl=depth(l),hr=depth(r),ht=depth(t),hb=depth(b);
  float correction=max((hl+hr+ht+hb)*0.25-2.0*DX/(DT*G),0.0);
  float vl=p.x==0?0.0:l.x,vt=p.y==0?0.0:t.y;
  float fl=vl*((vl>=0.0?hl:hc)-correction),fr=c.x*((c.x<=0.0?hr:hc)-correction);
  float ft=vt*((vt>=0.0?ht:hc)-correction),fb=c.y*((c.y<=0.0?hb:hc)-correction);
  c.z=quant_h(clamp(c.z-DT*(fr-fl+fb-ft)/DX,0.0,10.0));
 } else if(params.phase<2.5) {
  c.xy=quant_v(sample_velocity(vec2(p)-c.xy*DT*0.2/DX));
 } else {
  vec4 aux=imageLoad(aux_in,p);
  float amount=c.z-exp(-aux.z*0.5)*0.0001*0.025;
  float surface=eta(c),uvy=(float(p.y)+0.5)/float(size.y);
  if(surface>=aux.w && aux.w-surface<0.1 && c.w<aux.w) amount+=sin(params.clock*8.0+uvy*0.0378)*0.025*0.15;
  float alpha=aux.x/15.0;
  float target=max(max(sin(params.clock)*0.049701884388923645,-0.5)+1.0-c.w,0.05);
  amount=mix(amount,target,alpha);
  if(params.level_override>0.0) amount=mix(amount,1.0+params.level_override-c.w,alpha);
  if(aux.y>1.05) amount+=aux.y/15.0*0.025;
  c.z=quant_h(clamp(amount,0.0,10.0));
 }
 imageStore(state_out,p,c);
}
