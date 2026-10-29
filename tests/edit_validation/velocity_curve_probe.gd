extends "res://tests/edit_validation/water_curve_probe.gd"

var observe_step_loss := false
var step_loss_data := PackedByteArray()
var curve_policy := 2

func _read_step_loss() -> void:
	lab.solver.rd.buffer_get_data_async(lab.solver.step_loss_buffer, _step_loss_ready)

func _step_loss_ready(data: PackedByteArray) -> void: call_deferred("_record_step_loss", data)
func _record_step_loss(data: PackedByteArray) -> void: step_loss_data = data

func _sample(prefix: String, requested_time: float) -> void:
	await super._sample(prefix, requested_time)
	if not observe_step_loss: return
	step_loss_data.clear()
	RenderingServer.call_on_render_thread(_read_step_loss)
	while step_loss_data.is_empty(): await process_frame
	_save(prefix + "_step_loss.bin", step_loss_data)
	var ix := 0.0
	var iz := 0.0
	var energy := 0.0
	var events := PackedInt64Array([0,0,0,0])
	var finite := true
	var state_flags := 0
	for i in lab.profile.grid_size * lab.profile.grid_size:
		for slot in 4: finite = finite and is_finite(step_loss_data.decode_float(i * 32 + slot * 4))
		ix += step_loss_data.decode_float(i * 32) * 0.015625
		iz += step_loss_data.decode_float(i * 32 + 4) * 0.015625
		energy += step_loss_data.decode_float(i * 32 + 8) * 0.015625
		for slot in 3: events[slot] += step_loss_data.decode_u32(i * 32 + 16 + slot * 4)
		var last := step_loss_data.decode_u32(i * 32 + 28)
		events[3] += last & 0x00ffffff
		state_flags |= last >> 24
	rows[-1].native_substep_loss = {"removed_momentum_m4_s": [ix,iz],
		"removed_energy_defined_m5_s2": energy, "events": Array(events),
		"event_order": ["dry_or_ocean_zero", "native_velocity_limit", "blocked_zero", "undefined_zero_depth_energy"],
		"finite": finite, "all_completed_substeps_state_flags": state_flags,
		"flag_bits": ["nonfinite", "negative_water", "dry_momentum_nonzero"]}
	rows[-1].pass = rows[-1].pass and finite and state_flags == 0

func _write(ok: bool, error := "") -> void:
	var file := FileAccess.open(output.path_join("velocity_curve_probe.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass": ok, "rows": rows, "error": error,
		"scope": ("D velocity" if curve_policy == 2 else "E combined") + " four speeds, native30Hz+CFL 0-5s; captures, not performance",
		"conservation_guard": "existing solver 0.5% ceiling; instantaneous edit and impulse audits separate"}, "\t"))

func _run() -> void:
	var failure := ""
	observe_step_loss = "--observe-step-loss" in OS.get_cmdline_user_args()
	for size in [64, 256]:
		lab = load("res://tests/edit_validation/edit_gpu_water_" + ("diagnostic_" if observe_step_loss else "") + ("numeric" if size == 64 else "brush") + "_lab.tscn").instantiate()
		root.add_child(lab)
		while not lab.ready_for_ticks and lab.last_error.is_empty(): await process_frame
		if not lab.last_error.is_empty():
			failure = lab.last_error
			break
		for speed in [0.0, 0.25, 0.5, -0.25]:
			await lab.reset_domain()
			phase = curve_policy
			lab.water_policy = curve_policy
			lab.signed_speed_m_s = speed
			var prefix := "%d_%s_%s" % [size, "D" if curve_policy == 2 else "E", str(speed)]
			var before: Dictionary = await _snapshot(prefix + "_before")
			initial_volume = _sum(before.water.to_float32_array())
			var result: Dictionary = await lab.apply_gpu_command(_command(1, 0.48))
			if not lab.last_error.is_empty() or result.get("status") != 1:
				failure = lab.last_error if not lab.last_error.is_empty() else "velocity edit rejected"
				break
			_save(prefix + "_command_receipt.bin", lab.raw_receipt)
			var post: Dictionary = await _snapshot(prefix + "_post_edit")
			initial_sand_volume = _sum(post.sand.to_float32_array())
			initial_sediment_volume = _sum(post.sediment.to_float32_array())
			var old_sand: PackedFloat32Array = before.sand.to_float32_array()
			var new_sand: PackedFloat32Array = post.sand.to_float32_array()
			var old_water: PackedFloat32Array = before.water.to_float32_array()
			footprint.clear()
			initial_roi_volume = 0.0
			for i in old_sand.size():
				if old_sand[i] != new_sand[i]:
					footprint.append(i)
					initial_roi_volume += old_water[i] * 0.015625
			run_wall_us = Time.get_ticks_usec()
			var ticks := [0, 3, 8, 15, 30, 60, 150]
			var requested := [0.0, 0.1, 0.25, 0.5, 1.0, 2.0, 5.0]
			for sample in ticks.size():
				if ticks[sample] > 0: await lab.advance_ticks(ticks[sample] - lab.completed_ticks)
				if not lab.last_error.is_empty():
					failure = lab.last_error
					break
				await _sample(prefix + "_tick%03d" % ticks[sample], requested[sample])
				rows[-1].signed_speed_m_s = speed
				rows[-1].edit_receipt = result
				_write(false, "running")
			if not failure.is_empty(): break
		await lab.shutdown()
		lab.queue_free()
		await process_frame
		lab = null
		if not failure.is_empty(): break
	var ok := failure.is_empty() and rows.size() == 56
	for row in rows: ok = ok and row.pass
	_write(ok, failure)
	if lab != null:
		await lab.shutdown()
		lab.queue_free()
	finished = true
	print("VELOCITY_CURVE_COMPLETE pass=%s rows=%d" % [str(ok), rows.size()])
	quit(0 if ok else 1)
