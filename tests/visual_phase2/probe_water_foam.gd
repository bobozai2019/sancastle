extends SceneTree

const SCENE := preload("res://scenes/water_visual_fixture.tscn")
const Fixture := preload("res://scripts/scenarios/water_visual_fixture.gd")
const TICKS := [60, 120, 240, 300, 360, 480, 600, 900, 1200]
const OUT := "res://test_output/sandcastle_visual_reconstruction_phase2/验收/"

var readbacks: Dictionary = {}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var preview: Node3D = SCENE.instantiate()
	root.add_child(preview)
	var frames := 0
	while not preview.ready_for_ticks and preview.last_error.is_empty() and frames < 1800:
		await process_frame
		frames += 1
	if not preview.ready_for_ticks or preview.foam_field == null:
		push_error("foam fixture init failed: " + preview.last_error)
		quit(1)
		return
	var accepted: Dictionary = preview.request_wave({
		"domain_id": preview.shadow_domain.domain_id,
		"generation": preview.generation, "request_id": 1,
		"start_tick": 8, "profile_id": &"test_packet",
		"amplitude_m": 0.18, "duration_s": 6.0, "seed": 31})
	if not accepted.ok:
		push_error("foam wave request rejected: " + str(accepted))
		quit(1)
		return
	var samples := {}
	var artifacts: Array[String] = []
	for target in TICKS:
		while preview.completed_ticks < target and preview.last_error.is_empty() and frames < 60000:
			await process_frame
			frames += 1
		if preview.completed_ticks < target or not preview.last_error.is_empty():
			push_error("foam tick failed: " + preview.last_error)
			quit(1)
			return
		preview.playing = false
		while preview.tick_pending:
			await process_frame
		readbacks.clear()
		RenderingServer.call_on_render_thread(_read_state.bind(preview))
		var wait_frames := 0
		while readbacks.size() < 2 and wait_frames < 1200:
			await process_frame
			wait_frames += 1
		if readbacks.size() < 2 or readbacks.foam.size() != 65536 * 8 or \
				readbacks.water.size() != 65536 * 4:
			push_error("foam readback failed")
			quit(1)
			return
		samples[target] = _summarize(readbacks.foam.to_float32_array(),
			readbacks.water.to_float32_array())
		if target in [120, 300, 480, 900, 1200]:
			preview.set_visual_time(float(target) / 30.0)
			for camera_id in Fixture.CAMERA_IDS:
				preview.set_fixture_camera(camera_id)
				await RenderingServer.frame_post_draw
				await RenderingServer.frame_post_draw
				var filename := "W05_t%d_water_%s.png" % [target, camera_id]
				if root.get_texture().get_image().save_png(OUT + filename) != OK:
					push_error("foam screenshot failed: " + filename)
					quit(1)
					return
				artifacts.append(filename)
		preview.playing = true
	preview.playing = false
	var baseline_path := OUT + "W05_foam_baseline.json"
	var baseline: Variant = JSON.parse_string(FileAccess.get_file_as_string(baseline_path))
	if not baseline is Dictionary:
		push_error("foam baseline JSON missing")
		quit(1)
		return
	var gains := {}
	var invalid := 0
	var dry_foam := 0
	for target in TICKS:
		var baseline_sample: Dictionary = baseline.samples[str(target)]
		var sample: Dictionary = samples[target]
		gains[target] = {"sum": sample.sum - float(baseline_sample.sum),
			"coverage_05": sample.coverage_05 - int(baseline_sample.coverage_05),
			"hill_sum": sample.hill_sum - float(baseline_sample.hill_sum)}
		invalid += sample.invalid
		dry_foam += sample.dry_foam
	var passes: bool = invalid == 0 and dry_foam == 0 and \
			int(baseline.samples["300"].coverage_05) < 100 and \
			gains[300].hill_sum > 100.0 and gains[360].sum > 1000.0 and \
			float(samples[600].hill_sum) < float(samples[360].hill_sum) * 0.05
	var report := {"ticks": TICKS, "samples": samples,
		"relative_to_no_wave": gains,
		"wave_start_tick": 8, "wave_duration_s": 6.0,
		"wave_amplitude_m": 0.18, "artifacts": artifacts,
		"fixture_id": String(Fixture.FIXTURE_ID), "render_subdivision": preview.render_subdivision,
		"viewport_px": [root.size.x, root.size.y]}
	var output := FileAccess.open("res://test_output/sandcastle_visual_reconstruction_phase2/验收/W05_foam_probe.json", FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify(report, "\t"))
		output.close()
	print(("PASS" if passes else "FAIL") + ": W05 foam " + JSON.stringify(report))
	quit(0 if passes else 1)


func _summarize(foam_rg: PackedFloat32Array, water: PackedFloat32Array) -> Dictionary:
	var foam_sum := 0.0
	var foam_max := 0.0
	var wet_count := 0
	var coverage_05 := 0
	var coverage_20 := 0
	var dry_foam := 0
	var invalid := 0
	var near_sum := 0.0
	var hill_sum := 0.0
	var strong_weight := 0.0
	var strong_x_weight := 0.0
	for i in 65536:
		var foam: float = foam_rg[i * 2]
		var previous_depth: float = foam_rg[i * 2 + 1]
		if not is_finite(foam) or not is_finite(previous_depth) or \
				foam < -0.000001 or foam > 1.000001:
			invalid += 1
			continue
		foam_sum += foam
		foam_max = maxf(foam_max, foam)
		if water[i] > 0.0015:
			wet_count += 1
		elif foam > 0.001:
			dry_foam += 1
		if foam > 0.05:
			coverage_05 += 1
		if foam > 0.20:
			coverage_20 += 1
		var x := i % 256
		var z := i / 256
		if foam > 0.20:
			strong_weight += foam
			strong_x_weight += foam * float(x)
		if x < 64:
			near_sum += foam
		if x >= 112 and x < 176 and z >= 76 and z < 140:
			hill_sum += foam
	return {"sum": foam_sum, "max": foam_max, "wet_cells": wet_count,
		"coverage_05": coverage_05, "coverage_20": coverage_20,
		"dry_foam": dry_foam, "invalid": invalid,
		"near_sum": near_sum, "hill_sum": hill_sum,
		"strong_foam_centroid_x_cell": strong_x_weight / strong_weight if strong_weight > 0.0 else -1.0}


func _read_state(preview: Node3D) -> void:
	var foam_error: Error = preview.foam_field.request_data(_on_field.bind("foam"))
	if foam_error != OK:
		call_deferred("_receive_field", PackedByteArray(), "foam")
	var water_error: Error = preview.solver.request_data("water", _on_field.bind("water"))
	if water_error != OK:
		call_deferred("_receive_field", PackedByteArray(), "water")


func _on_field(data: PackedByteArray, field: String) -> void:
	call_deferred("_receive_field", data, field)


func _receive_field(data: PackedByteArray, field: String) -> void:
	readbacks[field] = data
