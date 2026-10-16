extends "res://scripts/visual/water_render_staging_entry.gd"

@onready var reflection_viewport: SubViewport = $ReflectionViewport
@onready var reflection_camera: Camera3D = $ReflectionViewport/ReflectionCamera

# Animated/ShaderMaterial reflection content can opt into continuous rendering.
@export var reflection_update_always := false
var reflection_revision := 0
var reflection_dirty := true
var reflection_nodes_dirty := true
var reflection_state := []
var reflection_geometry: Array[GeometryInstance3D] = []
var reflection_lights: Array[Light3D] = []
var reflection_resources: Array[Resource] = []
var reflection_materials: Array[BaseMaterial3D] = []
var reflection_has_dynamic_material := false


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
	reflection_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	if not get_tree().node_added.is_connected(_reflection_tree_changed):
		get_tree().node_added.connect(_reflection_tree_changed)
		get_tree().node_removed.connect(_reflection_tree_changed)
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


func invalidate_reflection() -> void:
	reflection_dirty = true


func _reflection_tree_changed(node: Node) -> void:
	if node is GeometryInstance3D or node is Light3D:
		reflection_nodes_dirty = true
		reflection_dirty = true


func _watch_reflection_resource(resource: Resource) -> void:
	if resource == null or resource in reflection_resources: return
	reflection_resources.append(resource)
	resource.changed.connect(invalidate_reflection)
	if resource is BaseMaterial3D: reflection_materials.append(resource)
	if resource is ShaderMaterial: reflection_has_dynamic_material = true


func _scan_reflection_nodes() -> void:
	for resource in reflection_resources:
		if resource.changed.is_connected(invalidate_reflection):
			resource.changed.disconnect(invalidate_reflection)
	reflection_resources.clear()
	reflection_materials.clear()
	reflection_geometry.clear()
	reflection_lights.clear()
	reflection_has_dynamic_material = false
	for node in find_children("*", "GeometryInstance3D", true, false):
		if not (node.layers & reflection_camera.cull_mask): continue
		reflection_geometry.append(node)
		if node is MeshInstance3D:
			_watch_reflection_resource(node.mesh)
			if node.mesh != null:
				for surface in node.mesh.get_surface_count():
					var material: Material = node.get_active_material(surface)
					_watch_reflection_resource(material)
					if material is ShaderMaterial: reflection_has_dynamic_material = true
			if node.skeleton != NodePath("") and node.get_node_or_null(node.skeleton) is Skeleton3D:
				reflection_has_dynamic_material = true
		else:
			# Particles and MultiMesh instances may animate without node transforms.
			reflection_has_dynamic_material = true
	for node in find_children("*", "Light3D", true, false):
		reflection_lights.append(node)
	var environment: Environment = $WorldEnvironment.environment
	_watch_reflection_resource(environment)
	reflection_nodes_dirty = false


func _update_reflection_camera() -> void:
	var source_camera := get_viewport().get_camera_3d()
	if source_camera == null: return
	if reflection_nodes_dirty: _scan_reflection_nodes()
	var environment: Environment = $WorldEnvironment.environment
	if environment != null and environment not in reflection_resources:
		_watch_reflection_resource(environment)
		reflection_dirty = true
	var state: Array = [source_camera, source_camera.global_transform,
		source_camera.fov, source_camera.near, source_camera.far, source_camera.projection,
		source_camera.keep_aspect, source_camera.size, source_camera.frustum_offset,
		source_camera.h_offset, source_camera.v_offset, reflection_viewport.size,
		water_material, environment, generation, reflection_camera.cull_mask, reflection_update_always]
	for node in reflection_geometry:
		state.append([node.global_transform, node.is_visible_in_tree(), node.layers,
			node.cast_shadow, node.material_override, node.material_overlay])
		if node is MeshInstance3D:
			state.append(node.mesh)
			if node.mesh != null and node.mesh not in reflection_resources: reflection_nodes_dirty = true
			if node.mesh != null:
				for surface in node.mesh.get_surface_count():
					var material: Material = node.get_active_material(surface)
					state.append(material)
					if material != null and material not in reflection_resources: reflection_nodes_dirty = true
		if node.material_overlay != null and node.material_overlay not in reflection_resources:
			_watch_reflection_resource(node.material_overlay)
	for light in reflection_lights:
		state.append([light.global_transform, light.is_visible_in_tree(), light.light_color,
			light.light_energy, light.light_indirect_energy, light.light_cull_mask, light.shadow_enabled])
	# BaseMaterial3D uniform setters also omit Resource.changed. Track the
	# ordinary surface inputs used by the static rocks; other custom changes
	# can call invalidate_reflection, and shader materials render continuously.
	for material in reflection_materials:
		state.append([material.albedo_color, material.albedo_texture,
			material.roughness, material.metallic, material.metallic_specular,
			material.emission_enabled, material.emission, material.emission_energy_multiplier,
			material.transparency, material.shading_mode, material.vertex_color_use_as_albedo,
			material.cull_mode, material.no_depth_test, material.uv1_scale, material.uv1_offset])
	var continuous := reflection_update_always or reflection_has_dynamic_material
	if not reflection_dirty and not reflection_nodes_dirty and state == reflection_state:
		if continuous:
			reflection_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		return
	if reflection_nodes_dirty: _scan_reflection_nodes()
	continuous = reflection_update_always or reflection_has_dynamic_material
	reflection_state = state
	reflection_dirty = false
	reflection_camera.fov = source_camera.fov
	reflection_camera.near = source_camera.near
	reflection_camera.far = source_camera.far
	reflection_camera.projection = source_camera.projection
	reflection_camera.keep_aspect = source_camera.keep_aspect
	reflection_camera.size = source_camera.size
	reflection_camera.frustum_offset = source_camera.frustum_offset
	reflection_camera.h_offset = source_camera.h_offset
	reflection_camera.v_offset = source_camera.v_offset
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
	water_material.set_shader_parameter("prototype_planar_view_projection", view_projection)
	reflection_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if continuous else SubViewport.UPDATE_ONCE
	reflection_revision += 1
