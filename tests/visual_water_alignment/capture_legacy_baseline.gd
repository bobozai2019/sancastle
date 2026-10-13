extends SceneTree

const WATER_SCENE := preload("res://scenes/water_visual_fixture.tscn")
const COUPLED_SCENE := preload("res://scenes/sand_coupled_fixture.tscn")

var case_id := "water"
var output_dir := ""
var run_id := ""
var capture_tick := 60
var frames := 0


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--case="):
			case_id = arg.trim_prefix("--case=")
		elif arg.begins_with("--output="):
			output_dir = arg.trim_prefix("--output=")
		elif arg.begins_with("--run-id="):
			run_id = arg.trim_prefix("--run-id=")
		elif arg.begins_with("--tick="):
			capture_tick = int(arg.trim_prefix("--tick="))
	call_deferred("_run")


func _run() -> void:
	if case_id not in ["water", "coupled"] or output_dir.is_empty() or run_id.is_empty() or capture_tick < 1:
		_fail("invalid arguments")
		return
	if not DirAccess.dir_exists_absolute(output_dir):
		_fail("output directory does not exist: " + output_dir)
		return
	var preview: Node3D = WATER_SCENE.instantiate() if case_id == "water" else COUPLED_SCENE.instantiate()
	root.add_child(preview)
	while not preview.ready_for_ticks and preview.last_error.is_empty() and frames < 1800:
		await process_frame
		frames += 1
	if not preview.ready_for_ticks or not preview.last_error.is_empty():
		_fail("fixture initialization: " + preview.last_error)
		return
	while preview.completed_ticks < capture_tick and preview.last_error.is_empty() and frames < 36000:
		await process_frame
		frames += 1
	if preview.completed_ticks < capture_tick or not preview.last_error.is_empty():
		_fail("capture tick: " + preview.last_error)
		return
	preview.playing = false
	while preview.tick_pending and frames < 39000:
		await process_frame
		frames += 1
	if preview.tick_pending:
		_fail("GPU did not settle")
		return
	preview.set_visual_time(float(capture_tick) / 30.0)
	var camera_ids: Array[StringName] = [&"oblique", &"close", &"grazing"]
	if case_id == "coupled":
		camera_ids = [&"oblique"]
	var files: Array[String] = []
	var cameras := {}
	for camera_id in camera_ids:
		if case_id == "water" and not preview.set_fixture_camera(camera_id):
			_fail("unknown camera: " + String(camera_id))
			return
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var camera := root.get_camera_3d()
		if camera == null:
			_fail("camera missing: " + String(camera_id))
			return
		cameras[String(camera_id)] = {"transform": str(camera.global_transform),
			"projection": camera.projection, "fov_deg": camera.fov,
			"orthographic_size": camera.size, "near": camera.near, "far": camera.far}
		var path := output_dir.path_join("%s_%s_%s.png" % [run_id, case_id, camera_id])
		if root.get_texture().get_image().save_png(path) != OK:
			_fail("PNG write: " + path)
			return
		files.append(path)
	var manifest := {
		"role": "legacy_visual_baseline",
		"run_id": run_id,
		"fixture_id": String(preview.fixture_id),
		"case": case_id,
		"profile_id": "legacy_water_v1" if case_id == "water" else "legacy_sand_coupled_v1",
		"tick": preview.completed_ticks,
		"generation": preview.generation,
		"revision": preview.solver.state_revision,
		"visual_time_s": float(capture_tick) / 30.0,
		"render_subdivision": preview.render_subdivision,
		"grid_size": preview.shadow_domain.grid_size,
		"cell_size_m": preview.shadow_domain.cell_size_m,
		"sim_hz": 30,
		"camera": cameras,
		"wave_requests": [],
		"viewport_px": [root.size.x, root.size.y],
		"rendering_driver": "d3d12",
		"hardware": RenderingServer.get_video_adapter_name(),
		"artifacts": files,
	}
	var manifest_path := output_dir.path_join("%s_%s_manifest.json" % [run_id, case_id])
	var file := FileAccess.open(manifest_path, FileAccess.WRITE)
	if file == null:
		_fail("manifest write: " + manifest_path)
		return
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	print("PASS: WR legacy baseline %s tick=%d files=%d" % [case_id, preview.completed_ticks, files.size()])
	quit(0)


func _fail(message: String) -> void:
	push_error("FAIL: WR legacy baseline " + message)
	quit(1)
