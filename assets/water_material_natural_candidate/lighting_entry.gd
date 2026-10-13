extends "res://assets/water_material_natural_candidate/normal_entry.gd"

@export_file("*.json") var lighting_profile_path := "res://assets/water_material_natural_candidate/lighting_manual.json"
var lighting_profile := {}
var effective_lighting := {}

func _ready() -> void:
	var decoded: Variant = JSON.parse_string(FileAccess.get_file_as_string(lighting_profile_path))
	var keys := ["lighting_schema_version", "normal_profile", "normal_profile_sha256", "route", "base_profile", "water_shader", "sun_glint_enabled", "sun_glint_gain", "sun_glint_exponent", "shadow_enabled", "scatter_direct_fraction", "foam_direct_fraction"]
	if decoded is Dictionary and decoded.get("lighting_schema_version") in [2.0,3.0]:
		keys.append("foam_shader")
	if decoded is Dictionary and decoded.get("lighting_schema_version") == 3:
		keys.append_array(["shadow_proxy_mesh", "shadow_proxy_enabled"])
	if not decoded is Dictionary or not _keys(decoded, keys):
		_reject("invalid_lighting_profile")
		return
	lighting_profile = decoded
	if not (_number(lighting_profile.lighting_schema_version, 1.0, 1.0) or _number(lighting_profile.lighting_schema_version, 2.0, 2.0) or _number(lighting_profile.lighting_schema_version, 3.0, 3.0)) or lighting_profile.route not in ["manual_glint", "engine_light"] or not _resource_path(lighting_profile.normal_profile) or FileAccess.get_sha256(lighting_profile.normal_profile) != lighting_profile.normal_profile_sha256:
		_reject("invalid_lighting_identity")
		return
	for name in ["sun_glint_enabled", "shadow_enabled"]:
		if typeof(lighting_profile[name]) != TYPE_BOOL:
			_reject("invalid_lighting_boolean")
			return
	if not _number(lighting_profile.sun_glint_gain, 0.0, 2.0) or not _number(lighting_profile.sun_glint_exponent, 4.0, 256.0) or not _number(lighting_profile.scatter_direct_fraction, 0.0, 1.0) or not _number(lighting_profile.foam_direct_fraction, 0.0, 1.0):
		_reject("invalid_lighting_range")
		return
	if lighting_profile.route == "manual_glint" and (lighting_profile.shadow_enabled or lighting_profile.scatter_direct_fraction != 0.0 or lighting_profile.foam_direct_fraction != 0.0):
		_reject("unimplemented_manual_shadow")
		return
	if lighting_profile.lighting_schema_version == 1 and lighting_profile.route != "manual_glint":
		_reject("invalid_route_for_lighting_schema")
		return
	if not _resource_path(lighting_profile.base_profile) or not ResourceLoader.exists(lighting_profile.water_shader):
		_reject("missing_lighting_resource")
		return
	if lighting_profile.lighting_schema_version >= 2 and (lighting_profile.route != "engine_light" or not ResourceLoader.exists(lighting_profile.foam_shader)):
		_reject("missing_foam_lighting_resource")
		return
	if lighting_profile.lighting_schema_version == 3:
		if typeof(lighting_profile.shadow_proxy_enabled) != TYPE_BOOL or not ResourceLoader.exists(lighting_profile.shadow_proxy_mesh) or not has_node("TerrainShadowProxy") or $TerrainShadowProxy.mesh.resource_path != lighting_profile.shadow_proxy_mesh:
			_reject("invalid_shadow_proxy")
			return
	candidate_profile_path = lighting_profile.normal_profile
	super._ready()

func _candidate_base_profile_path() -> String:
	return lighting_profile.base_profile

func _candidate_water_shader_path() -> String:
	return lighting_profile.water_shader

func _configure_scene() -> void:
	super._configure_scene()
	water_material.set_shader_parameter("natural_glint_enabled", lighting_profile.sun_glint_enabled)
	water_material.set_shader_parameter("natural_glint_gain", lighting_profile.sun_glint_gain)
	water_material.set_shader_parameter("natural_glint_exponent", lighting_profile.sun_glint_exponent)
	water_material.set_shader_parameter("natural_scatter_direct_fraction", lighting_profile.scatter_direct_fraction)
	water_material.set_shader_parameter("natural_foam_direct_fraction", lighting_profile.foam_direct_fraction)
	if lighting_profile.lighting_schema_version >= 2:
		var material: ShaderMaterial = $PrototypeFrontFoamDense.material_override
		material.shader = load(lighting_profile.foam_shader)
		material.set_shader_parameter("natural_foam_direct_fraction", lighting_profile.foam_direct_fraction)
	if lighting_profile.lighting_schema_version == 3:
		$TerrainShadowProxy.material_override = terrain_material
		set_shadow_proxy(lighting_profile.shadow_proxy_enabled)
	$SandFixtureSun.shadow_enabled = lighting_profile.shadow_enabled
	_sync_sun()

func set_fixture_camera(camera_id: StringName) -> bool:
	if camera_id != &"sunward": return super.set_fixture_camera(camera_id)
	fixture_camera_id = camera_id
	if overview_camera == null: return true
	var anchor := get_node_or_null("CameraAnchors/LightFacing") as Camera3D
	if anchor == null: return false
	overview_camera.global_transform = anchor.global_transform
	overview_camera.fov = anchor.fov
	set_player_camera(false)
	return true

func _sync_sun() -> void:
	water_material.set_shader_parameter("prototype_light_direction_world", $SandFixtureSun.global_basis.z.normalized())

func _process(delta: float) -> void:
	super._process(delta)
	if water_material != null:
		_sync_sun()

func _seal_test1_effective_profile() -> void:
	super._seal_test1_effective_profile()
	effective_lighting = {"lighting_schema_version": lighting_profile.lighting_schema_version, "route": lighting_profile.route,
		"source_sha256": _candidate_digest(lighting_profile_path),
		"sun_glint_enabled": water_material.get_shader_parameter("natural_glint_enabled"),
		"sun_glint_gain": water_material.get_shader_parameter("natural_glint_gain"),
		"sun_glint_exponent": water_material.get_shader_parameter("natural_glint_exponent"),
		"shadow_enabled": $SandFixtureSun.shadow_enabled,
		"sun_direction_world": str($SandFixtureSun.global_basis.z.normalized()),
		"sun_energy": $SandFixtureSun.light_energy,
		"scatter_direct_fraction": water_material.get_shader_parameter("natural_scatter_direct_fraction"),
		"foam_direct_fraction": water_material.get_shader_parameter("natural_foam_direct_fraction"),
		"shader": water_material.shader.resource_path}
	if lighting_profile.lighting_schema_version >= 2:
		var material: ShaderMaterial = $PrototypeFrontFoamDense.material_override
		effective_lighting["foam_shader"] = material.shader.resource_path
		effective_lighting["foam_direct_uniform"] = material.get_shader_parameter("natural_foam_direct_fraction")
	if lighting_profile.lighting_schema_version == 3:
		effective_lighting["shadow_proxy_mesh"] = $TerrainShadowProxy.mesh.resource_path
		effective_lighting["shadow_proxy_enabled"] = $TerrainShadowProxy.visible
		effective_lighting["visible_terrain_cast_shadow"] = $GpuSandTerrain.cast_shadow
		effective_lighting["shadow_proxy_cast_mode"] = $TerrainShadowProxy.cast_shadow

func set_shadow_proxy(enabled: bool) -> void:
	$TerrainShadowProxy.visible = enabled
	$GpuSandTerrain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if enabled else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
