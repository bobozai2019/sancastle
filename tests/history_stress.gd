extends SceneTree

const OUTPUT := "res://test_output/sandcastle_water_sand_coupling/验收/T01_history_100_tick_stress.csv"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: PackedScene = load("res://scenes/cpu_reference.tscn")
	if scene == null:
		printerr("FAIL: main scene unavailable")
		quit(1)
		return
	var demo = scene.instantiate()
	demo._reset_domain(0)
	demo.playing = false
	var initial_sand: float = demo.domain.total_sand_m3()
	var start_us := Time.get_ticks_usec()
	for n in 100:
		var position := Vector3(float(n % 10) * 0.65 - 2.925, 0.0,
			float(n / 10) * 0.65 - 2.925)
		demo._submit_brush(&"remove_sand", 0.003, position, position, &"circle")
		demo._step_simulation()
		if demo.command_history.size() != n + 1 or demo.domain.nan_events != 0:
			_fail("command %d did not apply cleanly" % n, demo)
			return
	var run_ms := float(Time.get_ticks_usec() - start_us) / 1000.0
	var before_hash := _state_hash(demo)
	var before_ledger: PackedStringArray = demo.audit_recorder.rows.duplicate()
	var before_tick: int = demo.domain.sim_tick
	start_us = Time.get_ticks_usec()
	if not demo._undo_command():
		_fail("cross-tick stress undo rejected", demo)
		return
	var undo_ms := float(Time.get_ticks_usec() - start_us) / 1000.0
	if demo.domain.sim_tick != before_tick or demo.command_history.size() != 99:
		_fail("cross-tick stress undo lost tick or history", demo)
		return
	start_us = Time.get_ticks_usec()
	if not demo._redo_command():
		_fail("cross-tick stress redo rejected", demo)
		return
	var redo_ms := float(Time.get_ticks_usec() - start_us) / 1000.0
	if _state_hash(demo) != before_hash or demo.audit_recorder.rows != before_ledger:
		_fail("cross-tick stress redo is not bitwise deterministic", demo)
		return
	var sand_error := absf(demo.domain.total_sand_m3() - initial_sand)
	if sand_error > 0.0001 or demo.domain.nan_events != 0 or demo.domain.clamped_sand_events != 0:
		_fail("cross-tick stress violates sand/finite invariant", demo)
		return
	var file := FileAccess.open(OUTPUT, FileAccess.WRITE)
	if file == null:
		_fail("stress CSV unavailable", demo)
		return
	file.store_csv_line(["commands", "ticks", "run_ms", "undo_ms", "redo_ms",
		"sand_error_m3", "nan_events", "clamped_sand_events", "state_hash"])
	file.store_csv_line(["100", str(before_tick), "%.3f" % run_ms, "%.3f" % undo_ms,
		"%.3f" % redo_ms, "%.9f" % sand_error, str(demo.domain.nan_events),
		str(demo.domain.clamped_sand_events), str(before_hash)])
	file.close()
	print("PASS: 100-command 100-tick history stress; undo %.1f ms redo %.1f ms" % [undo_ms, redo_ms])
	demo.free()
	quit(0)


func _state_hash(demo: Node3D) -> int:
	return hash([demo.domain.sim_tick, demo.domain.rock, demo.domain.sand,
		demo.domain.water, demo.domain.sediment, demo.domain.wetness,
		demo.domain.compaction, demo.domain.tool_inventory_m3,
		demo.domain.water_source_m3, demo.domain.water_sink_m3,
		demo.water_solver.momentum_x, demo.water_solver.momentum_y, demo.tide_time])


func _fail(message: String, demo: Node3D) -> void:
	printerr("FAIL: " + message)
	demo.free()
	quit(1)
