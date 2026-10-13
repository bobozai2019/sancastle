extends Node3D
signal state_readback_submitted
signal cfl_readback_submitted

const Domain = preload("res://scripts/simulation/sand_water_domain.gd")
const Solver = preload("res://scripts/simulation/edit_validation/lab_solver.gd")
const Queue = preload("res://scripts/sand/tool_command_queue.gd")
const STATE_FIELDS := ["rock", "sand", "water", "momentum_x", "momentum_z",
	"sediment", "wetness", "compaction", "obstacle", "flux"]
const SHADERS := ["shallow_edge_flux", "shallow_drain_scale", "shallow_update_state",
	"shallow_tide_boundary", "shallow_cfl_tiles", "shallow_gauge_depth",
	"shallow_audit_tiles", "shallow_tool_patch"]
@export var profile: Resource
@onready var collision_proxy: SandcastleGpuCollisionProxy = $CollisionProxy
var domain: SandWaterDomain
var command_queue: ToolCommandQueue
var solver: SandcastleGpuShallowSolver
var generation := 0
var completed_ticks := 0
var ready_for_ticks := false
var last_error := ""
var render_done := false
var readbacks := {}
var cfl_data := PackedByteArray()
var cfl_revision := -1
var spirvs: Array[RDShaderSPIRV] = []
var collision_spirv: RDShaderSPIRV
var textures := {}
var command_id := 0
var closed := false
var busy := false
var effective_profile := {}
var release_wait_count := 0
var release_record_us := -1
var pending_state_readbacks := 0
var pending_cfl_readbacks := 0
var observe_readback_ownership := false
var state_readback_callback_us := -1
var cfl_readback_callback_us := -1

func _ready() -> void:
	for name in SHADERS:
		var file: RDShaderFile = load("res://shaders/simulation/" + name + ".glsl")
		if file == null:
			_fail("shader missing: " + name)
			return
		spirvs.append(file.get_spirv())
	var file: RDShaderFile = load("res://shaders/simulation/shallow_collision_pack.glsl")
	collision_spirv = file.get_spirv()
	for field in ["rock", "sand", "water"]:
		textures[field] = Texture2DRD.new()
	call_deferred("reset_domain")

func _create_solver() -> SandcastleGpuShallowSolver:
	return Solver.new()

func reset_domain() -> void:
	if busy or closed:
		_fail("reset requested while busy/closed")
		return
	busy = true
	ready_for_ticks = false
	generation += 1
	completed_ticks = 0
	command_id = 0
	domain = Domain.new(profile.grid_size, profile.cell_size_m)
	domain.generation = generation
	domain.rock.fill(0.0)
	domain.sand.fill(profile.initial_sand_m)
	domain.water.fill(profile.initial_water_m)
	domain.tool_inventory_m3 = profile.inventory_m3
	command_queue = Queue.new(domain)
	effective_profile = {"profile_id": profile.profile_id, "grid_size": profile.grid_size,
		"cell_size_m": profile.cell_size_m, "sand_m": profile.initial_sand_m,
		"water_m": profile.initial_water_m, "inventory_m3": profile.inventory_m3,
		"seed": profile.seed, "sim_hz": profile.sim_hz, "boundary": "closed",
		"erosion": false, "generation": generation, "flux": "initialized_zero"}
	render_done = false
	RenderingServer.call_on_render_thread(_render_setup.bind(generation))
	while not render_done and last_error.is_empty():
		await get_tree().process_frame
	if not last_error.is_empty():
		busy = false
		return
	var chunks := PackedInt32Array()
	for id in (profile.grid_size / 32) * (profile.grid_size / 32):
		chunks.append(id)
	if not collision_proxy.apply_shadow_chunks(chunks, 0, generation, domain.rock, domain.sand):
		_fail("initial collision failed")
	ready_for_ticks = last_error.is_empty()
	busy = false

func _render_setup(token: int) -> void:
	if token != generation or closed:
		return
	if solver != null:
		for texture in textures.values():
			texture.texture_rd_rid = RID()
		collision_proxy._release_render()
		solver.release()
	call_deferred("_clear_collision_shapes")
	solver = _create_solver()
	if not solver.initialize(RenderingServer.get_rendering_device(), domain,
			spirvs[0], spirvs[1], spirvs[2], spirvs[3], spirvs[4], spirvs[5], spirvs[6], spirvs[7]):
		call_deferred("_fail", "solver initialize failed")
		return
	if not collision_proxy.setup_render(solver, collision_spirv, token):
		call_deferred("_fail", "collision initialize failed")
		return
	_publish_render()
	call_deferred("_done", token)

func _clear_collision_shapes() -> void:
	for shape in collision_proxy.shapes.values():
		shape.queue_free()
	collision_proxy.shapes.clear()
	collision_proxy.applied_revisions.clear()
	collision_proxy.pending_revisions.clear()
	collision_proxy.active_chunks.clear()

func _publish_render() -> void:
	for field in textures:
		textures[field].texture_rd_rid = solver.current_texture(field)
	call_deferred("_bind_materials")

func _bind_materials() -> void:
	for node in [$Sand, $Water]:
		var material: ShaderMaterial = node.material_override
		for field in textures:
			material.set_shader_parameter(field + "_state", textures[field])
		material.set_shader_parameter("extent_m", profile.grid_size * profile.cell_size_m)

func snapshot_state() -> Dictionary:
	if not ready_for_ticks or busy:
		_fail("snapshot requires idle ready state")
		return {}
	busy = true
	var token:=generation
	readbacks.clear()
	var fields := STATE_FIELDS.duplicate()
	RenderingServer.call_on_render_thread(_render_read.bind(fields, generation))
	while readbacks.size() < fields.size() and last_error.is_empty() and not closed and generation==token:
		await get_tree().process_frame
	busy = false
	if closed or generation!=token: return {}
	return readbacks.duplicate(true)

func _render_read(fields: Array, token: int) -> void:
	if closed or token != generation:
		return
	for field in fields:
		pending_state_readbacks+=1
		if solver.request_data(field, _on_data.bind(field, token)) != OK:
			pending_state_readbacks-=1
			call_deferred("_fail", "snapshot readback failed: " + field)
	if observe_readback_ownership: call_deferred("_notify_state_readback")

func _notify_state_readback() -> void: state_readback_submitted.emit()
func _notify_cfl_readback() -> void: cfl_readback_submitted.emit()

func _on_data(bytes: PackedByteArray, field: String, token: int) -> void:
	state_readback_callback_us=Time.get_ticks_usec()
	pending_state_readbacks-=1
	call_deferred("_record_data", bytes, field, token)

func _record_data(bytes: PackedByteArray, field: String, token: int) -> void:
	if token == generation and not closed:
		readbacks[field] = bytes

func advance_ticks(count: int) -> void:
	if not ready_for_ticks or busy:
		_fail("advance requires idle ready state")
		return
	busy = true
	var token:=generation
	for tick in count:
		cfl_data = PackedByteArray()
		RenderingServer.call_on_render_thread(_render_cfl.bind(generation))
		while cfl_data.is_empty() and last_error.is_empty() and not closed and generation==token:
			await get_tree().process_frame
		if not last_error.is_empty() or closed or generation!=token:
			break
		render_done = false
		RenderingServer.call_on_render_thread(_render_tick.bind(cfl_data, cfl_revision, generation))
		while not render_done and last_error.is_empty() and not closed and generation==token:
			await get_tree().process_frame
		if not last_error.is_empty() or closed or generation!=token:
			break
		completed_ticks += 1
		domain.sim_tick = completed_ticks
	busy = false

func _render_cfl(token: int) -> void:
	if closed or token!=generation: return
	pending_cfl_readbacks+=1
	if solver.request_cfl_tiles(_on_cfl.bind(token)) != OK:
		pending_cfl_readbacks-=1
		call_deferred("_fail", "CFL request failed")
	if observe_readback_ownership: call_deferred("_notify_cfl_readback")

func _on_cfl(bytes: PackedByteArray, revision: int, token: int) -> void:
	cfl_readback_callback_us=Time.get_ticks_usec()
	pending_cfl_readbacks-=1
	call_deferred("_record_cfl", bytes, revision, token)

func _record_cfl(bytes: PackedByteArray, revision: int, token: int) -> void:
	if token == generation and not closed:
		cfl_data = bytes
		cfl_revision = revision

func _render_tick(bytes: PackedByteArray, revision: int, token: int) -> void:
	if closed or token != generation:
		return
	if not solver.dispatch_tick_with_cfl(1.0 / profile.sim_hz, bytes, revision):
		call_deferred("_fail", "CFL tick failed")
		return
	_publish_render()
	call_deferred("_done", token)

func apply_cpu_command(command: Dictionary) -> Dictionary:
	if busy or not ready_for_ticks:
		return {"error": "backend_unavailable"}
	var error: StringName = command_queue.submit(command)
	if not error.is_empty():
		return {"error": String(error)}
	var results: Array[Dictionary] = command_queue.apply_due_commands(completed_ticks)
	var patch := command_queue.build_gpu_patch_batch(results)
	if patch.count > 0:
		busy = true
		render_done = false
		RenderingServer.call_on_render_thread(_render_patch.bind(patch, generation))
		while not render_done and last_error.is_empty():
			await get_tree().process_frame
		var chunks := PackedInt32Array()
		for result in results:
			chunks.append_array(result.dirty_chunks)
		collision_proxy.apply_shadow_chunks(chunks, solver.state_revision, generation, domain.rock, domain.sand)
		busy = false
	return {"results": results, "patch_count": patch.count}

func _render_patch(patch: Dictionary, token: int) -> void:
	if closed or token != generation:
		return
	if not solver.dispatch_tool_patch(patch.data, patch.count):
		call_deferred("_fail", "CPU patch failed")
		return
	_publish_render()
	call_deferred("_done", token)

func inject_boundary(depth_m: float) -> void:
	if busy or not ready_for_ticks:
		_fail("injection requires idle ready state")
		return
	busy = true
	render_done = false
	RenderingServer.call_on_render_thread(_render_injection.bind(depth_m, generation))
	while not render_done and last_error.is_empty():
		await get_tree().process_frame
	busy = false

func _render_injection(depth_m: float, token: int) -> void:
	if not solver.dispatch_boundary_injection(depth_m) or solver.request_tide_ledger(_on_injection.bind(token)) != OK:
		call_deferred("_fail", "injection/ledger failed")
		return
	_publish_render()

func _on_injection(_source: float, _sink: float, _revision: int, valid: bool, token: int) -> void:
	if not valid:
		call_deferred("_fail", "injection ledger invalid")
		return
	call_deferred("_done", token)

func _done(token: int) -> void:
	if token == generation:
		render_done = true

func _fail(message: String) -> void:
	last_error = message
	push_error(message)

func shutdown() -> void:
	closed = true
	generation += 1
	render_done = false
	RenderingServer.call_on_render_thread(_render_release)
	while not render_done:
		await get_tree().process_frame

func _render_release() -> void:
	if not collision_proxy.closing:
		collision_proxy.closing=true
		collision_proxy.generation+=1
		collision_proxy.pending_revisions.clear()
	if pending_state_readbacks>0 or pending_cfl_readbacks>0:
		release_wait_count+=1
		call_deferred("_retry_release");return
	# Async receipt callbacks own the editor buffers until they have returned.
	# Keep the render thread free to deliver them; retry from the next main frame.
	if solver != null and "receipt_pending" in solver and solver.receipt_pending:
		release_wait_count+=1
		call_deferred("_retry_release")
		return
	if collision_proxy.staging_texture.is_valid():
		release_wait_count+=1
		call_deferred("_retry_release")
		return
	release_record_us=Time.get_ticks_usec()
	for texture in textures.values():
		texture.texture_rd_rid = RID()
	collision_proxy._release_render()
	if solver != null:
		solver.release()
	solver = null
	call_deferred("_release_done")

func _retry_release() -> void:
	await get_tree().process_frame
	if closed: RenderingServer.call_on_render_thread(_render_release)

func _release_done() -> void:
	render_done = true

func _exit_tree() -> void:
	if not closed:
		closed = true
		generation += 1
		RenderingServer.call_on_render_thread(_render_release)
