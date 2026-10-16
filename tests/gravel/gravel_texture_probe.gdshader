shader_type spatial;
uniform sampler2D particle_state : filter_nearest, repeat_disable;
void vertex() {
	vec4 state = texelFetch(particle_state, ivec2(INSTANCE_ID % 64, INSTANCE_ID / 64), 0);
	VERTEX += state.xyz;
}
void fragment() {
	ALBEDO = vec3(0.48, 0.27, 0.12);
	ROUGHNESS = 0.85;
}
