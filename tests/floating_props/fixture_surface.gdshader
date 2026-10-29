shader_type spatial;
uniform sampler2D rock_state : filter_linear, repeat_disable;
uniform sampler2D sand_state : filter_linear, repeat_disable;
uniform sampler2D water_state : filter_linear, repeat_disable;
uniform bool show_water = false;
varying vec2 state_uv;
void vertex(){
 state_uv=VERTEX.xz/32.0+0.5;
 VERTEX.y=textureLod(rock_state,state_uv,0.0).r+textureLod(sand_state,state_uv,0.0).r;
 if(show_water)VERTEX.y+=textureLod(water_state,state_uv,0.0).r;
}
void fragment(){
 if(show_water && texture(water_state,state_uv).r<=0.001)discard;
 ALBEDO=show_water?vec3(0.08,0.42,0.56):vec3(0.64,0.52,0.34);
 ROUGHNESS=show_water?0.3:0.9;
 ALPHA=show_water?0.55:1.0;
}
