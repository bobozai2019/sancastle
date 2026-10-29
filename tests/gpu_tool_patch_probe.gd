extends SceneTree

const Domain = preload("res://scripts/simulation/sand_water_domain.gd")
const Queue = preload("res://scripts/sand/tool_command_queue.gd")
const GpuSolver = preload("res://scripts/simulation/gpu_shallow_solver.gd")

var size := 64
var initial_domain: SandWaterDomain
var cpu_domain: SandWaterDomain
var queue: ToolCommandQueue
var gpu_solver: SandcastleGpuShallowSolver
var spirvs: Array[RDShaderSPIRV] = []
var batch := {}
var readbacks := {}
var finished := false
var watchdog_started_ms := 0


func _init() -> void:
	call_deferred("_begin")


func _begin() -> void:
	var requested_size := int(OS.get_environment("SANDCASTLE_GPU_GRID"))
	if requested_size > 0:
		size = requested_size
	if size not in [64, 256]:
		_fail("tool patch probe requires 64 or 256 grid")
		return
	for path in [
		"res://shaders/simulation/shallow_edge_flux.glsl",
		"res://shaders/simulation/shallow_drain_scale.glsl",
		"res://shaders/simulation/shallow_update_state.glsl",
		"res://shaders/simulation/shallow_tide_boundary.glsl",
		"res://shaders/simulation/shallow_cfl_tiles.glsl",
		"res://shaders/simulation/shallow_gauge_depth.glsl",
		"res://shaders/simulation/shallow_audit_tiles.glsl",
		"res://shaders/simulation/shallow_tool_patch.glsl"]:
		var shader_file: RDShaderFile = load(path)
		if shader_file == null or shader_file.get_spirv() == null:
			_fail("shader import missing: " + path)
			return
		spirvs.append(shader_file.get_spirv())
	initial_domain = Domain.new(size, 0.125)
	cpu_domain = Domain.new(size, 0.125)
	for domain in [initial_domain, cpu_domain]:
		domain.sand.fill(0.25)
		domain.compaction.fill(0.10)
	queue = Queue.new(cpu_domain)
	for command in _commands():
		var error: StringName = queue.submit(command)
		if not error.is_empty():
			_fail("CPU command submit failed: " + String(error))
			return
	var results := queue.apply_due_commands(0)
	if results.size() != 5:
		_fail("CPU command batch result count mismatch")
		return
	for result in results:
		if result.status != &"applied":
			_fail("CPU command rejected: " + String(result.error_code))
			return
	batch = queue.build_gpu_patch_batch(results)
	if batch.count < 1 or batch.data.size() != batch.count * 16:
		_fail("GPU patch batch dimensions invalid")
		return
	RenderingServer.call_on_render_thread(_render_patch)
	watchdog_started_ms = Time.get_ticks_msec()
	call_deferred("_watchdog")


func _commands() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var kinds := [&"remove_sand", &"place_sand", &"smooth", &"compact", &"debug_add_sand"]
	var amounts := [0.04, 0.015, 0.0, 0.0, 0.01]
	for i in kinds.size():
		var swept := i == 1
		var transform := {"position_m": Vector3(-0.25, 0.0, -0.25)}
		if swept:
			transform["end_position_m"] = Vector3(0.75, 0.0, 0.5)
		result.append({
			"domain_id": cpu_domain.domain_id, "generation": cpu_domain.generation,
			"sim_tick": 0, "command_id": i + 1, "kind": kinds[i],
			"shape": &"swept_segment" if swept else &"circle",
			"transform": transform, "radius_m": 0.5, "strength": 1.0,
			"amount_m3": amounts[i], "seed": i + 101})
	return result


func _render_patch() -> void:
	gpu_solver = GpuSolver.new()
	if not gpu_solver.initialize(RenderingServer.get_rendering_device(), initial_domain,
			spirvs[0], spirvs[1], spirvs[2], spirvs[3], spirvs[4], spirvs[5], spirvs[6], spirvs[7]):
		call_deferred("_fail", "GPU patch solver initialization failed")
		return
	if gpu_solver.dispatch_tool_patch(PackedByteArray(), 1):
		call_deferred("_fail", "GPU patch accepted invalid byte count")
		return
	if not gpu_solver.dispatch_tool_patch(batch.data, batch.count) or gpu_solver.state_revision != 1:
		call_deferred("_fail", "GPU tool batch dispatch failed")
		return
	for buffer_index in 2:
		for field in ["sand", "compaction"]:
			var label := "%s_%d" % [field, buffer_index]
			var rid: RID = gpu_solver.textures[field][buffer_index]
			var error: Error = gpu_solver.rd.texture_get_data_async(rid, 0, _on_data.bind(label))
			if error != OK:
				call_deferred("_fail", "GPU tool readback failed %d" % error)
				return


func _on_data(data: PackedByteArray, label: String) -> void:
	call_deferred("_record", label, data)


func _record(label: String, data: PackedByteArray) -> void:
	if finished:
		return
	readbacks[label] = data
	if readbacks.size() != 4:
		return
	var digest := ""
	for buffer_index in 2:
		var sand_bytes: PackedByteArray = readbacks["sand_%d" % buffer_index]
		var compaction_bytes: PackedByteArray = readbacks["compaction_%d" % buffer_index]
		var sand_values := sand_bytes.to_float32_array()
		if sand_values.size() != size * size or compaction_bytes.size() != size * size * 2:
			_fail("GPU tool patch readback dimensions mismatch")
			return
		var compaction_image := Image.create_from_data(size, size, false,
			Image.FORMAT_RH, compaction_bytes)
		compaction_image.convert(Image.FORMAT_RF)
		var compaction_values := compaction_image.get_data().to_float32_array()
		for i in size * size:
			if absf(sand_values[i] - cpu_domain.sand[i]) > 0.000001 or \
					absf(compaction_values[i] - cpu_domain.compaction[i]) > 0.001:
				_fail("GPU tool patch mismatch buffer=%d cell=%d" % [buffer_index, i])
				return
		if buffer_index == 0:
			var hash := HashingContext.new()
			hash.start(HashingContext.HASH_SHA256)
			hash.update(sand_bytes)
			hash.update(compaction_bytes)
			digest = hash.finish().hex_encode()
	var expected_sand := initial_domain.total_sand_m3(false) + cpu_domain.sand_source_m3 - \
		cpu_domain.tool_inventory_m3
	if absf(cpu_domain.total_sand_m3(false) - expected_sand) > 0.0001:
		_fail("CPU tool inventory/source budget did not close")
		return
	print("PASS: GPU tool patch %d-square commands=5 dirty_cells=%d inventory=%.6f source=%.6f digest=%s" % [
		size, batch.count, cpu_domain.tool_inventory_m3, cpu_domain.sand_source_m3, digest])
	finished = true
	RenderingServer.call_on_render_thread(_release_success)


func _release_success() -> void:
	gpu_solver.release()
	call_deferred("_finish", 0)


func _watchdog() -> void:
	if finished:
		return
	if Time.get_ticks_msec() - watchdog_started_ms > 90000:
		_fail("GPU tool patch callback timed out")
		return
	await process_frame
	call_deferred("_watchdog")


func _fail(message: String) -> void:
	if finished:
		return
	finished = true
	printerr("FAIL: " + message)
	RenderingServer.call_on_render_thread(_release_failure)


func _release_failure() -> void:
	if gpu_solver != null:
		gpu_solver.release()
	call_deferred("_finish", 1)


func _finish(code: int) -> void:
	quit(code)
