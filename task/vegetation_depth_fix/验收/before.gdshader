shader_type spatial;
render_mode cull_back;

uniform sampler2D vegetation_roots : filter_nearest, repeat_disable;
uniform sampler2D vegetation_motion : filter_nearest, repeat_disable;
uniform sampler2D async_clock : filter_nearest, repeat_disable;
uniform sampler2D water_state : filter_nearest, repeat_disable;
// Original RGB + packed depth atlas. Alpha is NOT ordinary opacity.
uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float atlas_grid = 12.0;
uniform vec4 pivot_offset;
uniform int kind = 0;
uniform uint seed = 62143u;
varying vec3 proxy_position;
varying vec3 local_camera;
varying vec4 root_state;
varying vec2 flow_bend;
varying float yaw;
varying float plant_scale;
varying float plant_tint;
varying float living;
varying mat4 object_to_world;

uint hash32(uint v){v^=v>>16u;v*=0x7feb352du;v^=v>>15u;v*=0x846ca68bu;return v^(v>>16u);}
float random01(uint v){return float(hash32(v)>>8u)/16777216.0;}
mat3 rotation(float angle){return mat3(vec3(cos(angle),0.0,sin(angle)),vec3(0,1,0),vec3(-sin(angle),0.0,cos(angle)));}
void vertex(){
 object_to_world=MODEL_MATRIX;
 int id=INSTANCE_ID+kind*2048;ivec2 at=ivec2(id%128,id/128);
 root_state=texelFetch(vegetation_roots,at,0);flow_bend=texelFetch(vegetation_motion,at,0).xy;
 living=step(0.0001,root_state.w);uint rng=seed+uint(id)*0x9e3779b9u;
 float clock=texelFetch(async_clock,ivec2(0),0).r;
 float t=clamp((clock-random01(rng+17u)*0.25)*3.0,0.0,1.0)-1.0;
 float growth=0.25+0.75*(1.0+2.70158*t*t*t+1.70158*t*t);
 yaw=random01(rng+31u)*6.2831853;mat3 turn=rotation(yaw);
 plant_scale=max(root_state.w*growth,0.0001);proxy_position=VERTEX;
 vec3 local=turn*(VERTEX*plant_scale);local.xz+=flow_bend*VERTEX.y*plant_scale;
 VERTEX=local+root_state.xyz;
 vec3 n=turn*NORMAL;n.y-=dot(flow_bend,n.xz);NORMAL=normalize(n);
 vec3 relative=(inverse(MODEL_MATRIX)*vec4(CAMERA_POSITION_WORLD,1.0)).xyz-root_state.xyz;
 relative.xz-=flow_bend*relative.y;
 local_camera=transpose(turn)*relative/plant_scale;
 if(living<0.5)VERTEX=vec3(0.0,-50.0,0.0);
 plant_tint=random01(rng+47u);
}
vec3 decode_direction(vec2 frame){
 vec2 p=frame/(atlas_grid-1.0)*2.0-1.0;
 vec2 xz=vec2(p.x+p.y,p.x-p.y)*0.5;
 return normalize(vec3(xz.x,1.0-abs(xz.x)-abs(xz.y),xz.y));
}
vec4 sample_frame(vec2 frame,vec3 ray,out float surface_t){
 vec3 n=decode_direction(frame);vec3 center=pivot_offset.xyz/pivot_offset.w;
 vec3 right=normalize(vec3(-n.z,0.0,n.x)+vec3(0.000001,0.0,0.0));
 vec3 up=cross(right,n);
 float denominator=dot(n,ray);
 float plane_t=dot(n,center-local_camera)/min(denominator,-0.0001);
 vec3 q=local_camera+ray*plane_t-center;
 vec2 uv=vec2(dot(right,q),dot(up,q))*pivot_offset.w+0.5;
 vec2 inset=0.5/vec2(textureSize(atlas,0))*atlas_grid;
 vec2 packed_uv=(frame+clamp(uv,inset,vec2(1.0)-inset))/atlas_grid;
 vec4 pixel=texture(atlas,vec2(packed_uv.x,1.0-packed_uv.y));
 float inside=step(0.0,uv.x)*step(uv.x,1.0)*step(0.0,uv.y)*step(uv.y,1.0);
 // The source PS uses smoothstep(0,0.4,packed_depth) for coverage.
 float coverage=smoothstep(0.0,0.4,pixel.a)*inside;
 surface_t=plane_t+(0.5-pixel.a)/(pivot_offset.w*min(denominator,-0.0001));
 return vec4(pixel.rgb,coverage);
}
void fragment(){
 if(living<0.5)discard;
 vec3 center=pivot_offset.xyz/pivot_offset.w;
 vec3 direction=normalize(local_camera-center);
 vec2 oct=direction.xz/(abs(direction.x)+abs(direction.y)+abs(direction.z));
 vec2 grid=clamp((vec2(oct.x+oct.y,oct.x-oct.y)*0.5+0.5)*(atlas_grid-1.0),vec2(0.0),vec2(atlas_grid-1.001));
 vec2 lo=floor(grid);vec2 f=fract(grid);
 vec2 middle=lo+(f.x>f.y?vec2(1,0):vec2(0,1));
 vec3 weights=vec3(1.0-max(f.x,f.y),abs(f.x-f.y),min(f.x,f.y));
 vec3 ray=normalize(proxy_position-local_camera);
 float da;float db;float dc;
 vec4 a=sample_frame(lo,ray,da),b=sample_frame(middle,ray,db),c=sample_frame(lo+vec2(1),ray,dc);
 vec4 result=a*weights.x+b*weights.y+c*weights.z;
 if(result.a<0.5)discard;
 float distance_on_ray=da*weights.x+db*weights.y+dc*weights.z;
 vec3 surface=local_camera+ray*distance_on_ray;
 vec3 actual=rotation(yaw)*(surface*plant_scale);actual.xz+=flow_bend*surface.y*plant_scale;
 actual+=root_state.xyz;
 vec4 clip=PROJECTION_MATRIX*VIEW_MATRIX*object_to_world*vec4(actual,1.0);
 DEPTH=clamp(clip.z/clip.w,0.0,1.0);
 if(!FRONT_FACING)NORMAL=-NORMAL;
 ALBEDO=result.rgb*mix(0.9,1.08,plant_tint);ROUGHNESS=0.88;SPECULAR=0.16;
}
