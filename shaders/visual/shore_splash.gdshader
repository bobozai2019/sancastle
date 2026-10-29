shader_type spatial;
render_mode skip_vertex_transform, cull_disabled, blend_mix, depth_draw_never, specular_disabled;
uniform sampler2D splash_position : filter_nearest, repeat_disable;
uniform sampler2D splash_velocity : filter_nearest, repeat_disable;
uniform bool splash_visible = true;
uniform float splash_size = 1.0;
varying float particle_alpha;

void vertex(){
 int id=INSTANCE_ID;ivec2 at=ivec2(id%64,id/64);
 vec4 p=texelFetch(splash_position,at,0),v=texelFetch(splash_velocity,at,0);
 float life=clamp(p.w/max(v.w,0.001),0.0,1.0);
 particle_alpha=splash_visible&&p.w>0.0?smoothstep(0.0,0.16,life)*(1.0-smoothstep(0.88,1.0,life)):0.0;
 vec3 center=(VIEW_MATRIX*MODEL_MATRIX*vec4(p.xyz,1.0)).xyz;
 vec3 speed=(VIEW_MATRIX*MODEL_MATRIX*vec4(v.xyz,0.0)).xyz;
 vec2 up=length(speed.xy)>0.05?normalize(speed.xy):vec2(0.0,1.0);
 vec2 side=vec2(up.y,-up.x);
 float variation=fract(sin(float(id)*127.1)*43758.5453);
 float width=mix(0.025,0.055,variation)*splash_size;
 float height=width*(1.8+min(length(speed),2.5)*0.85);
 VERTEX=particle_alpha>0.0?center+vec3(side*VERTEX.x*width+up*VERTEX.y*height,0.0):vec3(0.0,0.0,10000.0);
 NORMAL=normalize((VIEW_MATRIX*vec4(0.0,1.0,0.0,0.0)).xyz);
}
void fragment(){
 float radius=length((UV-vec2(0.5))*2.0);
 ALPHA=(1.0-smoothstep(0.35,1.0,radius))*particle_alpha*0.72;
 if(ALPHA<0.025)discard;
 vec3 tint=vec3(0.84,0.94,0.97);
 ALBEDO=tint*0.65;EMISSION=tint*0.35;ROUGHNESS=1.0;SPECULAR=0.0;
}
