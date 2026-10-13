extends "res://tests/visual_water_alignment/prototypes/reference_preview.gd"

const WaveWorkload = preload("res://scripts/visual/water_render_wave_workload.gd")
const WATER_SHADER = preload("res://tests/visual_water_alignment/prototypes/reference_water_local_front.gdshader")

@export_range(0.0, 0.4, 0.01) var movie_crest_height_m := 0.25
@export_range(1.0, 3.0, 0.1) var movie_lift_depth_scale := 1.5
@export var movie_front_foam_enabled := true
@export_range(0, 2, 1) var movie_foreground_mode := 0


func _ready() -> void:
	prototype_natural_reference_shore = true
	prototype_structured_reference_bed = true
	prototype_lobed_reference_bed = true
	prototype_branched_reference_bed = true
	prototype_local_front_field = true
	prototype_front_band_foam_source = true
	prototype_foam_front_local_dense = movie_front_foam_enabled
	prototype_foam_front_local_diameter_px = 8.0
	prototype_foam_surface_lift_m = movie_crest_height_m
	prototype_front_face_source_gate = true
	render_subdivision = 2
	visual_time_s = 0.0
	super._ready()


func _mark_ready(token: int) -> void:
	super._mark_ready(token)
	if not ready_for_ticks or not last_error.is_empty():
		return
	water_material.shader = WATER_SHADER
	water_material.set_shader_parameter("rock_state", rock_texture)
	water_material.set_shader_parameter("sand_state", sand_texture)
	water_material.set_shader_parameter("water_state", water_texture)
	water_material.set_shader_parameter("momentum_x_state", momentum_x_texture)
	water_material.set_shader_parameter("momentum_z_state", momentum_z_texture)
	water_material.set_shader_parameter("foam_state", foam_texture)
	water_material.set_shader_parameter("local_front_state", local_front_texture)
	water_material.set_shader_parameter("display_reconstruction", true)
	water_material.set_shader_parameter("prototype_use_local_front", true)
	water_material.set_shader_parameter("prototype_eta_normals", true)
	water_material.set_shader_parameter("prototype_screen_optics", true)
	water_material.set_shader_parameter("prototype_screen_abs_fresnel", true)
	water_material.set_shader_parameter("prototype_screen_face_normal", true)
	water_material.set_shader_parameter("prototype_crest_height_m", movie_crest_height_m)
	water_material.set_shader_parameter("prototype_local_back_cells", 7.5)
	water_material.set_shader_parameter("prototype_local_face_cells", 1.8)
	water_material.set_shader_parameter("prototype_local_lift_depth_scale",
		movie_lift_depth_scale)
	water_material.set_shader_parameter("prototype_front_face_rim_tone", true)
	water_material.set_shader_parameter("phase2_foam", false)
	set_visual_time(0.0)
	_update_front_face_source_gate()
	if movie_foreground_mode > 0:
		get_node("MovieForegroundWall").visible = true
	if movie_foreground_mode == 2:
		get_node("GpuWaterSurface").visible = false
	var scheduled: Dictionary = WaveWorkload.schedule(self, "continuous_packets_v1")
	if not scheduled.ok:
		_fail("local front movie wave workload: " + String(scheduled.code))


func _tick_finished(substeps: int, source_m3: float, sink_m3: float,
		token: int) -> void:
	super._tick_finished(substeps, source_m3, sink_m3, token)
	if last_error.is_empty() and token == generation:
		set_visual_time(float(completed_ticks) / 30.0)
