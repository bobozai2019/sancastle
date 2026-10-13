extends "res://scripts/visual/water_render_staging_entry.gd"

@onready var reflection_viewport: SubViewport = $ReflectionViewport
@onready var reflection_camera: Camera3D = $ReflectionViewport/ReflectionCamera


func _configure_scene() -> void:
	super._configure_scene()
	if requested_render_profile.schema_version >= 8:
		var environment_scene: Node3D = $ReflectionRockEnvironment
		if environment_scene.scene_file_path != \
				String(requested_render_profile.resources.reflection_environment_scene):
			_fail("reflection environment resource mismatch")
			return
		water_material.set_shader_parameter("prototype_screen_sky_reflection_scale",
			requested_render_profile.visual.reflection_strength)
	reflection_viewport.world_3d = get_viewport().world_3d
	reflection_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	reflection_camera.cull_mask = 4
	reflection_camera.make_current()
	water_material.set_shader_parameter(
		"prototype_planar_reflection", reflection_viewport.get_texture())
	water_material.set_shader_parameter("prototype_planar_reflection_projected", true)
	water_material.set_shader_parameter("prototype_planar_reflection_enabled", true)
	_update_reflection_camera()


func _mark_ready(token: int) -> void:
	super._mark_ready(token)
	if not ready_for_ticks or not last_error.is_empty():
		return
	_update_reflection_camera()


func _process(delta: float) -> void:
	super._process(delta)
	if ready_for_ticks and last_error.is_empty():
		_update_reflection_camera()


func _update_reflection_camera() -> void:
	var source_camera := get_viewport().get_camera_3d()
	if source_camera == null:
		return
	reflection_camera.fov = source_camera.fov
	reflection_camera.near = source_camera.near
	reflection_camera.far = source_camera.far
	var source_basis := source_camera.global_transform.basis
	var reflected_position := source_camera.global_position
	reflected_position.y = -reflected_position.y
	var reflected_forward := -source_basis.z
	reflected_forward.y = -reflected_forward.y
	var reflected_up := source_basis.y
	reflected_up.y = -reflected_up.y
	reflection_camera.global_position = reflected_position
	reflection_camera.look_at(reflected_position + reflected_forward, reflected_up)
	var view_projection := reflection_camera.get_camera_projection() * Projection(
		reflection_camera.global_transform.affine_inverse())
	water_material.set_shader_parameter(
		"prototype_planar_view_projection", view_projection)
