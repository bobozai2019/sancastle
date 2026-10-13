extends "res://tests/visual_water_alignment/prototypes/rock_reflection_candidate_entry.gd"

## Fixed test1 composition. Scene markers own the camera positions and targets.

func _configure_scene() -> void:
	var capabilities: Dictionary = requested_render_profile.capabilities
	var test1_visual: Dictionary = requested_render_profile.get("test1_visual", {})
	prototype_foam_front_local_dense = capabilities.foam_splats.enabled
	prototype_foam_surface_lift_m = float(requested_render_profile.visual.crest_height_m)
	prototype_foam_front_local_diameter_px = float(test1_visual.get("splat_diameter_px", 3.5))
	super._configure_scene()
	water_material.set_shader_parameter("test1_whitewater_gain",
		float(test1_visual.get("whitewater_gain", 1.0)))
	var contact_overlay := $ShoreContactOverlay as MeshInstance3D
	contact_overlay.mesh = ($GpuWaterSurface as MeshInstance3D).mesh
	var contact_material := contact_overlay.material_override as ShaderMaterial
	contact_material.set_shader_parameter("rock_state", rock_texture)
	contact_material.set_shader_parameter("sand_state", sand_texture)
	contact_material.set_shader_parameter("water_state", water_texture)
	contact_material.set_shader_parameter("foam_state", foam_texture)
	contact_material.set_shader_parameter("local_front_state", local_front_texture)
	contact_material.set_shader_parameter("enabled", capabilities.shore_contact.enabled)
	$SandFixtureSun.visible = true
	# The shared preview resets this in _configure_scene; test1's lit bed has no
	# visible cast-shadow contribution at the chosen camera scale.
	$SandFixtureSun.shadow_enabled = false
	var environment: Environment = $WorldEnvironment.environment
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.93, 0.91, 0.84)
	environment.ambient_light_energy = 0.65
	set_fixture_camera(fixture_camera_id)


func set_fixture_camera(camera_id: StringName) -> bool:
	var marker_name := ""
	match camera_id:
		&"oblique": marker_name = "Oblique"
		&"close": marker_name = "Close"
		&"grazing": marker_name = "Grazing"
		_: return false
	fixture_camera_id = camera_id
	if overview_camera == null:
		return true
	var anchor := get_node_or_null("CameraAnchors/" + marker_name) as Camera3D
	if anchor == null:
		return false
	overview_camera.global_transform = anchor.global_transform
	overview_camera.fov = anchor.fov
	set_player_camera(false)
	return true


func _mark_ready(token: int) -> void:
	super._mark_ready(token)
	if ready_for_ticks and last_error.is_empty():
		_seal_test1_effective_profile()


func _tick_finished(substeps: int, source_m3: float, sink_m3: float,
		token: int) -> void:
	super._tick_finished(substeps, source_m3, sink_m3, token)
	if ready_for_ticks and last_error.is_empty() and token == generation:
		_seal_test1_effective_profile()


func _seal_test1_effective_profile() -> void:
	var dense := $PrototypeFrontFoamDense as MeshInstance3D
	var contact_material := ($ShoreContactOverlay as MeshInstance3D).material_override as ShaderMaterial
	var dense_enabled := dense.visible
	var contact_enabled: bool = contact_material.get_shader_parameter("enabled")
	var capabilities: Dictionary = requested_render_profile.capabilities
	var test1_visual: Dictionary = requested_render_profile.get("test1_visual", {})
	if dense_enabled != capabilities.foam_splats.enabled or \
			contact_enabled != capabilities.shore_contact.enabled or \
			not is_equal_approx(float(water_material.get_shader_parameter(
			"test1_whitewater_gain")), float(test1_visual.get("whitewater_gain", 1.0))):
		_fail("test1 foam/contact effective profile mismatch")
		return
	effective_render_profile["test1_foam_splats"] = dense_enabled
	effective_render_profile["test1_shore_contact"] = contact_enabled
	effective_render_profile["test1_sand_forms"] = prototype_test1_sand_forms
	effective_render_profile["test1_whitewater_gain"] = water_material.get_shader_parameter(
		"test1_whitewater_gain")
	effective_render_profile["test1_splat_diameter_px"] = prototype_foam_front_local_diameter_px
	effective_render_profile_sha256 = JSON.stringify(effective_render_profile).sha256_text()
