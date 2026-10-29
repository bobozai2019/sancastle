extends RefCounted
class_name SandcastleWaterRenderProfile

## Strict staging schema. "implemented" means a route is wired in the W07
## prototype, not that its visual or performance acceptance gate has passed.
const CAPABILITIES := ["eta_normals", "screen_optics", "main_foam",
	"fold_caustics", "local_front", "planar_reflection", "shore_contact",
	"foam_splats"]
const RESOURCES := ["water_shader", "terrain_fixed_shader",
	"terrain_coupled_shader", "caustic_pattern"]
const RESOURCES_V8 := ["water_shader", "terrain_fixed_shader",
	"terrain_coupled_shader", "caustic_pattern", "reflection_environment_scene"]
const VISUAL_FIELDS := ["face_normal", "depth_write", "crest_height_m",
	"shallow_extinction_m", "refraction_scale"]
const VISUAL_FIELDS_V2 := ["face_normal", "depth_write", "crest_height_m",
	"shallow_extinction_m", "refraction_scale", "offshore_core",
	"offshore_core_broken"]
const VISUAL_FIELDS_V3 := ["face_normal", "depth_write", "crest_height_m",
	"shallow_extinction_m", "refraction_scale", "offshore_core",
	"offshore_core_broken", "offshore_core_crown"]
const VISUAL_FIELDS_V5 := ["face_normal", "depth_write", "crest_height_m",
	"shallow_extinction_m", "refraction_scale", "offshore_core",
	"offshore_core_broken", "offshore_core_crown", "shallow_preserve"]
const VISUAL_FIELDS_V7 := ["face_normal", "depth_write", "crest_height_m",
	"shallow_extinction_m", "refraction_scale", "offshore_core",
	"offshore_core_broken", "offshore_core_crown", "shallow_preserve",
	"caustic_softness", "caustic_strength", "caustic_uv_scale"]
const VISUAL_FIELDS_V8 := ["face_normal", "depth_write", "crest_height_m",
	"shallow_extinction_m", "refraction_scale", "offshore_core",
	"offshore_core_broken", "offshore_core_crown", "shallow_preserve",
	"caustic_softness", "caustic_strength", "caustic_uv_scale",
	"reflection_strength"]
const TOP_FIELDS := ["profile_id", "schema_version", "phase",
	"target_fixture_ids", "grid_size", "cell_size_m", "sim_hz",
	"render_subdivision", "surface_bias_m", "reference_bed", "resources",
	"visual", "capabilities"]
const TEST1_VISUAL_FIELDS := ["whitewater_gain", "splat_diameter_px"]
const FIXTURES := ["water_render_demo_v2", "water_render_coupled_v2"]


static func load_file(path: String) -> Dictionary:
	if not path.begins_with("res://") or not FileAccess.file_exists(path):
		return _failure("profile_file_missing")
	var source := FileAccess.get_file_as_string(path)
	var parser := JSON.new()
	if parser.parse(source) != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return _failure("profile_json_invalid")
	var result := validate(parser.data)
	if not result.ok:
		return result
	result["source_path"] = path
	result["source_sha256"] = FileAccess.get_sha256(path)
	return result


static func validate(data: Variant) -> Dictionary:
	if typeof(data) != TYPE_DICTIONARY:
		return _failure("profile_shape_invalid")
	var p: Dictionary = data
	var has_test1_visual: bool = p.has("test1_visual")
	if not _exact_keys(p, TOP_FIELDS + ["test1_visual"] if has_test1_visual else TOP_FIELDS):
		return _failure("profile_fields_invalid")
	var is_v1: bool = p.profile_id == "water_render_staging_v1" and \
			_integer_equals(p.schema_version, 1)
	var is_v2: bool = p.profile_id == "water_render_staging_v2" and \
			_integer_equals(p.schema_version, 2)
	var is_v3: bool = p.profile_id == "water_render_staging_v3" and \
			_integer_equals(p.schema_version, 3)
	var is_v4: bool = p.profile_id == "water_render_staging_v4" and \
			_integer_equals(p.schema_version, 4)
	var is_v5: bool = p.profile_id == "water_render_staging_v5" and \
			_integer_equals(p.schema_version, 5)
	var is_v6: bool = p.profile_id == "water_render_staging_v6" and \
			_integer_equals(p.schema_version, 6)
	var is_v7: bool = p.profile_id == "water_render_staging_v7" and \
			_integer_equals(p.schema_version, 7)
	var is_v8: bool = p.profile_id == "water_render_staging_v8" and \
			_integer_equals(p.schema_version, 8)
	if has_test1_visual and not is_v8:
		return _failure("profile_test1_identity_invalid")
	if has_test1_visual:
		if typeof(p.test1_visual) != TYPE_DICTIONARY or \
				not _exact_keys(p.test1_visual, TEST1_VISUAL_FIELDS) or \
				not _number_in_range(p.test1_visual.whitewater_gain, 0.0, 1.0) or \
				not _number_in_range(p.test1_visual.splat_diameter_px, 1.0, 6.0):
			return _failure("profile_test1_visual_invalid")
	var is_v5_plus := is_v5 or is_v6 or is_v7 or is_v8
	if typeof(p.profile_id) != TYPE_STRING or not (is_v1 or is_v2 or is_v3 or is_v4 or is_v5_plus) or \
			p.phase != "staging":
		return _failure("profile_identity_invalid")
	if typeof(p.target_fixture_ids) != TYPE_ARRAY or \
			p.target_fixture_ids.size() != 2 or \
			p.target_fixture_ids[0] != FIXTURES[0] or \
			p.target_fixture_ids[1] != FIXTURES[1]:
		return _failure("profile_fixtures_invalid")
	if not _integer_equals(p.grid_size, 256) or \
			not _number_equals(p.cell_size_m, 0.125) or \
			not _integer_equals(p.sim_hz, 30) or \
			not _integer_equals(p.render_subdivision, 2) or \
			not _number_equals(p.surface_bias_m, 0.003) or \
			p.reference_bed != ("estuary_branched_v1" if (is_v4 or is_v5_plus) else \
			"natural_structured_v1"):
		return _failure("profile_domain_invalid")
	if typeof(p.resources) != TYPE_DICTIONARY or \
			not _exact_keys(p.resources, RESOURCES_V8 if is_v8 else RESOURCES):
		return _failure("profile_resources_invalid")
	for name in RESOURCES_V8 if is_v8 else RESOURCES:
		var path: Variant = p.resources[name]
		if typeof(path) != TYPE_STRING or not path.begins_with("res://") or \
				not ResourceLoader.exists(path):
			return _failure("profile_resource_missing:" + name)
	if (is_v6 or is_v7 or is_v8) and p.resources.terrain_fixed_shader != \
			p.resources.terrain_coupled_shader:
		return _failure("profile_shared_terrain_mismatch")
	var expected_visual: Array = VISUAL_FIELDS_V8 if is_v8 else \
			(VISUAL_FIELDS_V7 if is_v7 else \
			(VISUAL_FIELDS_V5 if is_v5_plus else \
			(VISUAL_FIELDS_V3 if (is_v3 or is_v4) else \
			(VISUAL_FIELDS_V2 if is_v2 else VISUAL_FIELDS))))
	if typeof(p.visual) != TYPE_DICTIONARY or \
			not _exact_keys(p.visual, expected_visual):
		return _failure("profile_visual_invalid")
	if typeof(p.visual.face_normal) != TYPE_BOOL or \
			typeof(p.visual.depth_write) != TYPE_BOOL or \
			not p.visual.depth_write or \
			not _number_in_range(p.visual.crest_height_m, 0.0, 0.25) or \
			not _number_in_range(p.visual.shallow_extinction_m, 0.11, 0.35) or \
			not _number_in_range(p.visual.refraction_scale, 0.0, 0.25):
		return _failure("profile_visual_values_invalid")
	if (is_v2 or is_v3 or is_v4 or is_v5_plus) and (typeof(p.visual.offshore_core) != TYPE_BOOL or \
			typeof(p.visual.offshore_core_broken) != TYPE_BOOL or \
			(p.visual.offshore_core_broken and not p.visual.offshore_core)):
		return _failure("profile_visual_values_invalid")
	if (is_v3 or is_v4 or is_v5_plus) and (typeof(p.visual.offshore_core_crown) != TYPE_BOOL or \
			(p.visual.offshore_core_crown and not p.visual.offshore_core_broken)):
		return _failure("profile_visual_values_invalid")
	if is_v5_plus and typeof(p.visual.shallow_preserve) != TYPE_BOOL:
		return _failure("profile_visual_values_invalid")
	if (is_v7 or is_v8) and (not _number_in_range(p.visual.caustic_softness, 0.0, 1.0) or \
			not _number_in_range(p.visual.caustic_strength, 0.0, 1.0) or \
			not _number_in_range(p.visual.caustic_uv_scale, 0.5, 2.0)):
		return _failure("profile_visual_values_invalid")
	if is_v8 and not _number_in_range(p.visual.reflection_strength, 0.2, 2.0):
		return _failure("profile_visual_values_invalid")
	if typeof(p.capabilities) != TYPE_DICTIONARY or \
			not _exact_keys(p.capabilities, CAPABILITIES):
		return _failure("profile_capabilities_invalid")
	for name in CAPABILITIES:
		var capability: Variant = p.capabilities[name]
		if typeof(capability) != TYPE_DICTIONARY or \
				not _exact_keys(capability, ["status", "enabled"]) or \
				typeof(capability.enabled) != TYPE_BOOL or \
				capability.status not in ["pending", "implemented"]:
			return _failure("profile_capability_invalid:" + name)
		if capability.status == "pending" and capability.enabled:
			return _failure("profile_pending_enabled:" + name)
	if p.capabilities.local_front.enabled != (p.visual.crest_height_m > 0.0) or \
			p.capabilities.screen_optics.enabled != p.visual.face_normal or \
			(p.capabilities.fold_caustics.enabled and \
			not p.capabilities.screen_optics.enabled):
		return _failure("profile_dependency_invalid")
	if (is_v2 or is_v3 or is_v4 or is_v5_plus) and p.visual.offshore_core and \
			not p.capabilities.local_front.enabled:
		return _failure("profile_dependency_invalid")
	if is_v8 and (not p.capabilities.planar_reflection.enabled or \
			not p.capabilities.screen_optics.enabled or \
			not p.resources.reflection_environment_scene.ends_with(".tscn")):
		return _failure("profile_dependency_invalid")
	return {"ok": true, "code": "", "profile": p.duplicate(true)}


static func effective_from_materials(profile: Dictionary, fixture_id: StringName,
		water: ShaderMaterial, terrain: ShaderMaterial,
		render_subdivision: int, visual_time_s: float,
		reference_bed_effective: String = "natural_structured_v1") -> Dictionary:
	var pattern: Texture2D = terrain.get_shader_parameter("caustic_pattern")
	var effective := {
		"profile_id": profile.profile_id,
		"schema_version": profile.schema_version,
		"phase": profile.phase,
		"fixture_id": String(fixture_id),
		"water_shader": water.shader.resource_path,
		"terrain_shader": terrain.shader.resource_path,
		"render_subdivision": render_subdivision,
		"depth_write": water.shader.code.contains("depth_draw_always"),
		"screen_optics": water.get_shader_parameter("prototype_screen_optics"),
		"screen_world_glint": water.get_shader_parameter("prototype_screen_world_glint"),
		"face_normal": water.get_shader_parameter("prototype_screen_face_normal"),
		"screen_abs_fresnel": water.get_shader_parameter("prototype_screen_abs_fresnel"),
		"eta_normals": water.get_shader_parameter("prototype_eta_normals"),
		"main_foam": water.get_shader_parameter("phase2_foam"),
		"crest_broken_core": water.get_shader_parameter("prototype_crest_broken_core"),
		"fold_caustics": terrain.get_shader_parameter("phase2_caustics"),
		"local_front": water.get_shader_parameter("prototype_use_local_front"),
		"crest_height_m": water.get_shader_parameter("prototype_crest_height_m"),
		"shallow_extinction_m": water.get_shader_parameter("prototype_shallow_extinction_m"),
		"refraction_scale": water.get_shader_parameter("prototype_refraction_scale"),
		"caustic_pattern": pattern.resource_path if pattern != null else "",
		"caustic_pattern_width": pattern.get_width() if pattern != null else 0,
		"caustic_pattern_height": pattern.get_height() if pattern != null else 0,
		"surface_bias_m": water.get_shader_parameter("water_surface_bias_m"),
		"visual_time_s": visual_time_s,
	}
	if profile.schema_version >= 2:
		effective["offshore_core"] = water.get_shader_parameter("prototype_offshore_core")
		effective["offshore_core_broken"] = water.get_shader_parameter(
			"prototype_offshore_core_broken")
	if profile.schema_version >= 3:
		effective["offshore_core_crown"] = water.get_shader_parameter(
			"prototype_offshore_core_crown")
	if profile.schema_version >= 4:
		effective["reference_bed"] = reference_bed_effective
	if profile.schema_version >= 5 or water.get_shader_parameter(
			"prototype_optical_shallow_preserve") == true:
		effective["shallow_preserve"] = water.get_shader_parameter(
			"prototype_optical_shallow_preserve")
	if profile.schema_version >= 7:
		effective["caustic_softness"] = terrain.get_shader_parameter(
			"prototype_caustic_softness")
		effective["caustic_strength"] = terrain.get_shader_parameter(
			"prototype_caustic_strength")
		effective["caustic_uv_scale"] = terrain.get_shader_parameter(
			"prototype_caustic_uv_scale")
	if profile.schema_version >= 8:
		var reflection: Texture2D = water.get_shader_parameter(
			"prototype_planar_reflection")
		effective["planar_reflection"] = water.get_shader_parameter(
			"prototype_planar_reflection_enabled")
		effective["reflection_strength"] = water.get_shader_parameter(
			"prototype_screen_sky_reflection_scale")
		effective["reflection_texture_width"] = reflection.get_width() if reflection != null else 0
		effective["reflection_texture_height"] = reflection.get_height() if reflection != null else 0
	return effective


static func effective_matches_request(profile: Dictionary, fixture_id: StringName,
		effective: Dictionary) -> bool:
	var cap: Dictionary = profile.capabilities
	var visual: Dictionary = profile.visual
	var terrain_shader: String = profile.resources.terrain_coupled_shader if \
			fixture_id == &"water_render_coupled_v2" else profile.resources.terrain_fixed_shader
	var base_matches: bool = effective.water_shader == profile.resources.water_shader and \
			effective.terrain_shader == terrain_shader and \
			effective.render_subdivision == profile.render_subdivision and \
			effective.depth_write == visual.depth_write and \
			effective.screen_optics == cap.screen_optics.enabled and \
			effective.get("shallow_preserve", false) == visual.get("shallow_preserve", false) and \
			effective.screen_world_glint == false and \
			effective.face_normal == visual.face_normal and \
			effective.screen_abs_fresnel == visual.face_normal and \
			effective.eta_normals == cap.eta_normals.enabled and \
			effective.main_foam == cap.main_foam.enabled and \
			effective.crest_broken_core == false and \
			effective.fold_caustics == cap.fold_caustics.enabled and \
			effective.local_front == cap.local_front.enabled and \
			is_equal_approx(float(effective.crest_height_m), float(visual.crest_height_m)) and \
			is_equal_approx(float(effective.shallow_extinction_m), float(visual.shallow_extinction_m)) and \
			is_equal_approx(float(effective.refraction_scale), float(visual.refraction_scale)) and \
			is_equal_approx(float(effective.surface_bias_m), float(profile.surface_bias_m)) and \
			effective.caustic_pattern == profile.resources.caustic_pattern and \
			effective.caustic_pattern_width == 1024 and \
			effective.caustic_pattern_height == 1024
	if not base_matches:
		return false
	if profile.schema_version >= 2:
		if effective.get("offshore_core") != visual.offshore_core or \
				effective.get("offshore_core_broken") != visual.offshore_core_broken:
			return false
	if profile.schema_version >= 3:
		if effective.get("offshore_core_crown") != visual.offshore_core_crown:
			return false
	if profile.schema_version >= 4:
		if effective.get("reference_bed") != profile.reference_bed:
			return false
	if profile.schema_version >= 5 and \
			effective.get("shallow_preserve") != visual.shallow_preserve:
		return false
	if profile.schema_version >= 7:
		var caustics_match := is_equal_approx(float(effective.get("caustic_softness", -1.0)),
			float(visual.caustic_softness)) and \
			is_equal_approx(float(effective.get("caustic_strength", -1.0)),
				float(visual.caustic_strength)) and \
			is_equal_approx(float(effective.get("caustic_uv_scale", -1.0)),
				float(visual.caustic_uv_scale))
		if not caustics_match:
			return false
	if profile.schema_version >= 8:
		return effective.get("planar_reflection") == cap.planar_reflection.enabled and \
			is_equal_approx(float(effective.get("reflection_strength", -1.0)),
				float(visual.reflection_strength)) and \
			effective.get("reflection_texture_width") == 960 and \
			effective.get("reflection_texture_height") == 540
	return true


static func _exact_keys(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size():
		return false
	for key in expected:
		if not value.has(key):
			return false
	return true


static func _integer_equals(value: Variant, expected: int) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and \
			float(value) == float(expected)


static func _number_equals(value: Variant, expected: float) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and \
			is_equal_approx(float(value), expected)


static func _number_in_range(value: Variant, minimum: float, maximum: float) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and \
			float(value) >= minimum and float(value) <= maximum


static func _failure(code: String) -> Dictionary:
	return {"ok": false, "code": code, "profile": {}}
