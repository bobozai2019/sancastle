extends "res://tests/edit_validation/edit_lab.gd"

const Protocol = preload("res://scripts/simulation/edit_validation/edit_protocol.gd")
var editor_spirvs: Array[RDShaderSPIRV] = []
var ticket_id := 0
var receipt := {}
var raw_receipt := PackedByteArray()
var reserved_m3 := 0.0
var pending_command := {}
var pending_revision := -1
var shadow_sand_revision := 0
var transaction_settled := false
var ignored_receipts := 0
var shader_metadata := []
var settle_us := -1
var publish_us := -1
var local_dispatch := false
var water_policy := 0
var signed_speed_m_s := 0.0

func _ready() -> void:
	for name in ["sand_prepare", "sand_reduce", "sand_apply", "sand_commit", "sand_publish"]:
		var file: RDShaderFile = load("res://shaders/simulation/edit_validation/" + ("sand_reduce_audit" if name=="sand_reduce" and "--sand-audit-values" in OS.get_cmdline_user_args() else name) + ".glsl")
		if file == null:
			_fail("edit shader missing: " + name)
			return
		var spirv := file.get_spirv()
		var compile_error := spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
		if not compile_error.is_empty():
			_fail("edit shader compile: " + name + " " + compile_error)
			return
		editor_spirvs.append(spirv)
		var context := HashingContext.new()
		context.start(HashingContext.HASH_SHA256)
		var bytecode: PackedByteArray = spirv.call("get_stage_bytecode", RenderingDevice.SHADER_STAGE_COMPUTE)
		context.update(bytecode)
		shader_metadata.append({"path": file.resource_path, "source_sha256": FileAccess.get_sha256(file.resource_path),
			"spirv_bytes": bytecode.size(), "spirv_sha256": context.finish().hex_encode()})
	super._ready()

func _create_solver() -> SandcastleGpuShallowSolver:
	var editor := preload("res://scripts/simulation/edit_validation/gpu_sand_editor.gd").new()
	editor.edit_spirvs = editor_spirvs
	editor.local_dispatch = local_dispatch
	return editor

func _publish_render() -> void:
	solver.publish_sand()
	for field in textures:
		textures[field].texture_rd_rid = solver.published_sand if field == "sand" else solver.current_texture(field)
	call_deferred("_bind_materials")

func apply_gpu_command(command: Dictionary) -> Dictionary:
	if busy or closed or not ready_for_ticks:
		return {"error": "backend_unavailable"}
	if not Protocol.finite_command(command) or command.get("kind") not in [&"remove_sand", &"place_sand"]:
		return {"error": "invalid_command"}
	if not is_finite(signed_speed_m_s) or absf(signed_speed_m_s) > 1.0:
		return {"error": "invalid_command"}
	# This synchronous lab executor consumes due commands only. Admission of
	# future commands belongs to the scheduler, not an orphaned queue entry here.
	if typeof(command.get("sim_tick")) == TYPE_INT and command.sim_tick > completed_ticks:
		return {"error": "backend_unavailable"}
	if not command_queue.pending.is_empty(): return {"error":"backend_unavailable"}
	var error: StringName = command_queue.submit(command)
	if not error.is_empty():
		return {"error": String(error)}
	return await execute_admitted_gpu_command(command, domain.tool_inventory_m3)

func execute_admitted_gpu_command(command: Dictionary, available_m3: float) -> Dictionary:
	# Consume the already admitted front command without advancing the admission
	# ID high-water mark a second time. Future IDs can execute in tick order.
	if busy or closed or not ready_for_ticks or command_queue.pending.is_empty() or not is_finite(available_m3):
		return {"error":"backend_unavailable"}
	var front: Dictionary = command_queue.pending[0]
	if front.command_id != command.command_id or front.generation != generation or front.sim_tick > completed_ticks:
		return {"error":"invalid_command"}
	command = command_queue.pending.pop_front()
	var token := generation
	busy = true
	transaction_settled = false
	settle_us = -1
	publish_us = -1
	ticket_id += 1
	pending_command = command.duplicate(true)
	pending_revision = solver.state_revision
	reserved_m3 = command.amount_m3 * command.strength if command.kind == &"place_sand" else 0.0
	receipt = {}
	raw_receipt = PackedByteArray()
	var data := Protocol.encode(command, ticket_id, pending_revision, profile.grid_size, profile.cell_size_m,
		water_policy, available_m3, signed_speed_m_s)
	RenderingServer.call_on_render_thread(_render_command.bind(data, generation))
	while receipt.is_empty() and last_error.is_empty() and not closed and generation == token:
		await get_tree().process_frame
	if not closed and generation == token and last_error.is_empty() and receipt.get("status", 2) == 1:
		render_done = false
		RenderingServer.call_on_render_thread(_render_publish_command.bind(generation))
		while not render_done and last_error.is_empty() and not closed and generation == token:
			await get_tree().process_frame
	reserved_m3 = 0.0
	pending_command = {}
	busy = false
	if closed or generation != token:
		# A close after CPU settlement must preserve the actual terminal outcome.
		if transaction_settled and receipt.get("status",0) in [1,2]: return receipt.duplicate(true)
		return {"error":"inactive_generation","cancelled":true}
	return receipt.duplicate(true)

func _render_command(data: PackedByteArray, token: int) -> void:
	if token != generation or closed:
		return
	if not solver.dispatch_sand_command(data, _on_receipt.bind(token)):
		call_deferred("_fail", "GPU command dispatch failed")

func _on_receipt(data: PackedByteArray, token: int) -> void:
	call_deferred("_settle_receipt", data, token)

func _settle_receipt(data: PackedByteArray, token: int) -> void:
	if closed or token != generation:
		ignored_receipts += 1
		return
	var result := Protocol.decode_receipt(data)
	if transaction_settled or pending_command.is_empty() or (result.get("ok", false) and result.ticket_id != ticket_id):
		ignored_receipts += 1
		return
	raw_receipt = data
	if not Protocol.receipt_matches(result, ticket_id, pending_command.command_id, generation, pending_revision):
		_fail("GPU receipt identity/audit failed")
		return
	if result.status not in [1, 2]:
		_fail("GPU receipt is not terminal")
		return
	if result.status == 1:
		var delta: float = result.actual_sand_m3 if pending_command.kind == &"remove_sand" else -result.actual_sand_m3
		domain.tool_inventory_m3 += delta
		command_queue.applied_log.append(pending_command.duplicate(true))
		shadow_sand_revision = -1
	transaction_settled = true
	settle_us = Time.get_ticks_usec()
	receipt = result

func _render_publish_command(token: int) -> void:
	if token != generation or closed:
		return
	if not transaction_settled or not solver.authorize_publication(ticket_id, int(receipt.output_revision), token):
		call_deferred("_fail", "unsettled or mismatched GPU publication")
		return
	_publish_render()
	publish_us = Time.get_ticks_usec()
	call_deferred("_done", token)

func synchronize_cpu_shadow() -> void:
	var fields: Dictionary = await snapshot_state()
	if closed or fields.size()!=STATE_FIELDS.size(): return
	domain.sand = fields.sand.to_float32_array()
	for field in ["compaction", "wetness"]:
		var values := PackedFloat32Array()
		values.resize(profile.grid_size * profile.grid_size)
		for i in values.size():
			values[i] = fields[field].decode_half(i * 2)
		domain.set(field, values)
	domain.sediment = fields.sediment.to_float32_array()
	domain.water = fields.water.to_float32_array()
	shadow_sand_revision = solver.state_revision

func apply_legacy_command(command: Dictionary) -> Dictionary:
	if busy:
		return {"error": "backend_unavailable"}
	if shadow_sand_revision != solver.state_revision:
		await synchronize_cpu_shadow()
	var result: Dictionary = await super.apply_cpu_command(command)
	shadow_sand_revision = solver.state_revision
	return result

func seed_test_state(sand_values: PackedFloat32Array, stock_m3: float) -> void:
	# Test initialization only; never called by the edit hot path.
	if busy or sand_values.size() != profile.grid_size * profile.grid_size:
		_fail("invalid test seed")
		return
	await reset_domain()
	if not last_error.is_empty():
		return
	busy = true
	domain.sand = sand_values.duplicate()
	domain.tool_inventory_m3 = stock_m3
	command_queue = Queue.new(domain)
	var stream := StreamPeerBuffer.new()
	stream.big_endian = false
	for i in sand_values.size():
		stream.put_32(i)
		stream.put_float(sand_values[i])
		stream.put_float(domain.compaction[i])
		stream.put_float(0.0)
	render_done = false
	RenderingServer.call_on_render_thread(_render_seed_patch.bind({"data": stream.data_array, "count": sand_values.size()}, generation))
	while not render_done and last_error.is_empty():
		await get_tree().process_frame
	shadow_sand_revision = solver.state_revision
	var chunks := PackedInt32Array()
	for id in (profile.grid_size / 32) * (profile.grid_size / 32):
		chunks.append(id)
	if not collision_proxy.apply_shadow_chunks(chunks, solver.state_revision, generation, domain.rock, domain.sand):
		_fail("seed collision publication failed")
	busy = false

func _render_seed_patch(patch: Dictionary, token: int) -> void:
	solver.owner_generation = token
	super._render_patch(patch, token)

func _fail(message: String) -> void:
	ready_for_ticks = false
	super._fail(message)
