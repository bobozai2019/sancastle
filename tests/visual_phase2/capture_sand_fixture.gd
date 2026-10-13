extends SceneTree

const SCENE := preload("res://scenes/sand_visual_fixture.tscn")
const Sampler := preload("res://scripts/visual/sand_display_sampler.gd")
const OUT := "res://test_output/sandcastle_visual_reconstruction_phase2/验收/"
const GRID := 256
const CELL_M := 0.125

var preview: Node3D
var sand_bytes := PackedByteArray()
var wet_bytes := PackedByteArray()
var frames := 0
var camera_id: StringName = &"oblique"
var subdivision := 2
var component := "all"
var stage := ""
var target_tick := 300


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--camera="):
			camera_id = StringName(arg.trim_prefix("--camera="))
		if arg.begins_with("--subdivision="):
			subdivision = int(arg.trim_prefix("--subdivision="))
		if arg.begins_with("--component="):
			component = arg.trim_prefix("--component=")
		if arg.begins_with("--stage="):
			stage = arg.trim_prefix("--stage=")
	if not stage.is_empty():
		target_tick = 30
	call_deferred("_run")


func _run() -> void:
	preview = SCENE.instantiate()
	preview.fixture_camera_id = camera_id
	preview.render_subdivision = subdivision
	if not stage.is_empty():
		var stage_wetness := {"dry": 0.05, "wet": 1.0,
			"retreat": 0.7671, "dried": 0.05}
		if not stage_wetness.has(stage):
			push_error("FAIL: unknown stage " + stage)
			quit(1)
			return
		preview.sand_fixture_wetness_override = stage_wetness[stage]
	root.add_child(preview)
	while (not preview.ready_for_ticks or preview.completed_ticks < target_tick) and preview.last_error.is_empty() and frames < 18000:
		await process_frame
		frames += 1
	if not preview.last_error.is_empty() or preview.completed_ticks < target_tick:
		push_error("FAIL: S02 sand fixture setup/tick " + preview.last_error)
		quit(1)
		return
	preview.playing = false
	while preview.tick_pending and frames < 19000:
		await process_frame
		frames += 1
	RenderingServer.call_on_render_thread(_read_sand)
	while (sand_bytes.is_empty() or wet_bytes.is_empty()) and frames < 20000:
		await process_frame
		frames += 1
	if sand_bytes.size() != GRID * GRID * 4:
		push_error("FAIL: S02 sand fixture GPU readback")
		quit(1)
		return
	var sand: PackedFloat32Array = sand_bytes.to_float32_array()
	var packed_wet_sum := 0.0
	for z in range(120, 137):
		for x in range(72, 89):
			packed_wet_sum += wet_bytes.decode_half(2 * (z * GRID + x))
	var result := {"fixture_id": String(preview.fixture_id),
		"camera_id": String(camera_id), "component": component, "stage": stage,
		"packed_wetness_mean": packed_wet_sum / 289.0,
		"tick": preview.completed_ticks, "revision": preview.solver.state_revision,
		"sand_gpu_hash": hash(sand_bytes),
		"cohesion_yield_height_m": preview.sand_cohesion_yield_height_m,
		"render_subdivision": preview.render_subdivision,
		"enable_erosion": preview.enable_erosion,
		"enable_structures": preview.enable_structures,
		"packed": _measure(sand, 80), "loose": _measure(sand, 176)}
	var rock := PackedFloat32Array()
	rock.resize(GRID * GRID)
	rock.fill(0.20)
	await physics_frame
	await physics_frame
	var centre_errors: Array[float] = []
	var half_errors: Array[float] = []
	var missing_rays := 0
	var worst := {}
	var worst_error := -1.0
	for z in range(119, 138):
		for x in range(71, 90):
			for offset in [0.5, 1.0]:
				var world_x: float = (float(x) + float(offset)) * CELL_M - 16.0
				var world_z: float = (float(z) + float(offset)) * CELL_M - 16.0
				var sample := Sampler.sample_world(rock, sand, GRID, CELL_M,
					Vector2(world_x, world_z))
				var query := PhysicsRayQueryParameters3D.create(
					Vector3(world_x, 10.0, world_z),
					Vector3(world_x, -10.0, world_z))
				var hit: Dictionary = root.world_3d.direct_space_state.intersect_ray(query)
				if not hit.has("position"):
					missing_rays += 1
					continue
				var error: float = absf(sample - hit.position.y)
				if error > worst_error:
					worst_error = error
					worst = {"x": x, "z": z, "offset": offset,
						"world_x": world_x, "world_z": world_z,
						"display_m": sample, "collision_m": hit.position.y}
				if offset == 0.5:
					centre_errors.append(error)
				else:
					half_errors.append(error)
	centre_errors.sort()
	half_errors.sort()
	result["display_collision"] = {
		"cell_centres_max_m": centre_errors[-1] if not centre_errors.is_empty() else INF,
		"half_cells_max_m": half_errors[-1] if not half_errors.is_empty() else INF,
		"half_cells_p95_m": half_errors[int(0.95 * float(half_errors.size() - 1))] if not half_errors.is_empty() else INF,
		"missing_rays": missing_rays,
		"worst": worst,
		"samples": centre_errors.size() + half_errors.size()}
	preview.set_fixture_camera(camera_id)
	preview.terrain_material.set_shader_parameter("use_grain", component != "no_grain")
	preview.terrain_material.set_shader_parameter("use_grain_normal", component != "no_normal")
	preview.terrain_material.set_shader_parameter("use_wet_finish", component != "no_wet")
	preview.terrain_material.set_shader_parameter("use_compaction_tint", component != "no_compaction")
	await process_frame
	await process_frame
	var image := root.get_viewport().get_texture().get_image()
	var artifact_stem := "S04_stage_%s_%s_t%d" % [stage, String(camera_id), target_tick] if not stage.is_empty() else \
		("S04_%s_%s_t300" % [component, String(camera_id)] if component != "all" else \
		("S02_sand_fixture_t300" if camera_id == &"oblique" and subdivision == 2 else \
		"S03_%s_%dx_t300" % [String(camera_id), subdivision]))
	var image_path := ProjectSettings.globalize_path(OUT + artifact_stem + ".png")
	if image.save_png(image_path) != OK:
		push_error("FAIL: S02 sand fixture screenshot")
		quit(1)
		return
	var json_path := ProjectSettings.globalize_path(OUT + artifact_stem + ".json")
	var file := FileAccess.open(json_path, FileAccess.WRITE)
	if file == null:
		push_error("FAIL: S02 sand fixture manifest")
		quit(1)
		return
	file.store_string(JSON.stringify(result, "  "))
	file.close()
	print("PASS: S02 sand fixture " + JSON.stringify(result))
	quit(0)


func _read_sand() -> void:
	var rd := RenderingServer.get_rendering_device()
	var data: PackedByteArray = rd.texture_get_data(
		preview.solver.current_texture("sand"), 0)
	var wet_data: PackedByteArray = rd.texture_get_data(
		preview.solver.current_texture("wetness"), 0)
	call_deferred("_receive_sand", data, wet_data)


func _receive_sand(data: PackedByteArray, wet_data: PackedByteArray) -> void:
	sand_bytes = data
	wet_bytes = wet_data


func _measure(sand: PackedFloat32Array, center_x: int) -> Dictionary:
	var peak := 0.0
	var high := 0
	var boundary := 0.0
	var boundary_count := 0
	var volume := 0.0
	for z in range(128 - 16, 128 + 17):
		for x in range(center_x - 16, center_x + 17):
			var h: float = sand[z * GRID + x]
			volume += h * CELL_M * CELL_M
			if absi(x - center_x) > 8 or absi(z - 128) > 8:
				continue
			peak = maxf(peak, h)
			if h > 0.9:
				high += 1
			if absi(x - center_x) == 8 or absi(z - 128) == 8:
				boundary += h
				boundary_count += 1
	return {"peak_m": peak, "high_shape_iou": float(high) / 289.0,
		"boundary_mean_m": boundary / float(boundary_count),
		"local_sand_volume_m3": volume}
