extends SceneTree

const SCENE := preload("res://scenes/water_visual_fixture.tscn")
const TICKS := [120, 240, 360, 480, 600, 720]
const SITES := {"near": Vector2i(48, 108), "middle": Vector2i(88, 108),
	"before_hill": Vector2i(120, 108), "hill": Vector2i(140, 108),
	"north_flank": Vector2i(140, 84), "south_flank": Vector2i(140, 132),
	"behind_hill": Vector2i(160, 108)}

var field_bytes: Dictionary = {}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var baseline: Dictionary = await _capture_case(false)
	var wave: Dictionary = await _capture_case(true)
	if baseline.is_empty() or wave.is_empty():
		quit(1)
		return
	var curves := {}
	var momentum_curves := {}
	var arrivals := {}
	for site in SITES:
		var samples := []
		var momentum_samples := []
		for tick in TICKS:
			var gain: float = wave[tick].water[site] - baseline[tick].water[site]
			var momentum_gain: float = wave[tick].momentum_x[site] - baseline[tick].momentum_x[site]
			samples.append(snappedf(gain, 0.000001))
			momentum_samples.append(snappedf(momentum_gain, 0.000001))
			if gain > 0.002 and not arrivals.has(site):
				arrivals[site] = tick
		curves[site] = samples
		momentum_curves[site] = momentum_samples
	var flank_gain := maxf(curves.north_flank.max(), curves.south_flank.max())
	var passes: bool = curves.near.max() > 0.005 and \
			curves.middle.max() > 0.002 and \
			curves.before_hill.max() > 0.001 and flank_gain > 0.002 and \
			absf(momentum_curves.north_flank[2]) > 0.002 and \
			absf(momentum_curves.south_flank[2]) > 0.002 and \
			wave.max_substeps <= 32 and baseline.max_substeps <= 32 and \
			wave.invalid_count == 0 and wave.negative_count == 0 and \
			wave.closure_fraction <= 0.005
	var report := {"ticks": TICKS, "depth_gain_curves_m": curves,
		"momentum_x_gain_curves_m2_s": momentum_curves,
		"first_sampled_arrival_tick": arrivals,
		"baseline_max_substeps": baseline.max_substeps,
		"wave_max_substeps": wave.max_substeps,
		"wave_invalid_cells": wave.invalid_count,
		"wave_negative_cells": wave.negative_count,
		"wave_closure_fraction": wave.closure_fraction,
		"wave_source_m3": wave.source_m3, "wave_sink_m3": wave.sink_m3}
	var output := FileAccess.open("res://test_output/sandcastle_visual_reconstruction_phase2/验收/W04_wave_arrival.json", FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify(report, "\t"))
		output.close()
	print(("PASS" if passes else "FAIL") + ": W04 arrival " + JSON.stringify(report))
	quit(0 if passes else 1)


func _capture_case(with_wave: bool) -> Dictionary:
	var preview: Node3D = SCENE.instantiate()
	root.add_child(preview)
	var frames := 0
	while not preview.ready_for_ticks and preview.last_error.is_empty() and frames < 1800:
		await process_frame
		frames += 1
	if not preview.ready_for_ticks:
		push_error("arrival fixture init failed: " + preview.last_error)
		return {}
	var initial_volume: float = preview.shadow_domain.total_water_m3()
	if with_wave:
		var accepted: Dictionary = preview.request_wave({
			"domain_id": preview.shadow_domain.domain_id,
			"generation": preview.generation, "request_id": 1,
			"start_tick": 8, "profile_id": &"test_packet",
			"amplitude_m": 0.18, "duration_s": 6.0, "seed": 17})
		if not accepted.ok:
			push_error("arrival wave rejected: " + str(accepted))
			return {}
	var samples := {}
	var max_substeps := 0
	for target in TICKS:
		while preview.completed_ticks < target and preview.last_error.is_empty() and frames < 60000:
			await process_frame
			frames += 1
			max_substeps = maxi(max_substeps, preview.last_substeps)
		if preview.completed_ticks < target or not preview.last_error.is_empty():
			push_error("arrival tick failed: " + preview.last_error)
			return {}
		preview.playing = false
		while preview.tick_pending:
			await process_frame
		field_bytes.clear()
		RenderingServer.call_on_render_thread(_read_water.bind(preview))
		var wait_frames := 0
		while field_bytes.size() < 2 and wait_frames < 1200:
			await process_frame
			wait_frames += 1
		if field_bytes.size() < 2 or field_bytes.water.size() != 65536 * 4 or \
				field_bytes.momentum_x.size() != 65536 * 4:
			push_error("arrival readback failed")
			return {}
		var water: PackedFloat32Array = field_bytes.water.to_float32_array()
		var qx: PackedFloat32Array = field_bytes.momentum_x.to_float32_array()
		var at_tick := {"water": {}, "momentum_x": {}}
		for site in SITES:
			var center: Vector2i = SITES[site]
			var mean_water := 0.0
			var mean_qx := 0.0
			for z in range(center.y - 2, center.y + 3):
				for x in range(center.x - 2, center.x + 3):
					mean_water += water[z * 256 + x] / 25.0
					mean_qx += qx[z * 256 + x] / 25.0
			at_tick.water[site] = mean_water
			at_tick.momentum_x[site] = mean_qx
		samples[target] = at_tick
		preview.playing = true
	preview.playing = false
	var volume := 0.0
	var invalid := 0
	var negative := 0
	for depth in field_bytes.water.to_float32_array():
		if not is_finite(depth):
			invalid += 1
		elif depth < -0.000001:
			negative += 1
		volume += depth * 0.015625
	var source: float = preview.solver.water_source_m3
	var sink: float = preview.solver.water_sink_m3
	samples.max_substeps = max_substeps
	samples.invalid_count = invalid
	samples.negative_count = negative
	samples.source_m3 = source
	samples.sink_m3 = sink
	samples.closure_fraction = absf(volume - (initial_volume + source - sink)) / maxf(volume, 1.0)
	preview.queue_free()
	await process_frame
	await process_frame
	return samples


func _read_water(preview: Node3D) -> void:
	for field in ["water", "momentum_x"]:
		var error: Error = preview.solver.request_data(field, _on_field.bind(field))
		if error != OK:
			call_deferred("_receive_field", PackedByteArray(), field)


func _on_field(data: PackedByteArray, field: String) -> void:
	call_deferred("_receive_field", data, field)


func _receive_field(data: PackedByteArray, field: String) -> void:
	field_bytes[field] = data
