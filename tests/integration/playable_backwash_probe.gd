extends SceneTree

var scene
var output := "D:/godot/project/sandcastle/test_output/playable_backwash_20261013_v1"
var results := {"pass": false, "samples": [], "errors": []}
var readbacks := {}
const FIELDS := ["water", "momentum_x", "rock", "sand", "sediment"]

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			output = arg.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(output)
	call_deferred("_run")

func _read() -> void:
	for field in FIELDS:
		scene.solver.request_data(field, func(bytes: PackedByteArray) -> void: call_deferred("_receive", field, bytes))

func _receive(key: String, bytes: PackedByteArray) -> void:
	readbacks[key] = bytes

func _sample() -> void:
	readbacks.clear()
	RenderingServer.call_on_render_thread(_read)
	var deadline := Time.get_ticks_msec() + 30000
	while readbacks.size() < FIELDS.size() and Time.get_ticks_msec() < deadline:
		await process_frame
	if readbacks.size() != FIELDS.size():
		results.errors.append("readback timeout")
		return
	var arrays := {}
	for field in FIELDS:
		arrays[field] = readbacks[field].to_float32_array()
		var file := FileAccess.open(output.path_join("%04d_%s.f32" % [scene.completed_ticks, field]), FileAccess.WRITE)
		file.store_buffer(readbacks[field])
	var water := 0.0
	var shore := 0.0
	var velocity := 0.0
	var count := 0
	var sand := 0.0
	for i in 256 * 256:
		for field in FIELDS:
			if not is_finite(arrays[field][i]):
				results.errors.append("nonfinite " + field)
		var h: float = arrays.water[i]
		water += h * 0.015625
		sand += (float(arrays.sand[i]) + float(arrays.sediment[i])) * 0.015625
		if h < -0.000001 or arrays.sand[i] < -0.000001:
			results.errors.append("negative state")
		if arrays.rock[i] + arrays.sand[i] > 0.10:
			shore += h * 0.015625
			if h > 0.005:
				velocity += float(arrays.momentum_x[i]) / h
				count += 1
	var row := {"tick": scene.completed_ticks, "time_s": float(scene.completed_ticks) / 30.0, "sea_level": scene.CaptureLayout.sea_level(scene.scene_key, float(scene.completed_ticks) / 30.0), "water_m3": water, "shore_water_m3": shore, "shore_mean_vx": velocity / maxf(count, 1.0), "water_source_m3": scene.solver.water_source_m3, "water_sink_m3": scene.solver.water_sink_m3, "sand_total_m3": sand, "sand_closure_m3": sand - scene.initial_sand_total_m3, "substeps": scene.last_substeps}
	results.samples.append(row)
	print("BACKWASH_SAMPLE ", JSON.stringify(row))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("frame_%04d.png" % scene.completed_ticks))
	var file := FileAccess.open(output.path_join("progress.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "\t"))

func _run() -> void:
	scene = load("res://scenes/playable/test1_backwash.tscn").instantiate()
	scene.playing = false
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 90000
	while not scene.ready_for_ticks and scene.last_error.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	if not scene.ready_for_ticks:
		results.errors.append(scene.last_error)
	else:
		scene.get_node("Interface/PerformancePanel/Margin/Rows/Header/Sampling").button_pressed = false
		await _sample()
		for tick in 540:
			var before: int = scene.completed_ticks
			scene._start_tick()
			deadline = Time.get_ticks_msec() + 30000
			while scene.completed_ticks == before and scene.last_error.is_empty() and Time.get_ticks_msec() < deadline:
				await process_frame
			if scene.completed_ticks != before + 1 or not scene.last_error.is_empty():
				results.errors.append("tick: " + scene.last_error)
				break
			if scene.completed_ticks % 60 == 0:
				await _sample()
		results["engine"] = Engine.get_version_info()
		results["adapter"] = RenderingServer.get_video_adapter_name()
		results["scope"] = "main conservative solver; 256x256 resampled test1 geometry; 16s Godot sea-level cycle, not original timing or capture kernels"
	await scene.shutdown()
	results.pass = results.errors.is_empty() and results.samples.size() == 10
	var file := FileAccess.open(output.path_join("result.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "\t"))
	quit(0 if results.pass else 1)
