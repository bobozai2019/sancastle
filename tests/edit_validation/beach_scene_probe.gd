extends SceneTree

const FIELDS := ["rock", "sand", "water", "momentum_x", "momentum_z",
	"sediment", "wetness", "compaction", "obstacle", "flux"]
var output := ""
var preview: Node3D
var readbacks := {}
var checks := []
var snapshots := []
var wave_inputs := []
var failed := false

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			output = arg.trim_prefix("--output=")
	call_deferred("_run")

func _read(fields: Array, token: int) -> void:
	for field in fields:
		if preview.solver.request_data(field, _data.bind(field, token)) != OK:
			call_deferred("_error", "readback: " + field)

func _data(bytes: PackedByteArray, field: String, token: int) -> void:
	call_deferred("_record", bytes, field, token)

func _record(bytes: PackedByteArray, field: String, token: int) -> void:
	if token == preview.generation:
		readbacks[field] = bytes

func _error(message: String) -> void:
	failed = true
	printerr(message)

func _snapshot(prefix: String) -> Dictionary:
	readbacks.clear()
	var fields := FIELDS.duplicate()
	RenderingServer.call_on_render_thread(_read.bind(fields, preview.generation))
	while readbacks.size() != fields.size() and not failed:
		await process_frame
	for field in readbacks:
		var file := FileAccess.open(output.path_join(prefix + "_" + field + ".bin"), FileAccess.WRITE)
		file.store_buffer(readbacks[field])
	return readbacks.duplicate(true)

func _check(name: String, ok: bool, detail: Variant = null) -> void:
	checks.append({"name": name, "pass": ok, "detail": detail})

func _run() -> void:
	if output.is_empty():
		quit(1)
		return
	root.size = Vector2i(1920, 1080)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var scene: PackedScene = load("res://tests/edit_validation/edit_beach_lab.tscn")
	for attempt in 2:
		preview = scene.instantiate()
		preview.playing = false
		preview.generation = attempt + 1
		root.add_child(preview)
		var deadline := Time.get_ticks_msec() + 90000
		while not preview.ready_for_ticks:
			if not preview.last_error.is_empty() or Time.get_ticks_msec() > deadline:
				_error("beach initialize: " + preview.last_error)
				quit(1)
				return
			await process_frame
		_check("beach_profile_%d" % attempt, preview.requested_render_profile_sha256 == FileAccess.get_sha256("res://assets/test1_beach/test1_beach_release.json"), preview.effective_render_profile)
		var requests := []
		for request in preview.wave_requests:
			var item: Dictionary = request.duplicate(true)
			item.erase("generation")
			requests.append(item)
		wave_inputs.append(requests)
		_check("beach_continuous_wave_schedule_%d" % attempt, requests.size() == 80)
		var initial: Dictionary = await _snapshot("beach_initial_%d" % attempt)
		snapshots.append(initial)
		var idle: Dictionary = await _snapshot("beach_idle_%d" % attempt)
		var same := true
		for field in FIELDS:
			same = same and initial[field] == idle[field]
		_check("beach_paused_no_edit_identity_%d" % attempt, same and preview.completed_ticks == 0)
		if attempt == 0:
			preview.queue_free()
			for i in 6:
				await process_frame
	var same := true
	for field in FIELDS:
		same = same and snapshots[0][field] == snapshots[1][field]
	_check("beach_rebuild_same_initial_fields", same)
	_check("beach_rebuild_same_wave_inputs", JSON.stringify(wave_inputs[0]) == JSON.stringify(wave_inputs[1]))
	preview.playing = true
	var deadline := Time.get_ticks_msec() + 30000
	while preview.completed_ticks < 30 and preview.last_error.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	preview.playing = false
	while preview.tick_pending and preview.last_error.is_empty():
		await process_frame
	_check("beach_visible_full_load_short_run", preview.completed_ticks >= 30 and preview.last_error.is_empty(),
		{"tick": preview.completed_ticks, "error": preview.last_error, "generation": preview.generation})
	await _snapshot("beach_short_run")
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(output.path_join("beach.png"))
	var ok := not failed
	for check in checks:
		ok = ok and check.pass
	var file := FileAccess.open(output.path_join("beach_scene_probe.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass": ok, "checks": checks, "wave_inputs": wave_inputs,
		"render_size": [image.get_width(), image.get_height()], "purpose": "T02 inherited load/init/rebuild; no performance verdict"}, "\t"))
	preview.queue_free()
	for i in 6:
		await process_frame
	print("BEACH_SCENE_COMPLETE pass=" + str(ok))
	quit(0 if ok else 1)
