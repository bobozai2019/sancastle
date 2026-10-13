extends SceneTree

const SCENE := preload("res://scenes/water_visual_fixture.tscn")
const TICKS := [60, 120, 240, 300, 360, 480, 600, 900, 1200]

var foam_bytes := PackedByteArray()
var ready_data := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var preview: Node3D = SCENE.instantiate()
	root.add_child(preview)
	var frames := 0
	while not preview.ready_for_ticks and preview.last_error.is_empty() and frames < 1800:
		await process_frame
		frames += 1
	if not preview.ready_for_ticks:
		push_error("foam baseline init failed: " + preview.last_error)
		quit(1)
		return
	var samples := {}
	for target in TICKS:
		while preview.completed_ticks < target and preview.last_error.is_empty() and frames < 60000:
			await process_frame
			frames += 1
		if preview.completed_ticks < target or not preview.last_error.is_empty():
			push_error("foam baseline tick failed: " + preview.last_error)
			quit(1)
			return
		preview.playing = false
		while preview.tick_pending:
			await process_frame
		ready_data = false
		RenderingServer.call_on_render_thread(_read.bind(preview))
		var wait_frames := 0
		while not ready_data and wait_frames < 1200:
			await process_frame
			wait_frames += 1
		if not ready_data or foam_bytes.size() != 65536 * 8:
			push_error("foam baseline readback failed")
			quit(1)
			return
		samples[target] = _summarize(foam_bytes.to_float32_array())
		preview.playing = true
	preview.playing = false
	var report := {"ticks": TICKS, "samples": samples,
		"fixture_id": "water_v1", "wave_requests": 0}
	var output := FileAccess.open("res://test_output/sandcastle_visual_reconstruction_phase2/验收/W05_foam_baseline.json", FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify(report, "\t"))
		output.close()
	print("PASS: W05 foam baseline " + JSON.stringify(report))
	quit(0)


func _summarize(values: PackedFloat32Array) -> Dictionary:
	var sum := 0.0
	var coverage_05 := 0
	var hill_sum := 0.0
	var invalid := 0
	for i in 65536:
		var foam: float = values[i * 2]
		if not is_finite(foam) or foam < 0.0 or foam > 1.0:
			invalid += 1
			continue
		sum += foam
		if foam > 0.05:
			coverage_05 += 1
		var x := i % 256
		var z := i / 256
		if x >= 112 and x < 176 and z >= 76 and z < 140:
			hill_sum += foam
	return {"sum": sum, "coverage_05": coverage_05,
		"hill_sum": hill_sum, "invalid": invalid}


func _read(preview: Node3D) -> void:
	var error: Error = preview.foam_field.request_data(_on_data)
	if error != OK:
		call_deferred("_receive", PackedByteArray())


func _on_data(data: PackedByteArray) -> void:
	call_deferred("_receive", data)


func _receive(data: PackedByteArray) -> void:
	foam_bytes = data
	ready_data = true
