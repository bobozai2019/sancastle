extends "res://scripts/visual/test1_beach_fixed_entry.gd"

@export_file("*.json") var candidate_profile_path := "res://assets/water_material_natural_candidate/texture_layers.json"
var candidate_profile := {}
var effective_candidate := {}
var candidate_error := ""

func _ready() -> void:
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(candidate_profile_path)) != OK or not json.data is Dictionary:
		_reject("invalid_candidate_profile")
		return
	candidate_profile = json.data
	if not _keys(candidate_profile, ["candidate_schema_version", "profile_id", "base_profile", "base_profile_sha256", "normal_detail", "cost_budget", "deferred_interfaces"]) or candidate_profile.get("candidate_schema_version") != 1 or candidate_profile.get("profile_id") != "water_material_natural_v1":
		_reject("invalid_candidate_profile")
		return
	if not _resource_path(candidate_profile.base_profile) or typeof(candidate_profile.base_profile_sha256) != TYPE_STRING or FileAccess.get_sha256(candidate_profile.base_profile) != candidate_profile.base_profile_sha256:
		_reject("resource_hash_mismatch")
		return
	if not candidate_profile.normal_detail is Dictionary:
		_reject("invalid_normal_fields")
		return
	var n: Dictionary = candidate_profile.normal_detail
	if not _keys(n, ["mode", "texture", "texture_sha256", "layers", "channels", "sampler"]):
		_reject("invalid_normal_fields")
		return
	if n.mode not in ["off", "legacy_sine", "texture_layers"] or not n.layers is Array or n.layers.size() != 2 or n.channels != "raw_rg_signed_xz" or n.sampler != "linear_mipmap_repeat_no_srgb":
		_reject("invalid_normal_decode")
		return
	if not _resource_path(n.texture) or typeof(n.texture_sha256) != TYPE_STRING or FileAccess.get_sha256(n.texture) != n.texture_sha256:
		_reject("missing_normal_resource_or_hash_mismatch")
		return
	for layer in n.layers:
		if not layer is Dictionary or not _keys(layer, ["scale_per_m", "direction_xz", "speed_m_s", "gain"]) or not layer.direction_xz is Array or layer.direction_xz.size() != 2:
			_reject("invalid_normal_layer")
			return
		if not _number(layer.direction_xz[0], -1.0, 1.0) or not _number(layer.direction_xz[1], -1.0, 1.0) or not _number(layer.gain, 0.0, 0.5) or not _number(layer.scale_per_m, 0.001, 4.0) or not _number(layer.speed_m_s, -2.0, 2.0):
			_reject("invalid_normal_layer")
			return
		var d := Vector2(float(layer.direction_xz[0]), float(layer.direction_xz[1]))
		if absf(d.length_squared() - 1.0) > 0.0001:
			_reject("invalid_normal_layer")
			return
	if not candidate_profile.cost_budget is Dictionary:
		_reject("invalid_candidate_budget_or_deferred")
		return
	var budget: Dictionary = candidate_profile.cost_budget
	if not _keys(budget, ["median_frame_relative_max", "p95_frame_relative_max", "window_s", "viewport_px"]) or not _number(budget.median_frame_relative_max, 1.10, 1.10) or not _number(budget.p95_frame_relative_max, 1.15, 1.15) or not _number(budget.window_s, 60.0, 60.0) or not budget.viewport_px is Array or budget.viewport_px.size() != 2:
		_reject("invalid_candidate_budget_or_deferred")
		return
	if not _number(budget.viewport_px[0], 1920.0, 1920.0) or not _number(budget.viewport_px[1], 1080.0, 1080.0) or candidate_profile.deferred_interfaces != ["lighting", "optics", "foam", "reflection", "caustics"]:
		_reject("invalid_candidate_budget_or_deferred")
		return
	var derived: Variant = JSON.parse_string(FileAccess.get_file_as_string(_candidate_base_profile_path()))
	var expected: Variant = JSON.parse_string(FileAccess.get_file_as_string(candidate_profile.base_profile))
	if not expected is Dictionary or not derived is Dictionary:
		_reject("invalid_derived_base")
		return
	expected.resources.water_shader = _candidate_water_shader_path()
	_candidate_apply_expected_visual_paths(expected)
	if expected != derived:
		_reject("derived_base_changes_nonvisual_inputs")
		return
	render_profile_path = _candidate_base_profile_path()
	super._ready()

func _configure_scene() -> void:
	super._configure_scene()
	var n: Dictionary = candidate_profile.normal_detail
	water_material.set_shader_parameter("natural_normal_mode", ["off", "legacy_sine", "texture_layers"].find(n.mode))
	water_material.set_shader_parameter("use_detail_normals", n.mode != "off")
	water_material.set_shader_parameter("natural_normal_texture", load(n.texture))
	for i in range(2):
		var layer: Dictionary = n.layers[i]
		water_material.set_shader_parameter("natural_layer%d" % i, Vector4(layer.scale_per_m, layer.speed_m_s, layer.gain, 0.0))
		water_material.set_shader_parameter("natural_direction%d" % i, Vector2(layer.direction_xz[0], layer.direction_xz[1]))

func _seal_test1_effective_profile() -> void:
	super._seal_test1_effective_profile()
	var n: Dictionary = candidate_profile.normal_detail
	effective_candidate = {"candidate_schema_version": 1, "profile_id": candidate_profile.profile_id,
		"source_sha256": _candidate_digest(candidate_profile_path), "mode": n.mode,
		"normal_mode_uniform": water_material.get_shader_parameter("natural_normal_mode"),
		"detail_enabled": water_material.get_shader_parameter("use_detail_normals"),
		"texture": n.texture, "texture_sha256": _candidate_digest(n.texture),
		"layer0": str(water_material.get_shader_parameter("natural_layer0")),
		"layer1": str(water_material.get_shader_parameter("natural_layer1")),
		"direction0": str(water_material.get_shader_parameter("natural_direction0")),
		"direction1": str(water_material.get_shader_parameter("natural_direction1")),
		"shader": water_material.shader.resource_path, "visual_time_s": visual_time_s}

func _reject(code: String) -> void:
	candidate_error = code
	last_error = code
	push_error(code)

func _keys(value: Dictionary, names: Array) -> bool:
	if value.size() != names.size(): return false
	for name in names:
		if not value.has(name): return false
	return true

func _number(value: Variant, low: float, high: float) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) >= low and float(value) <= high

func _resource_path(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and value.begins_with("res://") and not value.contains("..") and FileAccess.file_exists(value)

func _candidate_base_profile_path() -> String:
	return "res://assets/water_material_natural_candidate/base_v8_normal.json"

func _candidate_water_shader_path() -> String:
	return "res://assets/water_material_natural_candidate/water_normal.gdshader"

func _candidate_apply_expected_visual_paths(_expected: Dictionary) -> void:
	pass


# Runtime resources are immutable for this entry lifetime; startup validation and
# the external source audit remain independent of this metadata-only cache.
var candidate_metadata_cache_enabled := true
var candidate_digest_cache := {}
var candidate_mesh_count_cache := {}

func _candidate_digest(path: String) -> String:
	if not candidate_metadata_cache_enabled:return FileAccess.get_sha256(path)
	if not candidate_digest_cache.has(path):candidate_digest_cache[path]=FileAccess.get_sha256(path)
	return candidate_digest_cache[path]

func _candidate_mesh_counts(mesh: ArrayMesh) -> Vector2i:
	var identity:=mesh.get_rid()
	if candidate_metadata_cache_enabled and candidate_mesh_count_cache.has(identity):
		return candidate_mesh_count_cache[identity]
	var arrays:=mesh.surface_get_arrays(0)
	var counts:=Vector2i(arrays[Mesh.ARRAY_VERTEX].size(),0 if arrays[Mesh.ARRAY_INDEX]==null else arrays[Mesh.ARRAY_INDEX].size())
	if candidate_metadata_cache_enabled:candidate_mesh_count_cache[identity]=counts
	return counts
