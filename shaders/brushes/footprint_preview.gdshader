shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, world_vertex_coords;
uniform sampler2D rock_state : filter_nearest, repeat_disable;
uniform sampler2D sand_state : filter_nearest, repeat_disable;
uniform sampler2D stroke_baseline : filter_nearest, repeat_disable;
uniform bool use_stroke_baseline = false;
uniform int operation = 2;
uniform vec2 start_xz;
uniform vec2 end_xz;
uniform float height_m = 0.3;
uniform float bottom_width_m = 1.0;
uniform float top_width_m = 0.5;
uniform float trench_width_m = 0.5;
uniform float depth_m = 0.15;
uniform float shoulder_width_m = 0.5;
uniform vec4 tint : source_color = vec4(0.25, 1.0, 0.55, 0.45);
varying vec2 point;
float distance_to_path(vec2 pos){vec2 ab=end_xz-start_xz;float t=dot(ab,ab)>1e-12?clamp(dot(pos-start_xz,ab)/dot(ab,ab),0.0,1.0):0.0;return length(pos-(start_xz+ab*t));}
void vertex(){
 point=VERTEX.xz;vec2 uv=(point+16.0)/32.0;
 float rock=textureLod(rock_state,uv,0.0).r,bed=rock+textureLod(sand_state,uv,0.0).r;
 float base=use_stroke_baseline?textureLod(stroke_baseline,uv,0.0).r:bed;
 float d=distance_to_path(point);bool moving=dot(end_xz-start_xz,end_xz-start_xz)>1e-12;
 if(moving&&operation==2){float inner=top_width_m*0.5,outer=bottom_width_m*0.5;float f=d<=inner?1.0:clamp((outer-d)/max(outer-inner,1e-8),0.0,1.0);bed=max(bed,base+height_m*f);}
 // The cut mask stays above the visible bed so the uncut surface cannot
 // occlude the prospective trench. Color encodes the actual parabolic mask.
 VERTEX.y=bed+0.025;
}
void fragment(){
 float d=distance_to_path(point),outer=operation==2?bottom_width_m*0.5:trench_width_m*0.5+shoulder_width_m;
 vec3 color=tint.rgb;
 if(operation==3&&tint.g>tint.r){
  float r=trench_width_m*0.5;vec2 ab=end_xz-start_xz;float side=ab.x*(point.y-start_xz.y)-ab.y*(point.x-start_xz.x);
  color=d<r?mix(vec3(1.0,0.65,0.2),vec3(1.0,0.2,0.15),max(0.0,1.0-d*d/(r*r))):(side>=0.0?vec3(0.15,0.8,1.0):vec3(0.15,0.45,1.0));
 }
 ALBEDO=color;ALPHA=tint.a*step(d,outer);
}
