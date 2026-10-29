extends SceneTree

const Domain = preload("res://scripts/simulation/sand_water_domain.gd")
const GpuSolver = preload("res://scripts/simulation/gpu_shallow_solver.gd")
const GRID := 64
const DX := 0.125
const H0 := 0.12
const RADIUS := 0.75
const DT := 1.0 / 600.0
var output_directory := "res://test_output/sandcastle_test1_reverse_rebuild/evidence/deposit_inquiry_20261010/"
const TIMES := [0.0, 1.0 / 30.0, 0.1, 0.25, 0.5, 1.0, 2.0, 5.0]

var spirvs: Array[RDShaderSPIRV] = []
var solver: SandcastleGpuShallowSolver
var domain: SandWaterDomain
var changed := PackedInt32Array()
var readbacks := {}
var render_done := false
var failed := false
var case_id := ""
var rows: Array[Dictionary] = []
var initial_inside_m3 := 0.0
var initial_total_m3 := 0.0
var edits := PackedByteArray()
var started_ms := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	started_ms = Time.get_ticks_msec()
	var requested_output := OS.get_environment("SANDCASTLE_DEPOSIT_OUTPUT")
	if not requested_output.is_empty():
		output_directory = requested_output.trim_suffix("/") + "/"
		DirAccess.make_dir_recursive_absolute(output_directory)
	for shader in ["shallow_edge_flux", "shallow_drain_scale", "shallow_update_state",
			"shallow_tide_boundary", "shallow_cfl_tiles", "shallow_gauge_depth",
			"shallow_audit_tiles", "shallow_tool_patch"]:
		var file: RDShaderFile = load("res://shaders/simulation/" + shader + ".glsl")
		if file == null or file.get_spirv() == null:
			_fail("shader unavailable: " + shader)
			return
		spirvs.append(file.get_spirv())
	for config in [
			{"id": "no_edit", "height": 0.0, "shape": "disk"},
			{"id": "disk_low", "height": 0.05, "shape": "disk"},
			{"id": "disk_medium", "height": 0.2, "shape": "disk"},
			{"id": "disk_high", "height": 0.8, "shape": "disk"},
			{"id": "dome_high", "height": 0.8, "shape": "dome"}]:
		case_id = config.id
		domain = Domain.new(GRID, DX)
		domain.rock.fill(0.0)
		domain.sand.fill(0.0)
		domain.water.fill(H0)
		changed = PackedInt32Array()
		var stream := StreamPeerBuffer.new()
		stream.big_endian = false
		for z in GRID:
			for x in GRID:
				var radius := Vector2((float(x) + 0.5 - GRID / 2.0) * DX,
					(float(z) + 0.5 - GRID / 2.0) * DX).length()
				if radius >= RADIUS:
					continue
				var i := z * GRID + x
				changed.append(i)
				var height: float = config.height
				if config.shape == "dome":
					height *= 1.0 - radius * radius / (RADIUS * RADIUS)
				domain.sand[i] = height
				stream.put_32(i)
				stream.put_float(height)
				stream.put_float(0.0)
				stream.put_float(0.0)
		edits = stream.data_array
		var saved_sand := domain.sand.duplicate()
		domain.sand.fill(0.0)
		render_done = false
		RenderingServer.call_on_render_thread(_render_setup)
		while not render_done and not failed:
			await process_frame
		if failed:
			return
		readbacks = {}
		RenderingServer.call_on_render_thread(_render_read)
		while readbacks.size() != 4 and not failed:
			await process_frame
		if failed:
			return
		var before: PackedByteArray = readbacks.water
		render_done = false
		RenderingServer.call_on_render_thread(_render_patch)
		while not render_done and not failed:
			await process_frame
		domain.sand = saved_sand
		var advanced := 0
		for time_s in TIMES:
			var steps := roundi(time_s / DT)
			render_done = false
			RenderingServer.call_on_render_thread(_render_advance.bind(steps - advanced))
			while not render_done and not failed:
				await process_frame
			readbacks = {}
			RenderingServer.call_on_render_thread(_render_read)
			while readbacks.size() != 4 and not failed:
				await process_frame
			if failed:
				return
			if steps == 0 and readbacks.water != before:
				_fail("edit changed water field")
				return
			_measure(time_s)
			advanced = steps
		render_done = false
		RenderingServer.call_on_render_thread(_render_release)
		while not render_done and not failed:
			await process_frame
	var report := {"purpose": "Diagnostic of current GPU core, not competitor timing or release performance.",
		"grid": GRID, "dx_m": DX, "initial_depth_m": H0, "radius_m": RADIUS,
		"fixed_substep_s": DT, "tide": false, "erosion": false,
		"rows": rows, "elapsed_wall_ms": Time.get_ticks_msec() - started_ms}
	var output := FileAccess.open(output_directory + "godot_deposit_probe.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t"))
	output.close()
	for row in rows:
		print(JSON.stringify(row))
	print("PASS: underwater deposit diagnosis complete")
	quit(0)

func _render_setup() -> void:
	solver = GpuSolver.new()
	if not solver.initialize(RenderingServer.get_rendering_device(), domain,
			spirvs[0], spirvs[1], spirvs[2], spirvs[3], spirvs[4], spirvs[5], spirvs[6], spirvs[7]):
		call_deferred("_fail", "GPU init failed")
		return
	call_deferred("_done")

func _render_patch() -> void:
	if not solver.dispatch_tool_patch(edits, changed.size()):
		call_deferred("_fail", "patch failed")
		return
	call_deferred("_done")

func _render_advance(steps: int) -> void:
	for step in steps:
		if not solver.dispatch_substep(DT):
			call_deferred("_fail", "step failed")
			return
	call_deferred("_done")

func _render_read() -> void:
	for field in ["water", "sand", "momentum_x", "momentum_z"]:
		if solver.request_data(field, _on_data.bind(field)) != OK:
			call_deferred("_fail", "readback failed: " + field)

func _on_data(data: PackedByteArray, field: String) -> void:
	call_deferred("_record", data, field)

func _record(data: PackedByteArray, field: String) -> void:
	readbacks[field] = data

func _done() -> void:
	render_done = true

func _render_release() -> void:
	solver.release()
	call_deferred("_done")

func _measure(time_s: float) -> void:
	var h: PackedFloat32Array = readbacks.water.to_float32_array()
	var sand: PackedFloat32Array = readbacks.sand.to_float32_array()
	var qx: PackedFloat32Array = readbacks.momentum_x.to_float32_array()
	var qz: PackedFloat32Array = readbacks.momentum_z.to_float32_array()
	var total := 0.0
	var inside := 0.0
	var max_eta := 0.0
	var max_speed := 0.0
	var max_wave_speed := 0.0
	var min_h := INF
	var wet_inside := 0
	for i in h.size():
		if not is_finite(h[i]) or h[i] < -0.000001:
			_fail("invalid water")
			return
		total += h[i] * DX * DX
		min_h = minf(min_h, h[i])
		max_eta = maxf(max_eta, sand[i] + h[i])
		if h[i] > 0.001:
			var speed := Vector2(qx[i], qz[i]).length() / maxf(h[i], 0.005)
			max_speed = maxf(max_speed, speed)
			max_wave_speed = maxf(max_wave_speed, speed + sqrt(9.81 * h[i]))
	for i in changed:
		inside += h[i] * DX * DX
		if h[i] > 0.001:
			wet_inside += 1
	if time_s == 0.0:
		initial_inside_m3 = inside
		initial_total_m3 = total
	var center := (GRID / 2) * GRID + GRID / 2
	var row := {"case_id": case_id, "time_s": time_s,
		"inside_water_m3": inside, "inside_remaining_fraction": inside / initial_inside_m3,
		"center_depth_m": h[center], "max_eta_m": max_eta, "max_speed_mps": max_speed,
		"cfl_number": max_wave_speed * DT / DX,
		"min_depth_m": min_h, "wet_inside_cells": wet_inside,
		"water_m3": total, "water_closure_m3": total - initial_total_m3,
		"water_sha256": _sha256(readbacks.water)}
	rows.append(row)
	for field in readbacks:
		var path := output_directory + "%s_%04d_%s.bin" % [case_id, roundi(time_s * 1000.0), field]
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_buffer(readbacks[field])
		file.close()

func _sha256(data: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(data)
	return context.finish().hex_encode()

func _fail(message: String) -> void:
	if failed:
		return
	failed = true
	printerr("FAIL: " + message)
	quit(1)
