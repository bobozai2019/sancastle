extends SceneTree

var output := ""
var checks := []
var lab: Node3D
var started := 0
var finished := false

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			output = arg.trim_prefix("--output=")
	started = Time.get_ticks_msec()
	call_deferred("_watchdog")
	call_deferred("_run")

func _watchdog() -> void:
	while not finished:
		if Time.get_ticks_msec() - started > 150000:
			printerr("SCENE_PROBE timeout")
			quit(1)
			return
		await process_frame

func _check(name: String, ok: bool, detail: Variant = null) -> void:
	checks.append({"name": name, "pass": ok, "detail": detail})
	if not ok:
		printerr("SCENE_PROBE failed: " + name)

func _save_state(prefix: String, fields: Dictionary) -> void:
	var index := {}
	for field in fields:
		var path: String = prefix + "_" + field + ".bin"
		var file := FileAccess.open(output.path_join(path), FileAccess.WRITE)
		file.store_buffer(fields[field])
		var context := HashingContext.new()
		context.start(HashingContext.HASH_SHA256)
		context.update(fields[field])
		index[field] = {"path": path, "bytes": fields[field].size(),
			"sha256": context.finish().hex_encode()}
	var file := FileAccess.open(output.path_join(prefix + "_index.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(index, "\t"))

func _same(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for key in a:
		if a[key] != b.get(key):
			return false
	return true

func _run() -> void:
	if output.is_empty():
		quit(1)
		return
	root.size = Vector2i(960, 540)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for scene_name in ["numeric", "brush"]:
		var packed: PackedScene = load("res://tests/edit_validation/edit_" + scene_name + "_lab.tscn")
		if packed == null:
			_check(scene_name + "_load", false)
			break
		lab = packed.instantiate()
		root.add_child(lab)
		while not lab.ready_for_ticks and lab.last_error.is_empty():
			await process_frame
		if not lab.last_error.is_empty():
			_check(scene_name + "_init", false, lab.last_error)
			break
		var initial: Dictionary = await lab.snapshot_state()
		var cpu_water := PackedFloat32Array()
		if scene_name == "numeric":
			var cpu_domain = preload("res://scripts/simulation/sand_water_domain.gd").new(64, 0.125)
			cpu_domain.sand = lab.domain.sand.duplicate()
			cpu_domain.water = lab.domain.water.duplicate()
			var cpu_solver = preload("res://scripts/water/reference/shallow_water_solver.gd").new(cpu_domain)
			for tick in 15:
				cpu_solver.step(1.0 / 30.0)
			cpu_water = cpu_domain.water.duplicate()
			var cpu_file := FileAccess.open(output.path_join("numeric_cpu_water_15ticks.bin"), FileAccess.WRITE)
			cpu_file.store_buffer(cpu_water.to_byte_array())
			_check("numeric_CPU_static_reference", cpu_domain.sim_tick == 15 and cpu_solver.overload_events == 0 and cpu_solver.negative_depth_events == 0)
		_save_state(scene_name + "_initial", initial)
		for i in 8:
			await process_frame
		var idle: Dictionary = await lab.snapshot_state()
		_check(scene_name + "_no_command_no_tick_identity", _same(initial, idle))
		var command := {"domain_id": lab.domain.domain_id, "generation": lab.generation,
			"sim_tick": 0, "command_id": 1, "kind": &"remove_sand", "shape": &"circle",
			"transform": {"position_m": Vector3.ZERO}, "radius_m": 0.75,
			"strength": 0.0, "amount_m3": 0.01, "seed": 101}
		var result: Dictionary = await lab.apply_cpu_command(command)
		var zero: Dictionary = await lab.snapshot_state()
		_check(scene_name + "_zero_strength_identity", _same(initial, zero) and lab.domain.tool_inventory_m3 == 2.0, result)
		await lab.advance_ticks(15)
		var stepped: Dictionary = await lab.snapshot_state()
		_save_state(scene_name + "_static_15ticks", stepped)
		var max_depth_drift := 0.0
		var max_q := 0.0
		var finite := true
		var h: PackedFloat32Array = stepped.water.to_float32_array()
		var initial_h: PackedFloat32Array = initial.water.to_float32_array()
		if scene_name == "numeric":
			var maximum_difference := 0.0
			var within_budget := true
			for i in cpu_water.size():
				maximum_difference = maxf(maximum_difference, absf(cpu_water[i] - h[i]))
				within_budget = within_budget and absf(cpu_water[i] - h[i]) <= preload("res://scripts/simulation/edit_validation/edit_protocol.gd").cell_budget(cpu_water[i], h[i])
			_check("numeric_CPU_GPU_static_frozen_budget", within_budget,
				{"maximum_difference_m": maximum_difference, "budget_source": "T01 eps_cell; strict reset identity remains separate"})
		var qx: PackedFloat32Array = stepped.momentum_x.to_float32_array()
		var qz: PackedFloat32Array = stepped.momentum_z.to_float32_array()
		for i in h.size():
			max_depth_drift = maxf(max_depth_drift, absf(h[i] - initial_h[i]))
			max_q = maxf(max_q, maxf(absf(qx[i]), absf(qz[i])))
			finite = finite and is_finite(h[i]) and h[i] >= 0.0 and is_finite(qx[i]) and is_finite(qz[i])
		_check(scene_name + "_static_CFL_15ticks", finite and max_depth_drift <= 0.0001 and max_q <= 0.000001 and lab.completed_ticks == 15,
			{"depth_drift_m": max_depth_drift, "max_q": max_q, "ticks": lab.completed_ticks,
			"source_m3": lab.solver.water_source_m3, "sink_m3": lab.solver.water_sink_m3,
			"overloads": lab.solver.overload_events})
		await lab.inject_boundary(0.02)
		var injected: Dictionary = await lab.snapshot_state()
		_save_state(scene_name + "_source_injection", injected)
		var source_delta := _water_total(injected, 0.015625) - _water_total(stepped, 0.015625)
		var ledger_delta: float = lab.solver.water_source_m3 - lab.solver.water_sink_m3
		_check(scene_name + "_actual_source_ledger", absf(source_delta - ledger_delta) <= 0.0000001 and ledger_delta > 0.0,
			{"field_delta_m3": source_delta, "ledger_delta_m3": ledger_delta})
		_check(scene_name + "_missing_source_negative_control", absf(source_delta) > 0.0000001)
		var corrupt := injected.duplicate(true)
		var corrupt_h: PackedFloat32Array = injected.water.to_float32_array()
		corrupt_h[0] = 0.0
		corrupt.water = corrupt_h.to_byte_array()
		_check(scene_name + "_deleted_water_negative_control", absf(_water_total(corrupt, 0.015625) - _water_total(injected, 0.015625)) > 0.0000001)
		await lab.reset_domain()
		var reset: Dictionary = await lab.snapshot_state()
		_save_state(scene_name + "_reset", reset)
		_check(scene_name + "_reset_identity", _same(initial, reset) and lab.generation == 2 and lab.completed_ticks == 0)
		_check(scene_name + "_collision_chunks", lab.collision_proxy.applied_revisions.size() == (lab.profile.grid_size / 32) * (lab.profile.grid_size / 32), lab.collision_proxy.applied_revisions.size())
		for i in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join(scene_name + ".png"))
		var file := FileAccess.open(output.path_join(scene_name + "_effective.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(lab.effective_profile, "\t"))
		await lab.shutdown()
		lab.queue_free()
		await process_frame
		lab = null
	var ok := true
	for check in checks:
		ok = ok and check.pass
	finished = true
	var file := FileAccess.open(output.path_join("scene_probe.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass": ok, "checks": checks, "engine": Engine.get_version_info(),
		"adapter": RenderingServer.get_video_adapter_name(), "purpose": "G1 lab initialization/reset/static checks; no candidate or cost verdict"}, "\t"))
	print("SCENE_PROBE_COMPLETE " + JSON.stringify(checks))
	quit(0 if ok else 1)

func _water_total(fields: Dictionary, area: float) -> float:
	var total := 0.0
	for value in fields.water.to_float32_array():
		total += value * area
	return total
