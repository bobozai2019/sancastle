extends SceneTree

const Domain = preload("res://scripts/simulation/sand_water_domain.gd")
const Solver = preload("res://scripts/simulation/gpu_shallow_solver.gd")
const Coupler = preload("res://scripts/simulation/erosion/gpu_sediment_coupler.gd")
const SandAudit = preload("res://scripts/simulation/gpu_sand_audit.gd")
const Queue = preload("res://scripts/sand/tool_command_queue.gd")
const Scenarios = preload("res://scripts/scenarios/standard_scenarios.gd")
const DELTA_S := 1.0 / 30.0

var grid_size := 64
var ticks := 300
var build_berm := false
var tick_index := 0
var domain: SandWaterDomain
var initial_sand_values := PackedFloat32Array()
var solver: SandcastleGpuShallowSolver
var coupler: SandcastleGpuSedimentCoupler
var sand_audit: SandcastleGpuSandAudit
var spirvs: Array[RDShaderSPIRV] = []
var cfl_data := PackedByteArray()
var cfl_revision := -1
var substeps := 0
var tide_ready := false
var cfl_ready := false
var water_ready := false
var sand_ready := false
var snapshot_ready := false
var water_result := {}
var sand_result := {}
var snapshot_data := {}
var previous_snapshot_sand := PackedFloat32Array()
var initial_sand_m3 := 0.0
var initial_water_m3 := 0.0
var max_sand_closure_m3 := 0.0
var max_water_closure_m3 := 0.0
var max_sediment_m3 := 0.0
var interval_centroid_min := INF
var interval_centroid_max := -INF
var minimum_channel_erosion_share := INF
var final_downstream_deposit_m3 := 0.0
var berm_inventory_m3 := 0.0
var berm_changed_cells := 0
var rows := PackedStringArray([
	"tick,time_s,substeps,water_m3,water_source_m3,water_sink_m3,water_closure_m3,sand_m3,sediment_m3,sand_source_m3,sand_sink_m3,sand_closure_m3,water_invalid,water_negative,sand_invalid,sand_negative,erosion_centroid_x,erosion_channel_m3,erosion_bank_m3,downstream_deposit_m3,channel_flux_m3ps,interval_erosion_centroid_x,interval_erosion_channel_m3,interval_erosion_bank_m3,interval_downstream_deposit_m3,interval_hotspot_z,interval_hotspot_m3,downstream_cross_north_share,downstream_cross_flux_m3ps"])
var finished := false
var started_ms := 0


func _init() -> void:
	call_deferred("_begin")


func _begin() -> void:
	var requested_size := int(OS.get_environment("SANDCASTLE_NUM09_GRID"))
	var requested_ticks := int(OS.get_environment("SANDCASTLE_NUM09_TICKS"))
	if requested_size > 0:
		grid_size = requested_size
	if requested_ticks > 0:
		ticks = requested_ticks
	build_berm = OS.get_environment("SANDCASTLE_NUM09_BERM") == "1"
	if grid_size not in [64, 256] or ticks < 1 or \
			(build_berm and (grid_size != 256 or ticks < 1200)):
		_fail("NUM-09 arguments invalid")
		return
	for path in [
		"res://shaders/simulation/shallow_edge_flux.glsl",
		"res://shaders/simulation/shallow_drain_scale.glsl",
		"res://shaders/simulation/shallow_update_state.glsl",
		"res://shaders/simulation/shallow_tide_boundary.glsl",
		"res://shaders/simulation/shallow_cfl_tiles.glsl",
		"res://shaders/simulation/shallow_gauge_depth.glsl",
		"res://shaders/simulation/shallow_audit_tiles.glsl",
		"res://shaders/simulation/shallow_tool_patch.glsl",
		"res://shaders/simulation/erosion/sediment_step.glsl",
		"res://shaders/simulation/erosion/copy_after_boundary.glsl",
		"res://shaders/simulation/shallow_sand_audit_tiles.glsl"]:
		var file: RDShaderFile = load(path)
		if file == null or file.get_spirv() == null:
			_fail("NUM-09 shader import missing: " + path)
			return
		spirvs.append(file.get_spirv())
	domain = Domain.new(grid_size, 0.125)
	if not Scenarios.initialize(domain, 1):
		_fail("NUM-09 curved channel scene initialization failed")
		return
	initial_sand_m3 = domain.total_sand_m3(true)
	initial_sand_values = domain.sand.duplicate()
	initial_water_m3 = domain.total_water_m3()
	started_ms = Time.get_ticks_msec()
	RenderingServer.call_on_render_thread(_render_setup)
	call_deferred("_watchdog")


func _render_setup() -> void:
	solver = Solver.new()
	if not solver.initialize(RenderingServer.get_rendering_device(), domain,
			spirvs[0], spirvs[1], spirvs[2], spirvs[3], spirvs[4], spirvs[5],
			spirvs[6], spirvs[7]):
		call_deferred("_fail", "NUM-09 shallow solver initialization failed")
		return
	coupler = Coupler.new()
	if not coupler.initialize(solver, spirvs[8], spirvs[9]):
		call_deferred("_fail", "NUM-09 sediment coupler initialization failed")
		return
	sand_audit = SandAudit.new()
	if not sand_audit.initialize(solver, spirvs[10]):
		call_deferred("_fail", "NUM-09 sand audit initialization failed")
		return
	_render_begin_tick()


func _render_begin_tick() -> void:
	var level: float = Scenarios.tide_level(float(tick_index) * DELTA_S)
	if not solver.dispatch_tide_boundary(level) or not coupler.dispatch_after_boundary():
		call_deferred("_fail", "NUM-09 boundary/copy dispatch failed at %d" % tick_index)
		return
	if solver.request_tide_ledger(_on_ledger) != OK or \
			solver.request_cfl_tiles(_on_cfl) != OK:
		call_deferred("_fail", "NUM-09 boundary diagnostics failed at %d" % tick_index)


func _on_ledger(_source: float, _sink: float, _revision: int, valid: bool) -> void:
	call_deferred("_record_ledger", valid)


func _record_ledger(valid: bool) -> void:
	if finished:
		return
	if not valid:
		_fail("NUM-09 invalid tide ledger at %d" % tick_index)
		return
	tide_ready = true
	_maybe_dispatch_tick()


func _on_cfl(data: PackedByteArray, revision: int) -> void:
	call_deferred("_record_cfl", data, revision)


func _record_cfl(data: PackedByteArray, revision: int) -> void:
	if finished:
		return
	substeps = solver.substeps_from_cfl(DELTA_S, data)
	if substeps < 1 or substeps > solver.MAX_SUBSTEPS or revision != solver.state_revision:
		_fail("NUM-09 invalid CFL/substeps at %d: %d" % [tick_index, substeps])
		return
	cfl_data = data
	cfl_revision = revision
	cfl_ready = true
	_maybe_dispatch_tick()


func _maybe_dispatch_tick() -> void:
	if tide_ready and cfl_ready:
		tide_ready = false
		cfl_ready = false
		RenderingServer.call_on_render_thread(_render_finish_tick.bind(cfl_revision, substeps))


func _render_finish_tick(revision: int, count: int) -> void:
	if revision != solver.state_revision:
		call_deferred("_fail", "NUM-09 stale CFL revision")
		return
	for step in count:
		if not solver.dispatch_substep(DELTA_S / float(count)) or \
				not coupler.dispatch_after_water_substep(DELTA_S / float(count)):
			call_deferred("_fail", "NUM-09 coupled substep failed at %d/%d" % [tick_index, step])
			return
	if solver.request_audit_tiles(_on_water_audit) != OK or \
			sand_audit.request(_on_sand_audit) != OK:
		call_deferred("_fail", "NUM-09 account audit request failed at %d" % tick_index)
		return
	if _is_snapshot_tick():
		for field in ["sand", "flux"]:
			if solver.request_data(field, _on_snapshot.bind(field)) != OK:
				call_deferred("_fail", "NUM-09 snapshot readback failed: " + field)
				return


func _is_snapshot_tick() -> bool:
	return tick_index == 0 or (tick_index + 1) % 300 == 0 or tick_index + 1 == ticks


func _on_water_audit(data: PackedByteArray, _revision: int) -> void:
	call_deferred("_record_water_audit", data)


func _record_water_audit(data: PackedByteArray) -> void:
	if finished:
		return
	water_result = solver.decode_audit_tiles(data)
	water_ready = true
	_maybe_commit_tick()


func _on_sand_audit(data: PackedByteArray, _revision: int) -> void:
	call_deferred("_record_sand_audit", data)


func _record_sand_audit(data: PackedByteArray) -> void:
	if finished:
		return
	sand_result = sand_audit.decode(data)
	sand_ready = true
	_maybe_commit_tick()


func _on_snapshot(data: PackedByteArray, field: String) -> void:
	call_deferred("_record_snapshot", data, field)


func _record_snapshot(data: PackedByteArray, field: String) -> void:
	if finished:
		return
	snapshot_data[field] = data.to_float32_array()
	if snapshot_data.size() == 2:
		snapshot_ready = true
		_maybe_commit_tick()


func _maybe_commit_tick() -> void:
	if not water_ready or not sand_ready or not snapshot_ready:
		return
	if not water_result.get("valid", false) or not sand_result.get("valid", false) or \
			water_result.invalid_cells != 0 or water_result.negative_cells != 0 or \
			sand_result.invalid_cells != 0 or sand_result.negative_cells != 0:
		_fail("NUM-09 invalid/negative completed state at %d" % tick_index)
		return
	var water_closure: float = absf(water_result.water_m3 - initial_water_m3 - \
		solver.water_source_m3 + solver.water_sink_m3)
	var sand_closure: float = absf(sand_result.sand_m3 + sand_result.sediment_m3 + \
		domain.tool_inventory_m3 - initial_sand_m3 - domain.sand_source_m3 + \
		domain.sand_sink_m3)
	max_water_closure_m3 = maxf(max_water_closure_m3, water_closure)
	max_sand_closure_m3 = maxf(max_sand_closure_m3, sand_closure)
	max_sediment_m3 = maxf(max_sediment_m3, sand_result.sediment_m3)
	if water_closure > maxf(0.001, initial_water_m3 * 0.005) or \
			sand_closure > maxf(0.001, initial_sand_m3 * 0.01):
		_fail("NUM-09 account did not close at %d: water %.6f sand %.6f" % [
			tick_index, water_closure, sand_closure])
		return
	var metrics := {"erosion_centroid_x": "", "erosion_channel_m3": "",
		"erosion_bank_m3": "", "downstream_deposit_m3": "",
		"channel_flux_m3ps": "", "interval_erosion_centroid_x": "",
		"interval_erosion_channel_m3": "", "interval_erosion_bank_m3": "",
		"interval_downstream_deposit_m3": "", "interval_hotspot_z": "",
		"interval_hotspot_m3": "", "downstream_cross_north_share": "",
		"downstream_cross_flux_m3ps": ""}
	if not snapshot_data.is_empty():
		metrics = _snapshot_metrics()
		if metrics.is_empty():
			return
		if tick_index > 0:
			var centroid := float(metrics.interval_erosion_centroid_x)
			interval_centroid_min = minf(interval_centroid_min, centroid)
			interval_centroid_max = maxf(interval_centroid_max, centroid)
			var channel_erosion := float(metrics.interval_erosion_channel_m3)
			var bank_erosion := float(metrics.interval_erosion_bank_m3)
			if channel_erosion + bank_erosion > 0.0:
				minimum_channel_erosion_share = minf(minimum_channel_erosion_share,
					channel_erosion / (channel_erosion + bank_erosion))
		final_downstream_deposit_m3 = float(metrics.downstream_deposit_m3)
	rows.append(",".join([
		str(tick_index + 1), "%.6f" % (float(tick_index + 1) * DELTA_S),
		str(substeps), "%.9f" % water_result.water_m3,
		"%.9f" % solver.water_source_m3, "%.9f" % solver.water_sink_m3,
		"%.9f" % water_closure, "%.9f" % sand_result.sand_m3,
		"%.9f" % sand_result.sediment_m3,
		"%.9f" % domain.sand_source_m3, "%.9f" % domain.sand_sink_m3,
		"%.9f" % sand_closure,
		str(water_result.invalid_cells), str(water_result.negative_cells),
		str(sand_result.invalid_cells), str(sand_result.negative_cells),
		str(metrics.erosion_centroid_x), str(metrics.erosion_channel_m3),
		str(metrics.erosion_bank_m3), str(metrics.downstream_deposit_m3),
		str(metrics.channel_flux_m3ps), str(metrics.interval_erosion_centroid_x),
		str(metrics.interval_erosion_channel_m3), str(metrics.interval_erosion_bank_m3),
		str(metrics.interval_downstream_deposit_m3),
		str(metrics.interval_hotspot_z), str(metrics.interval_hotspot_m3),
		str(metrics.downstream_cross_north_share),
		str(metrics.downstream_cross_flux_m3ps)]))
	var pending_berm := build_berm and tick_index + 1 == 900
	var patch := {}
	if pending_berm:
		patch = _prepare_player_berm(snapshot_data.get("sand", PackedFloat32Array()))
		if patch.is_empty():
			return
	tick_index += 1
	water_ready = false
	sand_ready = false
	snapshot_ready = not _is_snapshot_tick()
	snapshot_data.clear()
	if tick_index == ticks:
		_finish_success()
	elif pending_berm:
		RenderingServer.call_on_render_thread(_render_apply_berm.bind(patch))
	else:
		RenderingServer.call_on_render_thread(_render_begin_tick)


func _prepare_player_berm(snapshot_sand: PackedFloat32Array) -> Dictionary:
	if snapshot_sand.size() != grid_size * grid_size:
		_fail("NUM-09 berm snapshot missing")
		return {}
	domain.sand = snapshot_sand.duplicate()
	domain.sim_tick = tick_index + 1
	var queue: ToolCommandQueue = Queue.new(domain)
	var center_nz := 0.5 + 0.11 * sin(0.40 * TAU * 1.5)
	var center_z_m := (center_nz - 0.5) * float(grid_size) * domain.cell_size_m
	var x_m := (0.40 - 0.5) * float(grid_size) * domain.cell_size_m
	var commands: Array[Dictionary] = [
		{"kind": &"remove_sand", "position": Vector3(5.0, 0.0, -10.0),
			"end": Vector3(9.0, 0.0, -10.0)},
		{"kind": &"place_sand", "position": Vector3(x_m, 0.0, center_z_m - 2.0),
			"end": Vector3(x_m, 0.0, center_z_m + 0.4)}]
	for i in commands.size():
		var command: Dictionary = commands[i]
		var error: StringName = queue.submit({
			"domain_id": domain.domain_id, "generation": domain.generation,
			"sim_tick": domain.sim_tick, "command_id": i + 1,
			"kind": command.kind, "shape": &"swept_segment",
			"transform": {"position_m": command.position,
				"end_position_m": command.end}, "radius_m": 0.38,
			"strength": 1.0, "amount_m3": 0.6, "seed": i + 901})
		if not error.is_empty():
			_fail("NUM-09 berm command rejected: " + String(error))
			return {}
	var results: Array[Dictionary] = queue.apply_due_commands(domain.sim_tick)
	if results.size() != 2 or results[0].status != &"applied" or \
			results[1].status != &"applied":
		_fail("NUM-09 berm edit failed: " + str(results))
		return {}
	var patch: Dictionary = queue.build_gpu_patch_batch(results)
	if patch.count < 10:
		_fail("NUM-09 berm patch too small")
		return {}
	berm_inventory_m3 = domain.tool_inventory_m3
	berm_changed_cells = patch.count
	previous_snapshot_sand = domain.sand.duplicate()
	return patch


func _render_apply_berm(patch: Dictionary) -> void:
	if not solver.dispatch_tool_patch(patch.data, patch.count):
		call_deferred("_fail", "NUM-09 berm GPU patch failed")
		return
	_render_begin_tick()


func _snapshot_metrics() -> Dictionary:
	var sand: PackedFloat32Array = snapshot_data["sand"]
	var flux: PackedFloat32Array = snapshot_data["flux"]
	if sand.size() != grid_size * grid_size or flux.size() != grid_size * grid_size * 4:
		_fail("NUM-09 snapshot size mismatch")
		return {}
	var erosion_channel := 0.0
	var erosion_bank := 0.0
	var downstream_deposit := 0.0
	var channel_flux := 0.0
	var erosion_x_weighted := 0.0
	var erosion_total := 0.0
	var interval_erosion_channel := 0.0
	var interval_erosion_bank := 0.0
	var interval_downstream_deposit := 0.0
	var interval_erosion_x_weighted := 0.0
	var interval_erosion_total := 0.0
	var interval_hotspot_z_weighted := 0.0
	var interval_hotspot_total := 0.0
	var downstream_cross_north := 0.0
	var downstream_cross_total := 0.0
	var area: float = domain.cell_area_m2
	for z in grid_size:
		for x in grid_size:
			var i: int = domain.index(x, z)
			if not is_finite(sand[i]) or sand[i] < -0.000001:
				_fail("NUM-09 snapshot invalid sand at %d" % i)
				return {}
			var nx := float(x) / float(grid_size - 1)
			var nz := float(z) / float(grid_size - 1)
			var channel_center := 0.5 + 0.11 * sin(nx * TAU * 1.5)
			var in_channel := absf(nz - channel_center) < 0.09
			if x == roundi(float(grid_size - 1) * 0.43) and in_channel:
				var downstream_rate: float = maxf(flux[i * 4 + 1], 0.0)
				downstream_cross_total += downstream_rate
				if nz >= channel_center:
					downstream_cross_north += downstream_rate
			var sand_change: float = initial_sand_values[i] - sand[i]
			if sand_change > 0.0:
				var eroded: float = sand_change * area
				erosion_total += eroded
				erosion_x_weighted += eroded * nx
				if in_channel:
					erosion_channel += eroded
				else:
					erosion_bank += eroded
			elif nx > 0.7:
				downstream_deposit += -sand_change * area
			var prior_sand: float = initial_sand_values[i] if previous_snapshot_sand.is_empty() else \
				previous_snapshot_sand[i]
			var interval_change: float = prior_sand - sand[i]
			if interval_change > 0.0:
				var interval_eroded: float = interval_change * area
				interval_erosion_total += interval_eroded
				interval_erosion_x_weighted += interval_eroded * nx
				if nx >= 0.42 and nx <= 0.62:
					interval_hotspot_z_weighted += interval_eroded * nz
					interval_hotspot_total += interval_eroded
				if in_channel:
					interval_erosion_channel += interval_eroded
				else:
					interval_erosion_bank += interval_eroded
			elif nx > 0.7:
				interval_downstream_deposit += -interval_change * area
			for direction in 4:
				var rate: float = flux[i * 4 + direction]
				if not is_finite(rate) or rate < -0.000001:
					_fail("NUM-09 snapshot invalid water flux at %d" % i)
					return {}
				if in_channel:
					channel_flux += maxf(rate, 0.0)
	previous_snapshot_sand = sand.duplicate()
	return {"erosion_centroid_x": "%.6f" % (erosion_x_weighted / maxf(erosion_total, 1e-12)),
		"erosion_channel_m3": "%.9f" % erosion_channel,
		"erosion_bank_m3": "%.9f" % erosion_bank,
		"downstream_deposit_m3": "%.9f" % downstream_deposit,
		"channel_flux_m3ps": "%.9f" % channel_flux,
		"interval_erosion_centroid_x": "%.6f" % (interval_erosion_x_weighted / maxf(interval_erosion_total, 1e-12)),
		"interval_erosion_channel_m3": "%.9f" % interval_erosion_channel,
		"interval_erosion_bank_m3": "%.9f" % interval_erosion_bank,
		"interval_downstream_deposit_m3": "%.9f" % interval_downstream_deposit,
		"interval_hotspot_z": "%.6f" % (interval_hotspot_z_weighted / \
			maxf(interval_hotspot_total, 1e-12)),
		"interval_hotspot_m3": "%.9f" % interval_hotspot_total,
		"downstream_cross_north_share": "%.6f" % (downstream_cross_north / \
			maxf(downstream_cross_total, 1e-12)),
		"downstream_cross_flux_m3ps": "%.9f" % downstream_cross_total}


func _finish_success() -> void:
	if not build_berm and grid_size == 256 and ticks >= 9000 and \
			(interval_centroid_max - interval_centroid_min < 0.20 or \
			minimum_channel_erosion_share < 0.80 or \
			final_downstream_deposit_m3 < 0.01 or max_sediment_m3 < 0.1):
		_fail("NUM-09 hotspot/deposition gate failed: x_range=%.6f channel_share=%.6f downstream=%.6f suspended=%.6f" % [
			interval_centroid_max - interval_centroid_min,
			minimum_channel_erosion_share, final_downstream_deposit_m3,
			max_sediment_m3])
		return
	var path := "res://test_output/sandcastle_water_sand_coupling/验收/T04_num09_gpu_%d_%d%s.csv" % [
		grid_size, ticks, "_berm" if build_berm else ""]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("NUM-09 CSV unavailable")
		return
	for row in rows:
		file.store_line(row)
	file.close()
	print("PASS: GPU NUM-09 numeric probe grid=%d ticks=%d berm=%s berm_cells=%d inventory=%.9f max_water_closure=%.9f max_sand_closure=%.9f max_sediment=%.9f hotspot_x_range=%.6f min_channel_share=%.6f downstream_deposit=%.6f CSV=%s" % [
		grid_size, ticks, str(build_berm), berm_changed_cells, berm_inventory_m3,
		max_water_closure_m3, max_sand_closure_m3,
		max_sediment_m3, interval_centroid_max - interval_centroid_min,
		minimum_channel_erosion_share, final_downstream_deposit_m3, path])
	_finish(0)


func _watchdog() -> void:
	if finished:
		return
	if Time.get_ticks_msec() - started_ms > 900000:
		_fail("NUM-09 GPU probe timed out at %d/%d" % [tick_index, ticks])
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
	RenderingServer.call_on_render_thread(_render_release)
	for frame in 3:
		await process_frame
	quit(code)


func _render_release() -> void:
	if sand_audit != null:
		sand_audit.release()
	if coupler != null:
		coupler.release()
	if solver != null:
		solver.release()
