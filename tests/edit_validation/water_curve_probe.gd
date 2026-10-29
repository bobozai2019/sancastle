extends "res://tests/edit_validation/water_transaction_probe.gd"

var initial_volume := 0.0
var footprint := PackedInt32Array()
var initial_roi_volume := 0.0
var phase := 0
var run_wall_us := 0
var initial_sand_volume := NAN
var initial_sediment_volume := NAN

func _write(ok: bool, error := "") -> void:
	var file := FileAccess.open(output.path_join("water_curve_probe.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass": ok, "rows": rows, "error": error,
		"scope": "native B/C, 30Hz+CFL through 5 simulated seconds; diagnostic captures, not performance",
		"conservation_guard": "existing solver 0.5% ceiling; strict instantaneous edit audit is separate"}, "\t"))

func _sample(prefix: String, requested_time: float) -> void:
	var state: Dictionary = await _snapshot(prefix)
	var h: PackedFloat32Array = state.water.to_float32_array()
	var qx: PackedFloat32Array = state.momentum_x.to_float32_array()
	var qz: PackedFloat32Array = state.momentum_z.to_float32_array()
	var sand: PackedFloat32Array = state.sand.to_float32_array()
	var rock: PackedFloat32Array = state.rock.to_float32_array()
	var sediment: PackedFloat32Array = state.sediment.to_float32_array()
	var volume := _sum(h)
	var roi := 0.0
	var roi_max := 0.0
	for i in footprint:
		roi += h[i] * 0.015625
		roi_max = maxf(roi_max, h[i])
	var eta_peak := -INF
	var max_h := 0.0
	var max_speed := 0.0
	var finite := true
	var dry_momentum := true
	var native_limit := true
	for i in h.size():
		finite = finite and is_finite(h[i]) and h[i] >= 0.0 and is_finite(qx[i]) and is_finite(qz[i]) and is_finite(sand[i]) and sand[i] >= 0.0 and is_finite(sediment[i]) and sediment[i] >= 0.0
		max_h = maxf(max_h, h[i])
		if h[i] <= 0.001:
			dry_momentum = dry_momentum and qx[i] == 0.0 and qz[i] == 0.0
		else:
			eta_peak = maxf(eta_peak, rock[i] + sand[i] + h[i])
			var momentum := sqrt(qx[i] * qx[i] + qz[i] * qz[i])
			max_speed = maxf(max_speed, momentum / h[i])
			var limit := maxf(1.5, 3.0 * sqrt(9.81 * h[i])) * h[i]
			native_limit = native_limit and momentum <= limit + Protocol.cell_budget(0.0, limit)
	var relative_error := absf(volume - initial_volume) / maxf(initial_volume, 1e-12)
	var published: bool = state.water == state.published_water and state.sand == state.published_sand
	var sand_volume := _sum(sand)
	var sediment_volume := _sum(sediment)
	var sand_error := absf(sand_volume - initial_sand_volume) if is_finite(initial_sand_volume) else 0.0
	var sediment_error := absf(sediment_volume - initial_sediment_volume) if is_finite(initial_sediment_volume) else 0.0
	var solid_ok := sand_error <= maxf(1e-7, absf(initial_sand_volume) * 0.005) if is_finite(initial_sand_volume) else true
	solid_ok = solid_ok and (sediment_error <= maxf(1e-7, absf(initial_sediment_volume) * 0.005) if is_finite(initial_sediment_volume) else true)
	var center: int = (lab.profile.grid_size / 2) * lab.profile.grid_size + lab.profile.grid_size / 2
	var ok: bool = finite and dry_momentum and native_limit and published and solid_ok and relative_error <= 0.005 and lab.solver.overload_events == 0
	rows.append({"phase": ["B_legacy", "C_displacement", "D_velocity", "E_combined"][phase], "grid": lab.profile.grid_size,
		"pass": ok, "requested_sim_s": requested_time, "completed_tick": lab.completed_ticks,
		"actual_sim_s": lab.completed_ticks / 30.0, "wall_us": Time.get_ticks_usec() - run_wall_us,
		"generation": lab.generation, "revision": lab.solver.state_revision,
		"water_m3": volume, "water_relative_error": relative_error, "roi_water_m3": roi,
		"center_h_m": h[center], "roi_max_h_m": roi_max, "roi_mean_h_m": roi / maxf(footprint.size() * 0.015625, 1e-12),
		"sand_m3": sand_volume, "sediment_m3": sediment_volume, "sand_absolute_error_m3": sand_error,
		"sediment_absolute_error_m3": sediment_error, "solid_conservation_guard": solid_ok,
		"roi_migration_m3": initial_roi_volume - roi, "max_h_m": max_h,
		"eta_peak_wet_m": eta_peak, "max_speed_m_s": max_speed, "finite_nonnegative": finite,
		"dry_momentum_zero": dry_momentum, "original_solver_velocity_limit": native_limit,
		"max_substeps": lab.solver.max_substeps_used, "overload_events": lab.solver.overload_events,
		"published_complete": published, "prefix": prefix})
	_write(false, "running")

func _run() -> void:
	var failure := ""
	for size in [64, 256]:
		lab = load("res://tests/edit_validation/edit_gpu_water_" + ("numeric" if size == 64 else "brush") + "_lab.tscn").instantiate()
		root.add_child(lab)
		while not lab.ready_for_ticks and lab.last_error.is_empty(): await process_frame
		if not lab.last_error.is_empty():
			failure = lab.last_error
			break
		for policy in [0, 1]:
			await lab.reset_domain()
			phase = policy
			lab.water_policy = policy
			var prefix := "%d_%s" % [size, "B" if policy == 0 else "C"]
			var before: Dictionary = await _snapshot(prefix + "_before")
			initial_volume = _sum(before.water.to_float32_array())
			var result: Dictionary = await lab.apply_gpu_command(_command(1, 0.48))
			if not lab.last_error.is_empty() or result.get("status") != 1:
				failure = lab.last_error if not lab.last_error.is_empty() else "edit rejected"
				break
			_save(prefix + "_command_receipt.bin", lab.raw_receipt)
			var post: Dictionary = await _snapshot(prefix + "_post_edit")
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
			await _sample(prefix + "_tick000", 0.0)
			var ticks := [3, 8, 15, 30, 60, 150]
			var requested := [0.1, 0.25, 0.5, 1.0, 2.0, 5.0]
			for sample in ticks.size():
				await lab.advance_ticks(ticks[sample] - lab.completed_ticks)
				if not lab.last_error.is_empty():
					failure = lab.last_error
					break
				await _sample(prefix + "_tick%03d" % ticks[sample], requested[sample])
			if not failure.is_empty(): break
		await lab.shutdown()
		lab.queue_free()
		await process_frame
		lab = null
		if not failure.is_empty(): break
	var ok := failure.is_empty() and rows.size() == 28
	for row in rows: ok = ok and row.pass
	_write(ok, failure)
	if lab != null:
		await lab.shutdown()
		lab.queue_free()
	finished = true
	print("WATER_CURVE_COMPLETE pass=%s rows=%d" % [str(ok), rows.size()])
	quit(0 if ok else 1)
