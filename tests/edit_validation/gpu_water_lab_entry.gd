extends "res://tests/edit_validation/gpu_brush_lab_entry.gd"

var displacement_spirvs: Array[RDShaderSPIRV] = []
var expect_transport_failure := false
var fast_full_wet := false

func _ready() -> void:
	var skip_idle: bool="--skip-idle-components" in OS.get_cmdline_user_args()
	if skip_idle and not ("--packed-runs" in OS.get_cmdline_user_args() and "--compensated-capacity" in OS.get_cmdline_user_args() and "--cached-capacity" in OS.get_cmdline_user_args()):
		_fail("idle component candidate requires packed compensated cached capacity");return
	var cached_shader: String="water_packed_cached_idle" if skip_idle else "water_packed_cached"
	fast_full_wet = "--fast-full-wet" in OS.get_cmdline_user_args() or "--connected-runs" in OS.get_cmdline_user_args() or "--packed-runs" in OS.get_cmdline_user_args()
	water_policy = 1
	for name in ["water_prepare", "water_displace", "water_merge_receipt", "water_commit", "water_publish", "water_velocity_apply", "water_velocity_reduce", "water_full_wet"]:
		var file: RDShaderFile = load("res://shaders/simulation/edit_validation/" + ("water_displace_compensated_audit" if name=="water_displace" and "--sand-audit-values" in OS.get_cmdline_user_args() else "water_displace_compensated" if name=="water_displace" and "--compensated-capacity" in OS.get_cmdline_user_args() else "water_velocity_prefetch" if name=="water_velocity_reduce" and "--prefetch-velocity" in OS.get_cmdline_user_args() else cached_shader if name=="water_full_wet" and "--packed-runs" in OS.get_cmdline_user_args() and "--compensated-capacity" in OS.get_cmdline_user_args() and "--cached-capacity" in OS.get_cmdline_user_args() else "water_packed_compensated" if name=="water_full_wet" and "--packed-runs" in OS.get_cmdline_user_args() and "--compensated-capacity" in OS.get_cmdline_user_args() else "water_packed_runs" if name=="water_full_wet" and "--packed-runs" in OS.get_cmdline_user_args() else "water_connected_runs" if name=="water_full_wet" and "--connected-runs" in OS.get_cmdline_user_args() else name) + ".glsl")
		if file == null:
			_fail("water shader missing: " + name)
			return
		var spirv := file.get_spirv()
		var error := spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
		if not error.is_empty():
			_fail("water shader compile: " + name + " " + error)
			return
		displacement_spirvs.append(spirv)
		var bytes: PackedByteArray = spirv.call("get_stage_bytecode", RenderingDevice.SHADER_STAGE_COMPUTE)
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(bytes)
		shader_metadata.append({"path": file.resource_path, "source_sha256": FileAccess.get_sha256(file.resource_path),
			"spirv_bytes": bytes.size(), "spirv_sha256": hash.finish().hex_encode()})
	super._ready()

func _create_solver() -> SandcastleGpuShallowSolver:
	var editor := preload("res://scripts/simulation/edit_validation/gpu_water_editor.gd").new()
	editor.edit_spirvs = editor_spirvs
	editor.water_spirvs = displacement_spirvs
	editor.local_dispatch = local_dispatch
	editor.fast_full_wet = fast_full_wet and (not "--compensated-capacity" in OS.get_cmdline_user_args() or "--packed-runs" in OS.get_cmdline_user_args())
	editor.connected_runs="--connected-runs" in OS.get_cmdline_user_args() or "--packed-runs" in OS.get_cmdline_user_args()
	return editor

func _publish_render() -> void:
	super._publish_render()
	textures.water.texture_rd_rid = solver.published_water

func seed_test_fields(fields: Dictionary, stock_m3: float = 2.0) -> void:
	# Every setup starts a new generation. This API is not an edit or hot upload.
	if busy or closed or not is_finite(stock_m3):
		_fail("invalid water test seed")
		return
	var count: int = profile.grid_size * profile.grid_size
	for key in fields:
		if key not in ["rock", "sand", "water", "sediment", "momentum_x", "momentum_z", "obstacle", "compaction", "wetness"] or not fields[key] is PackedFloat32Array or fields[key].size() != count:
			_fail("invalid water test field: " + key)
			return
		for value in fields[key]:
			if not is_finite(value) or (key in ["sand", "water", "sediment"] and value < 0.0):
				_fail("invalid water test value: " + key)
				return
	await reset_domain()
	if not last_error.is_empty(): return
	busy = true
	ready_for_ticks = false
	var hashes := {}
	for key in fields:
		if key not in ["momentum_x", "momentum_z"]: domain.set(key, fields[key].duplicate())
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(fields[key].to_byte_array())
		hashes[key] = hash.finish().hex_encode()
	var zero := PackedFloat32Array()
	zero.resize(count)
	zero.fill(0.0)
	domain.set_meta("edit_validation_initial_qx", fields.get("momentum_x", zero).duplicate())
	domain.set_meta("edit_validation_initial_qz", fields.get("momentum_z", zero).duplicate())
	domain.tool_inventory_m3 = stock_m3
	command_queue = Queue.new(domain)
	effective_profile.setup_seed = {"initial_field_sha256": hashes, "stock_m3": stock_m3,
		"profile_scalar_fields_are_defaults": true, "generation": generation}
	render_done = false
	RenderingServer.call_on_render_thread(_render_setup.bind(generation))
	while not render_done and last_error.is_empty(): await get_tree().process_frame
	var chunks := PackedInt32Array()
	for id in (profile.grid_size / 32) * (profile.grid_size / 32): chunks.append(id)
	if last_error.is_empty() and not collision_proxy.apply_shadow_chunks(chunks, solver.state_revision, generation, domain.rock, domain.sand):
		_fail("water seed collision failed")
	ready_for_ticks = last_error.is_empty()
	busy = false

func _fail(message: String) -> void:
	if expect_transport_failure and message == "GPU command dispatch failed":
		last_error = message
		ready_for_ticks = false
		print("EXPECTED_WATER_TRANSPORT_FAILURE quarantine")
		return
	super._fail(message)
