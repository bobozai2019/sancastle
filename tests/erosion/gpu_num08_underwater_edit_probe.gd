extends SceneTree

const GRID := 256
const CELL_AREA := 0.125 * 0.125
const TARGET_TICKS := 1800

var preview: Node3D
var readback := PackedByteArray()
var finished := false
var started_ms := 0
var csv_rows := PackedStringArray([
	"event,tick,time_s,water_source_m3,water_sink_m3,last_audit_revision,last_audit_water_m3,last_audit_negative_cells,last_audit_invalid_cells,exact_water_m3"])


func _init() -> void:
	call_deferred("_begin")


func _begin() -> void:
	var scene: PackedScene = load("res://scenes/gpu_water_preview.tscn")
	if scene == null:
		_fail("NUM-08 preview scene missing")
		return
	preview = scene.instantiate()
	preview.enable_erosion = true
	preview.preset_index = 1
	root.add_child(preview)
	started_ms = Time.get_ticks_msec()
	call_deferred("_watchdog")
	call_deferred("_run")


func _run() -> void:
	while preview.completed_ticks < 10:
		if not preview.last_error.is_empty():
			_fail(preview.last_error)
			return
		await process_frame
	preview.playing = false
	while preview.tick_pending:
		await process_frame
	var before_water: PackedFloat32Array = await _read_field("water")
	var before_sand: PackedFloat32Array = await _read_field("sand")
	if finished:
		return
	var edit_cell := -1
	for z in range(32, GRID - 32):
		for x in range(32, GRID - 32):
			var i: int = z * GRID + x
			if before_water[i] > 0.05 and before_sand[i] > 0.05:
				edit_cell = i
				break
		if edit_cell >= 0:
			break
	if edit_cell < 0:
		_fail("NUM-08 no wet sand cell for edit")
		return
	var x: int = edit_cell % GRID
	var z: int = edit_cell / GRID
	var world := Vector3((float(x) + 0.5) * 0.125 - 16.0, 0.0,
		(float(z) + 0.5) * 0.125 - 16.0)
	var source_before: float = preview.solver.water_source_m3
	var sink_before: float = preview.solver.water_sink_m3
	var water_before_m3 := _water_volume(before_water)
	_csv_row("before_edit", water_before_m3)
	var edit_error: StringName = preview._submit_brush(&"remove_sand", 0.01,
		world, world, &"circle")
	if not edit_error.is_empty():
		_fail("NUM-08 underwater dig rejected: " + String(edit_error))
		return
	var prior_batches: int = preview.completed_patch_batches
	while preview.completed_patch_batches == prior_batches or preview.tick_pending:
		await process_frame
	var dug_water: PackedFloat32Array = await _read_field("water")
	var dug_sand: PackedFloat32Array = await _read_field("sand")
	if finished:
		return
	var dig_delta := _max_delta(before_sand, dug_sand)
	if dig_delta < 0.001 or _max_delta(before_water, dug_water) > 0.0000001:
		_fail("NUM-08 dig changed no sand or silently remapped water")
		return
	if absf(_water_volume(dug_water) - water_before_m3) > 0.000001:
		_fail("NUM-08 dig changed water volume")
		return
	_csv_row("after_dig", _water_volume(dug_water))
	prior_batches = preview.completed_patch_batches
	edit_error = preview._submit_brush(&"place_sand", 0.01,
		world, world, &"circle")
	if not edit_error.is_empty():
		_fail("NUM-08 underwater fill rejected: " + String(edit_error))
		return
	while preview.completed_patch_batches == prior_batches or preview.tick_pending:
		await process_frame
	var filled_water: PackedFloat32Array = await _read_field("water")
	var filled_sand: PackedFloat32Array = await _read_field("sand")
	if finished:
		return
	var fill_delta := _max_delta(dug_sand, filled_sand)
	if fill_delta < 0.001 or _max_delta(before_water, filled_water) > 0.0000001:
		_fail("NUM-08 fill changed no sand or silently remapped water")
		return
	if absf(_water_volume(filled_water) - water_before_m3) > 0.000001:
		_fail("NUM-08 fill changed water volume")
		return
	_csv_row("after_fill", _water_volume(filled_water))
	if absf(preview.solver.water_source_m3 - source_before) > 0.0000001 or \
			absf(preview.solver.water_sink_m3 - sink_before) > 0.0000001:
		_fail("NUM-08 edit changed water source/sink ledger")
		return
	preview.playing = true
	var last_logged_tick: int = preview.completed_ticks
	while preview.completed_ticks < TARGET_TICKS:
		if not preview.last_error.is_empty():
			_fail(preview.last_error)
			return
		await process_frame
		if preview.completed_ticks != last_logged_tick:
			last_logged_tick = preview.completed_ticks
			_csv_row("run", NAN)
	preview.playing = false
	while preview.tick_pending or preview.audit_revision < preview.solver.state_revision - 4:
		await process_frame
	var final_water: PackedFloat32Array = await _read_field("water")
	if finished:
		return
	var final_water_m3 := _water_volume(final_water)
	var expected_m3: float = water_before_m3 + \
			(preview.solver.water_source_m3 - source_before) - \
			(preview.solver.water_sink_m3 - sink_before)
	var closure := absf(final_water_m3 - expected_m3)
	if closure > 0.01 or preview.audit_negative_cells != 0 or \
			preview.audit_invalid_cells != 0 or \
			absf(final_water_m3 - preview.audit_water_m3) > 0.005:
		_fail("NUM-08 60-second water closure/audit failed closure=%.7f audit=%.7f" % [
			closure, absf(final_water_m3 - preview.audit_water_m3)])
		return
	_csv_row("final_exact", final_water_m3)
	var csv_path := "res://test_output/sandcastle_water_sand_coupling/验收/T04_num08_gpu_256_1800.csv"
	var csv := FileAccess.open(csv_path, FileAccess.WRITE)
	if csv == null:
		_fail("NUM-08 CSV could not be written")
		return
	csv.store_string("\n".join(csv_rows) + "\n")
	csv.close()
	print("PASS: GPU NUM-08 underwater dig/fill 256-square cell=%d,%d wet_depth=%.6f tick=%d dig_delta=%.6f fill_delta=%.6f edit_water_delta=%.9f 60s_water_closure=%.9f audit_delta=%.9f invalid=%d negative=%d CSV=%s" % [
		x, z, before_water[edit_cell], preview.completed_ticks, dig_delta, fill_delta,
		_max_delta(before_water, filled_water), closure,
		absf(final_water_m3 - preview.audit_water_m3),
		preview.audit_invalid_cells, preview.audit_negative_cells, csv_path])
	_finish(0)


func _csv_row(event: String, exact_water_m3: float) -> void:
	csv_rows.append("%s,%d,%.6f,%.9f,%.9f,%d,%.9f,%d,%d,%.9f" % [
		event, preview.completed_ticks, float(preview.completed_ticks) / 30.0,
		preview.solver.water_source_m3, preview.solver.water_sink_m3,
		preview.audit_revision, preview.audit_water_m3,
		preview.audit_negative_cells, preview.audit_invalid_cells, exact_water_m3])


func _read_field(field: String) -> PackedFloat32Array:
	readback = PackedByteArray()
	RenderingServer.call_on_render_thread(_render_read_field.bind(field))
	while readback.is_empty() and not finished:
		await process_frame
	return readback.to_float32_array()


func _render_read_field(field: String) -> void:
	var error: Error = preview.solver.request_data(field, _on_data)
	if error != OK:
		call_deferred("_fail", "NUM-08 %s readback failed: %d" % [field, error])


func _on_data(data: PackedByteArray) -> void:
	call_deferred("_record_data", data)


func _record_data(data: PackedByteArray) -> void:
	if not finished:
		readback = data


func _water_volume(values: PackedFloat32Array) -> float:
	var total := 0.0
	for value in values:
		if not is_finite(value) or value < -0.000001:
			return NAN
		total += value * CELL_AREA
	return total


func _max_delta(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	if a.size() != GRID * GRID or b.size() != a.size():
		return INF
	var maximum := 0.0
	for i in a.size():
		maximum = maxf(maximum, absf(a[i] - b[i]))
	return maximum


func _watchdog() -> void:
	if finished:
		return
	if Time.get_ticks_msec() - started_ms > 180000:
		_fail("NUM-08 timed out at tick %d" % preview.completed_ticks)
		return
	await process_frame
	call_deferred("_watchdog")


func _fail(message: String) -> void:
	if finished:
		return
	printerr("FAIL: " + message)
	_finish(1)


func _finish(code: int) -> void:
	finished = true
	if preview != null:
		preview.queue_free()
	for frame in 3:
		await process_frame
	quit(code)
