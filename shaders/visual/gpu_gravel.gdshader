shader_type spatial;
uniform sampler2D particle_state : filter_nearest, repeat_disable;
uniform uint seed = 57849u;
uniform float radius_min_m = 0.02;
uniform float radius_max_m = 0.05;
varying float stone_color;
uint hash32(uint v) {
	v ^= v >> 16u; v *= 0x7feb352du; v ^= v >> 15u;
	v *= 0x846ca68bu; return v ^ (v >> 16u);
}
float random01(uint v) { return float(hash32(v) >> 8u) / 16777216.0; }
void vertex() {
	uint id = uint(INSTANCE_ID);
	vec4 state = texelFetch(particle_state, ivec2(INSTANCE_ID % 64, INSTANCE_ID / 64), 0);
	float radius = mix(radius_min_m, radius_max_m, random01(id + seed + 0x165667b1u));
	vec3 scale = vec3(radius, radius * 0.6, radius * 0.85);
	float angle = random01(id + seed + 0x27d4eb2du) * 6.2831853;
	mat3 turn = mat3(vec3(cos(angle),0.0,sin(angle)),vec3(0.0,1.0,0.0),vec3(-sin(angle),0.0,cos(angle)));
	VERTEX = turn * ((VERTEX + vec3(0.0,1.0,0.0)) * scale) + state.xyz;
	NORMAL = normalize(turn * (NORMAL / scale));
	stone_color = random01(id + seed + 0xd3a2646cu);
}
void fragment() {
	ALBEDO = mix(vec3(0.18,0.15,0.12),vec3(0.48,0.43,0.34),stone_color);
	ROUGHNESS = 0.9;
}
