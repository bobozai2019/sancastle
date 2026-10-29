@tool
class_name SandcastleScenePreviewController
extends Node3D

## Editor-only art-direction controls for the lightweight scene preview.
## The owning gameplay scene hides this node on startup; simulation geometry
## remains authoritative at runtime.

@export_category("Editor Scene Preview")
@export_range(4.0, 64.0, 0.5, "or_greater") var preview_size_m := 32.0:
	set(value):
		preview_size_m = maxf(value, 1.0)
		_apply_preview()

@export_group("Terrain")
@export var terrain_color := Color(0.72, 0.53, 0.28, 1.0):
	set(value):
		terrain_color = value
		_apply_preview()
@export var dune_color := Color(0.72, 0.53, 0.28, 1.0):
	set(value):
		dune_color = value
		_apply_preview()
@export_range(-2.0, 4.0, 0.01) var terrain_level_m := -0.03:
	set(value):
		terrain_level_m = value
		_apply_preview()
@export var dune_center_m := Vector2(3.5, 0.5):
	set(value):
		dune_center_m = value
		_apply_preview()
@export_range(0.0, 16.0, 0.1) var dune_radius_x_m := 4.8:
	set(value):
		dune_radius_x_m = value
		_apply_preview()
@export_range(0.0, 16.0, 0.1) var dune_radius_z_m := 3.7:
	set(value):
		dune_radius_z_m = value
		_apply_preview()
@export_range(0.0, 8.0, 0.05) var dune_height_m := 1.1:
	set(value):
		dune_height_m = value
		_apply_preview()

@export_group("Water")
@export var water_enabled := true:
	set(value):
		water_enabled = value
		_apply_preview()
@export_range(-2.0, 4.0, 0.01) var water_level_m := 0.08:
	set(value):
		water_level_m = value
		_apply_preview()
@export_range(0.0, 1.0, 0.01) var water_coverage := 0.34:
	set(value):
		water_coverage = clampf(value, 0.0, 1.0)
		_apply_preview()
@export var water_color := Color(0.04, 0.72, 0.69, 0.68):
	set(value):
		water_color = value
		_apply_preview()
@export var deep_water_color := Color(0.02, 0.29, 0.37, 0.94):
	set(value):
		deep_water_color = value
		_apply_preview()
@export_range(0.001, 1.0, 0.005) var preview_water_depth_m := 0.10:
	set(value):
		preview_water_depth_m = value
		_apply_preview()
@export var water_output_bias := Vector3.ZERO:
	set(value):
		water_output_bias = value
		_apply_preview()
@export_range(-1.0, 60.0, 0.1) var preview_time_s := 6.0:
	set(value):
		preview_time_s = value
		_apply_preview()
@export_range(0.0, 0.5, 0.005) var wave_height_m := 0.08:
	set(value):
		wave_height_m = value
		_apply_preview()
@export_range(0.05, 4.0, 0.05) var wave_frequency := 0.6:
	set(value):
		wave_frequency = value
		_apply_preview()
@export_range(-4.0, 4.0, 0.05) var wave_speed := 0.7:
	set(value):
		wave_speed = value
		_apply_preview()

@export_group("Wave Trigger")
@export var trigger_origin_m := Vector2(-8.0, 0.0)
@export_range(0.0, 1.5, 0.01) var trigger_height_m := 0.35
@export_range(0.5, 12.0, 0.1) var trigger_speed_m_s := 4.0
@export_range(0.5, 8.0, 0.1) var trigger_duration_s := 4.0
@export_tool_button("触发水波") var trigger_water_wave_action = trigger_water_wave

var _trigger_age_s := -1.0


func _ready() -> void:
	_apply_preview()
	set_process(false)


func trigger_water_wave() -> void:
	_trigger_age_s = 0.0
	var water := get_node_or_null("WaterPreview") as MeshInstance3D
	if water != null:
		water.visible = true
	_update_trigger_shader()
	set_process(true)


func _process(delta: float) -> void:
	if _trigger_age_s < 0.0:
		set_process(false)
		return
	_trigger_age_s += delta
	if _trigger_age_s > trigger_duration_s:
		_trigger_age_s = -1.0
		set_process(false)
	_update_trigger_shader()
	if _trigger_age_s < 0.0 and not water_enabled:
		var water := get_node_or_null("WaterPreview") as MeshInstance3D
		if water != null:
			water.visible = false


func _apply_preview() -> void:
	if not is_inside_tree():
		return
	var terrain := get_node_or_null("TerrainPreview") as MeshInstance3D
	var dune := get_node_or_null("TerrainPreview/DunePreview") as MeshInstance3D
	var water := get_node_or_null("WaterPreview") as MeshInstance3D
	if terrain == null or dune == null or water == null:
		return
	var terrain_mesh := terrain.mesh as PlaneMesh
	var water_mesh := water.mesh as PlaneMesh
	var terrain_material := terrain_mesh.material as StandardMaterial3D
	var dune_material := dune.mesh.material as StandardMaterial3D
	var water_material := water_mesh.material as ShaderMaterial
	terrain_mesh.size = Vector2.ONE * preview_size_m
	terrain.position.y = terrain_level_m
	terrain_material.albedo_color = terrain_color
	dune_material.albedo_color = dune_color
	dune.position = Vector3(dune_center_m.x,
		dune_height_m * 0.35, dune_center_m.y)
	dune.scale = Vector3(dune_radius_x_m, dune_height_m * 0.5,
		dune_radius_z_m)
	var water_width := maxf(preview_size_m * water_coverage, 0.01)
	var water_length := preview_size_m * 0.985
	water_mesh.size = Vector2(water_width, water_length)
	# The shader moves vertices beyond PlaneMesh's flat AABB. Keep the edited
	# water visible until its expanded bounds actually leave the camera frustum.
	water.custom_aabb = AABB(Vector3(-water_width * 0.5, -2.0,
		-water_length * 0.5), Vector3(water_width, 4.0, water_length))
	water.position = Vector3(-preview_size_m * 0.5 + water_width * 0.5,
		water_level_m, 0.0)
	water.visible = water_enabled and water_coverage > 0.0
	water_material.set_shader_parameter("water_color", water_color)
	water_material.set_shader_parameter("deep_water_color", deep_water_color)
	water_material.set_shader_parameter("preview_depth_m", preview_water_depth_m)
	water_material.set_shader_parameter("output_color_bias", water_output_bias)
	water_material.set_shader_parameter("visual_time_s", preview_time_s)
	water_material.set_shader_parameter("wave_height_m", wave_height_m)
	water_material.set_shader_parameter("wave_frequency", wave_frequency)
	water_material.set_shader_parameter("wave_speed", wave_speed)
	_update_trigger_shader()


func _update_trigger_shader() -> void:
	if not is_inside_tree():
		return
	var water := get_node_or_null("WaterPreview") as MeshInstance3D
	if water == null:
		return
	var water_mesh := water.mesh as PlaneMesh
	var water_material := water_mesh.material as ShaderMaterial
	water_material.set_shader_parameter("trigger_origin_m", Vector2(
		trigger_origin_m.x - water.position.x,
		trigger_origin_m.y - water.position.z))
	water_material.set_shader_parameter("trigger_height_m", trigger_height_m)
	water_material.set_shader_parameter("trigger_age_s", _trigger_age_s)
	water_material.set_shader_parameter("trigger_speed_m_s", trigger_speed_m_s)
