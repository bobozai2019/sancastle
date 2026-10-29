shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

// Lightweight editor-only water. Gameplay water uses gpu_water.gdshader and
// simulation textures; this shader exists so art-direction parameters are
// visible immediately in the editor viewport.
uniform vec4 water_color : source_color = vec4(0.04, 0.72, 0.69, 0.68);
uniform vec4 deep_water_color : source_color = vec4(0.02, 0.29, 0.37, 0.94);
uniform float preview_depth_m : hint_range(0.001, 1.0, 0.005) = 0.10;
uniform vec3 output_color_bias = vec3(0.0);
uniform float visual_time_s = 6.0;
uniform float wave_height_m : hint_range(0.0, 0.5, 0.005) = 0.08;
uniform float wave_frequency : hint_range(0.05, 4.0, 0.05) = 0.6;
uniform float wave_speed : hint_range(-4.0, 4.0, 0.05) = 0.7;
uniform vec2 trigger_origin_m = vec2(-8.0, 0.0);
uniform float trigger_height_m : hint_range(0.0, 1.5, 0.01) = 0.35;
uniform float trigger_age_s = -1.0;
uniform float trigger_speed_m_s : hint_range(0.5, 12.0, 0.1) = 4.0;

varying float displayed_depth_m;
varying vec2 preview_uv;
varying float trigger_crest;

void vertex() {
	// Runtime maps the full 32 m domain to UV * 32. Using world metres here
	// keeps detail scale stable when the preview water covers only part of it.
	preview_uv = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz + vec2(16.0);
	float wave_a = sin(VERTEX.x * wave_frequency + TIME * wave_speed);
	float wave_b = cos(VERTEX.z * wave_frequency * 0.83 - TIME * wave_speed * 0.71);
	float displacement = (wave_a + wave_b) * wave_height_m * 0.5;
	trigger_crest = 0.0;
	if (trigger_age_s >= 0.0) {
		float distance_m = length(VERTEX.xz - trigger_origin_m);
		float front_m = trigger_age_s * trigger_speed_m_s;
		float front_offset = (distance_m - front_m) * 1.8;
		float envelope = exp(-front_offset * front_offset) *
			exp(-trigger_age_s * 0.35);
		trigger_crest = (0.5 + 0.5 * sin((distance_m - front_m) * 5.5)) * envelope;
		displacement += trigger_crest * trigger_height_m * 0.08;
	}
	VERTEX.y += displacement;
	displayed_depth_m = max(preview_depth_m + displacement, 0.001);
}

void fragment() {
	// Match gpu_water.gdshader's phase-2 absorption and reflection equations so
	// editor art direction and triggered runtime water share the same palette.
	float transmission = exp(-displayed_depth_m / 0.11);
	float depth_fraction = 1.0 - transmission;
	vec3 scatter = mix(water_color.rgb, deep_water_color.rgb,
		smoothstep(0.02, 0.30, displayed_depth_m));
	float t = visual_time_s >= 0.0 ? visual_time_s : TIME;
	float attenuation = smoothstep(0.008, 0.065, displayed_depth_m);
	vec2 flow_direction = vec2(1.0, 0.0);
	vec2 detail = vec2(
		sin(preview_uv.x * 3.1 + preview_uv.y * 1.7 - t * 1.2),
		cos(preview_uv.y * 2.8 - preview_uv.x * 1.4 - t * 0.9)) *
		0.075 * attenuation;
	detail += flow_direction * sin(dot(preview_uv, flow_direction) * 7.0 -
		t * 2.0) * 0.025 * attenuation;
	vec3 n = normalize(vec3(detail.x, detail.y, 1.0));
	float fresnel = pow(1.0 - clamp(dot(normalize(VIEW), n), 0.0, 1.0), 5.0);
	float reflection = 0.04 + 0.34 * fresnel;
	float glint = pow(max(0.0, dot(n,
		normalize(vec3(-0.10, 0.10, 0.99)))), 28.0) * 0.12 * attenuation;
	ALBEDO = clamp(mix(scatter, vec3(0.53, 0.78, 0.79), reflection) +
		vec3(glint) + output_color_bias, vec3(0.0), vec3(1.0));
	ALBEDO = mix(ALBEDO, vec3(0.95, 1.0, 1.0), trigger_crest);
	ALPHA = clamp(depth_fraction * (1.0 - reflection) + reflection * 0.75,
		0.0, 0.95) * smoothstep(0.001, 0.018, displayed_depth_m) *
		(water_color.a / 0.68);
	ALPHA = mix(ALPHA, 0.96, trigger_crest * 0.8);
}
