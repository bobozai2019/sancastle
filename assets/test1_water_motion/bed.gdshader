shader_type spatial;
render_mode cull_disabled;
uniform sampler2D water_field : filter_linear,repeat_disable;
varying vec3 world;
void vertex() {
 vec2 e=vec2(1.0/512.0,1.0/256.0);
 VERTEX.y=texture(water_field,UV).w;
 float dx=(texture(water_field,UV+vec2(e.x,0)).w-texture(water_field,UV-vec2(e.x,0)).w)/0.1171875;
 float dz=(texture(water_field,UV+vec2(0,e.y)).w-texture(water_field,UV-vec2(0,e.y)).w)/0.1171875;
 NORMAL=normalize(vec3(-dx,1.0,dz));world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
}
void fragment() {
 float h=max(texture(water_field,UV).z-0.05,0.0);
 float grain=fract(sin(dot(floor(world.xz*280.0),vec2(12.9898,78.233)))*43758.5453);
 ALBEDO=mix(vec3(.78,.65,.43),vec3(.56,.46,.28),smoothstep(0.0,0.03,h))*(.9+.2*grain);
 ROUGHNESS=.9;
}
