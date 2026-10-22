shader_type spatial;
render_mode cull_disabled;

uniform sampler2D vegetation_roots : filter_nearest, repeat_disable;
uniform sampler2D vegetation_motion : filter_nearest, repeat_disable;
uniform sampler2D async_clock : filter_nearest, repeat_disable;
uniform sampler2D water_state : filter_nearest, repeat_disable;
uniform int kind = 0;
uniform uint seed = 62143u;
uniform vec3 base_color : source_color = vec3(0.15,0.24,0.06);
uniform vec3 tip_color : source_color = vec3(0.40,0.48,0.13);
uniform float root_darkening = 0.25;
varying float plant_tint;
varying float living;
varying float submerged;

uint hash32(uint v){v^=v>>16u;v*=0x7feb352du;v^=v>>15u;v*=0x846ca68bu;return v^(v>>16u);}
float random01(uint v){return float(hash32(v)>>8u)/16777216.0;}
void vertex(){
 int id=INSTANCE_ID+kind*768;ivec2 at=ivec2(id%128,id/128);
 vec4 root=texelFetch(vegetation_roots,at,0);vec2 bend=texelFetch(vegetation_motion,at,0).xy;
 living=step(0.0001,root.w);uint rng=seed+uint(id)*0x9e3779b9u;
 float clock=texelFetch(async_clock,ivec2(0),0).r;
 float t=clamp((clock-random01(rng+17u)*0.25)*3.0,0.0,1.0)-1.0;
 float growth=0.25+0.75*(1.0+2.70158*t*t*t+1.70158*t*t);
 float angle=random01(rng+31u)*6.2831853;
 mat3 turn=mat3(vec3(cos(angle),0.0,sin(angle)),vec3(0,1,0),vec3(-sin(angle),0.0,cos(angle)));
 float height=VERTEX.y;vec3 local=turn*(VERTEX*root.w*growth);
 local.xz+=bend*height*height*root.w*growth;
 VERTEX=local+root.xyz;
 vec3 n=turn*NORMAL;n.y-=2.0*height*dot(bend,n.xz);NORMAL=normalize(n);
 if(living<0.5)VERTEX=vec3(0.0,-50.0,0.0);
 plant_tint=random01(rng+47u);
 submerged=clamp(textureLod(water_state,root.xz/32.0+vec2(0.5),0.0).r/max(root.w,0.01),0.0,1.0);
}
void fragment(){
 if(living<0.5)discard;
 if(!FRONT_FACING)NORMAL=-NORMAL;
 float rib=1.0-abs(UV.x*2.0-1.0);
 vec3 color=mix(base_color,tip_color,smoothstep(0.0,1.0,UV.y));
 color*=mix(0.85,1.10,plant_tint)*(1.0-root_darkening*(1.0-UV.y));
 color*=0.90+0.10*rib;color*=mix(vec3(1.0),vec3(0.77,0.91,0.78),submerged);
 ALBEDO=color;ROUGHNESS=0.86;SPECULAR=0.20;RIM=0.12;RIM_TINT=0.35;
}
