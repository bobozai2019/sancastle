extends SceneTree

const Profile = preload("res://scripts/visual/water_render_profile.gd")
const PROFILE_PATH := "res://tests/visual_water_alignment/prototypes/water_render_staging_v1.json"
const PROFILE_PATH_V2 := "res://tests/visual_water_alignment/prototypes/water_render_staging_v2.json"
const PROFILE_PATH_V3 := "res://tests/visual_water_alignment/prototypes/water_render_staging_v3.json"
const PROFILE_PATH_V4 := "res://tests/visual_water_alignment/prototypes/water_render_staging_v4.json"
const PROFILE_PATH_V5 := "res://tests/visual_water_alignment/prototypes/water_render_staging_v5.json"
const PROFILE_PATH_V6 := "res://tests/visual_water_alignment/prototypes/water_render_staging_v6.json"
const PROFILE_PATH_V7 := "res://tests/visual_water_alignment/prototypes/water_render_staging_v7.json"
const PROFILE_PATH_V8 := "res://tests/visual_water_alignment/prototypes/water_render_staging_v8.json"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var loaded: Dictionary = Profile.load_file(PROFILE_PATH)
	if not loaded.get("ok", false):
		_fail("valid profile rejected: " + str(loaded.get("code", "")))
		return
	var source: Dictionary = loaded.profile
	var loaded_v2: Dictionary = Profile.load_file(PROFILE_PATH_V2)
	if not loaded_v2.get("ok", false):
		_fail("valid v2 profile rejected: " + str(loaded_v2.get("code", "")))
		return
	var invalid_v2: Dictionary = loaded_v2.profile.duplicate(true)
	invalid_v2.visual["offshore_core"] = false
	if not _rejects(invalid_v2, "profile_visual_values_invalid"):
		return
	var loaded_v3: Dictionary = Profile.load_file(PROFILE_PATH_V3)
	if not loaded_v3.get("ok", false):
		_fail("valid v3 profile rejected: " + str(loaded_v3.get("code", "")))
		return
	var invalid_v3: Dictionary = loaded_v3.profile.duplicate(true)
	invalid_v3.visual["offshore_core_broken"] = false
	if not _rejects(invalid_v3, "profile_visual_values_invalid"):
		return
	var loaded_v4: Dictionary = Profile.load_file(PROFILE_PATH_V4)
	if not loaded_v4.get("ok", false):
		_fail("valid v4 profile rejected: " + str(loaded_v4.get("code", "")))
		return
	var invalid_v4: Dictionary = loaded_v4.profile.duplicate(true)
	invalid_v4.reference_bed = "natural_structured_v1"
	if not _rejects(invalid_v4, "profile_domain_invalid"):
		return
	var loaded_v5: Dictionary = Profile.load_file(PROFILE_PATH_V5)
	if not loaded_v5.get("ok", false):
		_fail("valid v5 profile rejected: " + str(loaded_v5.get("code", "")))
		return
	var invalid_v5: Dictionary = loaded_v5.profile.duplicate(true)
	invalid_v5.visual["shallow_preserve"] = "true"
	if not _rejects(invalid_v5, "profile_visual_values_invalid"):
		return
	invalid_v5 = loaded_v5.profile.duplicate(true)
	invalid_v5.visual.erase("shallow_preserve")
	if not _rejects(invalid_v5, "profile_visual_invalid"):
		return
	var loaded_v6: Dictionary = Profile.load_file(PROFILE_PATH_V6)
	if not loaded_v6.get("ok", false):
		_fail("valid v6 profile rejected: " + str(loaded_v6.get("code", "")))
		return
	var invalid_v6: Dictionary = loaded_v6.profile.duplicate(true)
	invalid_v6.resources["terrain_fixed_shader"] = \
		"res://tests/visual_water_alignment/prototypes/reference_terrain.gdshader"
	if not _rejects(invalid_v6, "profile_shared_terrain_mismatch"):
		return
	invalid_v6 = loaded_v6.profile.duplicate(true)
	invalid_v6.visual.erase("shallow_preserve")
	if not _rejects(invalid_v6, "profile_visual_invalid"):
		return
	invalid_v6 = loaded_v6.profile.duplicate(true)
	invalid_v6.schema_version = 5
	if not _rejects(invalid_v6, "profile_identity_invalid"):
		return
	var loaded_v7: Dictionary = Profile.load_file(PROFILE_PATH_V7)
	if not loaded_v7.get("ok", false):
		_fail("valid v7 profile rejected: " + str(loaded_v7.get("code", "")))
		return
	for field in ["caustic_softness", "caustic_strength", "caustic_uv_scale"]:
		var missing_v7: Dictionary = loaded_v7.profile.duplicate(true)
		missing_v7.visual.erase(field)
		if not _rejects(missing_v7, "profile_visual_invalid"):
			return
	var invalid_v7: Dictionary = loaded_v7.profile.duplicate(true)
	invalid_v7.visual.caustic_softness = 2.0
	if not _rejects(invalid_v7, "profile_visual_values_invalid"):
		return
	invalid_v7 = loaded_v7.profile.duplicate(true)
	invalid_v7.resources.terrain_fixed_shader = \
		"res://tests/visual_water_alignment/prototypes/reference_terrain.gdshader"
	if not _rejects(invalid_v7, "profile_shared_terrain_mismatch"):
		return
	var loaded_v8: Dictionary = Profile.load_file(PROFILE_PATH_V8)
	if not loaded_v8.get("ok", false):
		_fail("valid v8 profile rejected: " + str(loaded_v8.get("code", "")))
		return
	var invalid_v8: Dictionary = loaded_v8.profile.duplicate(true)
	invalid_v8.visual.erase("reflection_strength")
	if not _rejects(invalid_v8, "profile_visual_invalid"):
		return
	invalid_v8 = loaded_v8.profile.duplicate(true)
	invalid_v8.visual.reflection_strength = 0.0
	if not _rejects(invalid_v8, "profile_visual_values_invalid"):
		return
	invalid_v8 = loaded_v8.profile.duplicate(true)
	invalid_v8.resources.reflection_environment_scene = "res://missing_reflection_scene.tscn"
	if not _rejects(invalid_v8, "profile_resource_missing:reflection_environment_scene"):
		return
	invalid_v8 = loaded_v8.profile.duplicate(true)
	invalid_v8.capabilities.planar_reflection.enabled = false
	if not _rejects(invalid_v8, "profile_dependency_invalid"):
		return
	invalid_v8 = loaded_v8.profile.duplicate(true)
	invalid_v8.schema_version = 7
	if not _rejects(invalid_v8, "profile_identity_invalid"):
		return
	if String(loaded.source_sha256).length() != 64:
		_fail("source hash missing")
		return
	var cases := {
		"profile_identity_invalid": {"schema_version": 2},
		"profile_domain_invalid": {"grid_size": 128},
		"profile_fields_invalid": {"unexpected": true},
	}
	for expected_code in cases:
		var invalid: Dictionary = source.duplicate(true)
		invalid.merge(cases[expected_code], true)
		if not _rejects(invalid, expected_code):
			return
	var missing_resource: Dictionary = source.duplicate(true)
	missing_resource.resources["caustic_pattern"] = "res://missing_pattern.png"
	if not _rejects(missing_resource, "profile_resource_missing:caustic_pattern"):
		return
	var pending_enabled: Dictionary = source.duplicate(true)
	pending_enabled.capabilities.planar_reflection["enabled"] = true
	if not _rejects(pending_enabled, "profile_pending_enabled:planar_reflection"):
		return
	var invalid_visual: Dictionary = source.duplicate(true)
	invalid_visual.visual["shallow_extinction_m"] = 0.5
	if not _rejects(invalid_visual, "profile_visual_values_invalid"):
		return
	var drifted_bias: Dictionary = source.duplicate(true)
	drifted_bias.surface_bias_m = 0.006
	if not _rejects(drifted_bias, "profile_domain_invalid"):
		return
	var invalid_dependency: Dictionary = source.duplicate(true)
	invalid_dependency.visual["face_normal"] = false
	if not _rejects(invalid_dependency, "profile_dependency_invalid"):
		return
	var missing_field: Dictionary = source.duplicate(true)
	missing_field.erase("sim_hz")
	if not _rejects(missing_field, "profile_fields_invalid"):
		return
	print("PASS: staging v1–v8 profiles valid and 27 invalid cases rejected sha256=" +
		String(loaded.source_sha256))
	quit(0)


func _rejects(value: Dictionary, code: String) -> bool:
	var result: Dictionary = Profile.validate(value)
	if result.get("ok", true) or result.get("code", "") != code:
		_fail("expected %s got %s" % [code, result])
		return false
	return true


func _fail(message: String) -> void:
	push_error("FAIL: staging profile " + message)
	quit(1)
