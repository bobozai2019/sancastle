extends "res://tests/edit_validation/water_curve_probe.gd"

var frames := []

func _write(ok: bool, error := "") -> void:
	var file := FileAccess.open(output.path_join("feedback_probe.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass": ok, "rows": rows, "frames": frames, "error": error,
		"scope": "same static camera B/C/D/E 256, completed tick images; diagnostic, not performance",
		"playback_hz": 30, "wall_time_distinct": true}, "\t"))

func _capture(tick: int, prefix: String) -> void:
	lab.get_node("EvidenceOverlay/Label").text = "%s | tick %d | sim %.3fs | wall %.3fs\ngen %d / revision %d | 256x256 | 0.125m | speed %.2fm/s" % [
		["B depth", "C displacement", "D velocity", "E combined"][phase], tick, tick / 30.0,
		(Time.get_ticks_usec() - run_wall_us) / 1e6, lab.generation, lab.solver.state_revision, lab.signed_speed_m_s]
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var name := prefix + "_frame%03d.jpg" % tick
	var err := image.save_jpg(output.path_join(name), 0.9)
	if err != OK: lab.last_error = "frame save error %d" % err
	if tick in [0, 3, 8, 15, 30, 60, 150]: image.save_png(output.path_join(prefix + "_tick%03d.png" % tick))
	frames.append({"file": name, "tick": tick, "sim_s": tick / 30.0,
		"wall_us": Time.get_ticks_usec() - run_wall_us, "generation": lab.generation,
		"revision": lab.solver.state_revision, "width": image.get_width(), "height": image.get_height(),
		"sha256": FileAccess.get_sha256(output.path_join(name))})

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--feedback-policy="): phase = int(arg.trim_prefix("--feedback-policy="))
	if phase < 0 or phase > 3:
		_write(false, "invalid policy"); finished = true; quit(1); return
	lab = load("res://tests/edit_validation/edit_feedback_lab.tscn").instantiate()
	root.add_child(lab)
	while not lab.ready_for_ticks and lab.last_error.is_empty(): await process_frame
	lab.water_policy = phase
	lab.signed_speed_m_s = 0.5 if phase >= 2 else 0.0
	var prefix: String = "256_" + ["B", "C", "D", "E"][phase]
	var before: Dictionary = await _snapshot(prefix + "_before")
	initial_volume = _sum(before.water.to_float32_array())
	var receipt: Dictionary = await lab.apply_gpu_command(_command(1, 0.48))
	_save(prefix + "_receipt.bin", lab.raw_receipt)
	var post: Dictionary = await _snapshot(prefix + "_post_edit")
	initial_sand_volume = _sum(post.sand.to_float32_array())
	initial_sediment_volume = _sum(post.sediment.to_float32_array())
	footprint.clear(); initial_roi_volume = 0.0
	var bs: PackedFloat32Array = before.sand.to_float32_array()
	var ns: PackedFloat32Array = post.sand.to_float32_array()
	var h: PackedFloat32Array = before.water.to_float32_array()
	for i in h.size():
		if bs[i] != ns[i]: footprint.append(i); initial_roi_volume += h[i] * 0.015625
	run_wall_us = Time.get_ticks_usec()
	for tick in 151:
		if tick > 0: await lab.advance_ticks(1)
		if not lab.last_error.is_empty(): break
		await _capture(tick, prefix)
		if tick in [0, 3, 8, 15, 30, 60, 150]: await _sample(prefix + "_tick%03d" % tick, tick / 30.0)
	var error: String = lab.last_error
	var ok: bool = error.is_empty() and receipt.get("status") == 1 and frames.size() == 151 and rows.size() == 7
	for row in rows: ok = ok and row.pass
	_write(ok, error)
	await lab.shutdown(); lab.queue_free(); finished = true
	print("FEEDBACK_COMPLETE pass=%s policy=%d frames=%d" % [str(ok), phase, frames.size()])
	quit(0 if ok else 1)
