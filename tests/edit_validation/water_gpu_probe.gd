extends SceneTree

const Reference = preload("res://scripts/simulation/edit_validation/water_displacement_reference.gd")
const Protocol = preload("res://scripts/simulation/edit_validation/edit_protocol.gd")
var output := ""
var rows := []
var fields := {}
var grid_size := 64
var rd: RenderingDevice
var rids: Array[RID] = []
var shader_metadata := {}
var result_bytes := PackedByteArray()
var receipt_bytes := PackedByteArray()
var render_error := ""
var finished := false
var started := 0

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	started = Time.get_ticks_msec()
	call_deferred("_watchdog")
	call_deferred("_run")

func _watchdog() -> void:
	while not finished:
		if Time.get_ticks_msec() - started > 150000:
			_write(false, "water GPU timeout")
			quit(1)
			return
		await process_frame

func _write(ok: bool, error: String = "") -> void:
	var file := FileAccess.open(output.path_join("water_gpu_probe.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass": ok, "error": error, "rows": rows,
		"shader": shader_metadata, "scope": "setup buffers -> GPU candidate -> debug readback; no live commit or performance verdict"}, "\t"))

func _save(name: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(output.path_join(name), FileAccess.WRITE)
	file.store_buffer(bytes)

func _state(size: int) -> Dictionary:
	var state := {}
	for key in ["old_bed", "new_bed", "water", "sediment", "momentum_x", "momentum_z", "obstacle"]:
		var values := PackedFloat32Array()
		values.resize(size * size)
		values.fill(0.12 if key == "water" else 0.0)
		state[key] = values
	return state

func _cap(height: float, center_x: int = -1) -> void:
	if center_x == -1: center_x = grid_size / 2
	for z in grid_size:
		for x in grid_size:
			if Vector2((x + 0.5 - center_x) * 0.125, (z + 0.5 - grid_size / 2) * 0.125).length() <= 0.75:
				fields.new_bed[z * grid_size + x] = height

func _data_ready(data: PackedByteArray, receipt: bool) -> void:
	call_deferred("_record", data, receipt)

func _record(data: PackedByteArray, receipt: bool) -> void:
	if receipt: receipt_bytes = data
	else: result_bytes = data

func _render_dispatch(input: PackedByteArray, spirv: RDShaderSPIRV) -> void:
	rd = RenderingServer.get_rendering_device()
	var shader := rd.shader_create_from_spirv(spirv)
	var pipeline := rd.compute_pipeline_create(shader)
	var input_buffer := rd.storage_buffer_create(input.size(), input)
	var result_buffer := rd.storage_buffer_create(grid_size * grid_size * 16)
	var scratch_buffer := rd.storage_buffer_create(grid_size * grid_size * 20)
	var receipt_buffer := rd.storage_buffer_create(128)
	var buffers := [input_buffer, result_buffer, scratch_buffer, receipt_buffer]
	var uniforms: Array[RDUniform] = []
	for binding in 4:
		var uniform := RDUniform.new()
		uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		uniform.binding = binding
		uniform.add_id(buffers[binding])
		uniforms.append(uniform)
	var set_rid := rd.uniform_set_create(uniforms, shader, 0)
	rids = [set_rid, pipeline, shader, input_buffer, result_buffer, scratch_buffer, receipt_buffer]
	var push := PackedByteArray()
	push.resize(16)
	push.fill(0)
	push.encode_u32(0, grid_size)
	push.encode_float(4, 0.125)
	var list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list, pipeline)
	rd.compute_list_bind_uniform_set(list, set_rid, 0)
	rd.compute_list_set_push_constant(list, push, 16)
	rd.compute_list_dispatch(list, 1, 1, 1)
	rd.compute_list_end()
	var e1: Error = rd.buffer_get_data_async(result_buffer, _data_ready.bind(false))
	var e2: Error = rd.buffer_get_data_async(receipt_buffer, _data_ready.bind(true))
	if e1 != OK or e2 != OK: call_deferred("_set_error", "candidate readback unavailable")

func _set_error(error: String) -> void:
	render_error = error

func _release() -> void:
	for rid in rids:
		if rid.is_valid(): rd.free_rid(rid)
	rids.clear()
	call_deferred("_released")

var released := false
func _released() -> void: released = true

func _sum(values) -> float:
	var sum := 0.0
	for value in values: sum += value * 0.015625
	return sum

func _case(name: String, spirv: RDShaderSPIRV) -> void:
	var oracle: Dictionary = Reference.build(fields, grid_size, 0.125)
	var input := PackedByteArray()
	input.resize(grid_size * grid_size * 32)
	input.fill(0)
	for i in grid_size * grid_size:
		for field in 7:
			input.encode_float(i * 32 + field * 4, fields[["old_bed", "new_bed", "water", "sediment", "momentum_x", "momentum_z", "obstacle"][field]][i])
	var prefix := "%s_%d" % [name, grid_size]
	_save(prefix + "_input_f32.bin", input)
	result_bytes.clear()
	receipt_bytes.clear()
	RenderingServer.call_on_render_thread(_render_dispatch.bind(input, spirv))
	while (result_bytes.is_empty() or receipt_bytes.is_empty()) and render_error.is_empty(): await process_frame
	if not render_error.is_empty(): return
	_save(prefix + "_gpu_f32.bin", result_bytes)
	_save(prefix + "_receipt.bin", receipt_bytes)
	var values := result_bytes.to_float32_array()
	var candidate := {}
	var max_errors := {}
	var within_budget := true
	var finite := true
	for slot in 4:
		var key: String = ["water", "sediment", "momentum_x", "momentum_z"][slot]
		var data := PackedFloat32Array()
		data.resize(grid_size * grid_size)
		var max_error := 0.0
		for i in data.size():
			data[i] = values[i * 4 + slot]
			finite = finite and is_finite(data[i]) and (slot >= 2 or data[i] >= 0.0)
			if oracle.ok:
				var difference: float = absf(data[i] - oracle[key][i])
				max_error = maxf(max_error, difference)
				within_budget = within_budget and difference <= Protocol.cell_budget(fields[key][i], oracle[key][i])
		candidate[key] = data
		max_errors[key] = max_error
		if oracle.ok: _save(prefix + "_oracle_f64_" + key + ".bin", oracle[key].to_byte_array())
	var status := receipt_bytes.decode_u32(0)
	var closure := true
	var budgets := {}
	for slot in 4:
		var key: String = ["water", "sediment", "momentum_x", "momentum_z"][slot]
		if not oracle.ok:
			budgets[key] = {"not_applicable": "rejected input; raw candidate checked for byte identity"}
			continue
		var touched := PackedInt32Array()
		for i in grid_size * grid_size:
			if fields.water[i] > 0.001 and fields.obstacle[i] < 0.5: touched.append(i)
		var budget := Protocol.volume_budget(fields[key], candidate[key], 0.015625, touched)
		var loss := 0.0 if slot < 2 else receipt_bytes.decode_float(24 if slot == 2 else 28)
		var error: float = absf(_sum(candidate[key]) + loss - _sum(fields[key]))
		closure = closure and error <= budget.edit_m3
		budgets[key] = {"integral_error": error, "integral_budget": budget.edit_m3,
			"unit": "m3" if slot < 2 else "m4/s"}
	var rejected_identity := true
	if not oracle.ok:
		for key in candidate: rejected_identity = rejected_identity and candidate[key].to_byte_array() == fields[key].to_byte_array()
	var receipt_matches := true
	if oracle.ok:
		var donor_actual := 0.0
		var donor_count := 0
		for i in grid_size * grid_size:
			if fields.water[i] > 0.001 and fields.obstacle[i] < 0.5 and fields.new_bed[i] > fields.old_bed[i]:
				donor_actual += (fields.water[i] - candidate.water[i]) * 0.015625
				donor_count += 1
		var capacity_status := 0
		for component in oracle.components:
			capacity_status = maxi(capacity_status, component.capacity_status)
		receipt_matches = receipt_bytes.decode_u32(8) == oracle.components.size() and receipt_bytes.decode_u32(12) == capacity_status and \
			absf(receipt_bytes.decode_float(16) - donor_actual) <= Protocol.reduction_budget(donor_count, absf(donor_actual)) and \
			absf(receipt_bytes.decode_float(16) - oracle.displaced_water_m3) <= budgets.water.integral_budget and \
			absf(receipt_bytes.decode_float(20) - oracle.retained_water_m3) <= budgets.water.integral_budget
	var row_ok: bool = (status == 1 and within_budget and finite and closure and receipt_matches) if oracle.ok else status == 2 and rejected_identity
	rows.append({"case": name, "grid": grid_size, "pass": row_ok, "status": status,
		"error_flags": receipt_bytes.decode_u32(4), "components": receipt_bytes.decode_u32(8),
		"capacity_status": receipt_bytes.decode_u32(12), "moved_m3": receipt_bytes.decode_float(16),
		"retained_m3": receipt_bytes.decode_float(20), "water_residual": receipt_bytes.decode_float(32),
		"residual_before": receipt_bytes.decode_float(56), "correction_cells": receipt_bytes.decode_u32(60),
		"max_correction_depth": receipt_bytes.decode_float(64),
		"queue_high_water": receipt_bytes.decode_u32(44), "max_errors": max_errors if oracle.ok else null,
		"closure": budgets, "oracle_ok": oracle.ok})
	rows[-1].receipt_matches = receipt_matches
	_write(false, "running")
	released = false
	RenderingServer.call_on_render_thread(_release)
	while not released: await process_frame

func _run() -> void:
	var file: RDShaderFile = load("res://shaders/simulation/edit_validation/"+("water_displace_compensated" if "--compensated-capacity" in OS.get_cmdline_user_args() else "water_displace")+".glsl")
	var spirv := file.get_spirv()
	var compile_error := spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
	if not compile_error.is_empty():
		_write(false, compile_error)
		finished = true
		quit(1)
		return
	var bytes: PackedByteArray = spirv.call("get_stage_bytecode", RenderingDevice.SHADER_STAGE_COMPUTE)
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	shader_metadata = {"source_sha256": FileAccess.get_sha256(file.resource_path), "spirv_sha256": hash.finish().hex_encode(), "spirv_bytes": bytes.size()}
	var cases := ["no_edit", "cap20", "cap80", "dry", "zero_capacity", "partial_capacity", "deep", "small", "dig", "suspended_flow", "obstacle", "dry_separation",
		"roundtop", "dry_flow", "border", "many_pools", "nan_bed", "negative_water", "inf_momentum", "negative_sediment"]
	for size in [64, 256]:
		grid_size = size
		for name in cases:
			fields = _state(size)
			match name:
				"cap20": _cap(0.2)
				"cap80": _cap(0.8)
				"dry":
					fields.water.fill(0.0)
					_cap(0.8)
				"zero_capacity": fields.new_bed.fill(0.8)
				"partial_capacity":
					fields.water.fill(0.0)
					for z in range(size / 2 - 8, size / 2 + 8):
						for x in range(size / 2 - 8, size / 2 + 8):
							fields.water[z * size + x] = 0.12
							if abs(x - size / 2) < 6 and abs(z - size / 2) < 6: fields.new_bed[z * size + x] = 0.8
				"deep":
					fields.water.fill(1.2)
					_cap(0.2)
				"small": _cap(0.0001)
				"dig": fields.new_bed.fill(-0.2)
				"suspended_flow":
					fields.sediment.fill(0.003)
					fields.momentum_x.fill(0.024)
					fields.momentum_z.fill(-0.012)
					_cap(0.8)
				"obstacle", "dry_separation":
					for z in size: fields["obstacle" if name == "obstacle" else "water"][z * size + size / 2] = 1.0 if name == "obstacle" else 0.0
					_cap(0.8, size / 4)
				"roundtop":
					for z in size:
						for x in size:
							var distance := Vector2((x + 0.5 - size / 2) * 0.125, (z + 0.5 - size / 2) * 0.125).length()
							fields.new_bed[z * size + x] = 0.8 * maxf(0.0, 1.0 - distance / 0.75)
				"dry_flow":
					fields.water.fill(0.00105)
					fields.sediment.fill(0.0002)
					fields.momentum_x.fill(0.0001)
					_cap(0.0001)
				"border": _cap(0.8, 0)
				"many_pools":
					for z in size:
						for x in size: fields.water[z * size + x] = 0.12 if (x + z) % 2 == 0 else 0.0
					_cap(0.8)
				"nan_bed": fields.new_bed[0] = NAN
				"negative_water": fields.water[0] = -0.1
				"inf_momentum": fields.momentum_x[0] = INF
				"negative_sediment": fields.sediment[0] = -0.1
			await _case(name, spirv)
			if not render_error.is_empty(): break
	var ok := render_error.is_empty() and rows.size() == cases.size() * 2
	for row in rows: ok = ok and row.pass
	_write(ok, render_error)
	finished = true
	print("WATER_GPU_COMPLETE pass=%s rows=%d" % [str(ok), rows.size()])
	quit(0 if ok else 1)


