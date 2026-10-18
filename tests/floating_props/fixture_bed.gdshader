shader_type spatial;
uniform sampler2D rock_state : filter_nearest, repeat_disable;
uniform sampler2D sand_state : filter_nearest, repeat_disable;
uniform sampler2D water_state : filter_nearest, repeat_disable;
void vertex(){
 vec2 state_uv=VERTEX.xz/32.0+0.5;
 VERTEX.y=textureLod(rock_state,state_uv,0.0).r+textureLod(sand_state,state_uv,0.0).r;
}
void fragment(){
 ALBEDO=vec3(0.64,0.52,0.34);
 ROUGHNESS=0.9;
}
