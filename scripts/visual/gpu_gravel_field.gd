extends RefCounted
class_name SandcastleGpuGravelField

## Display-only GPU state. All RD calls, including release, run on render thread.
const PROFILE_KEYS := ["schema_version", "count", "capacity", "seed", "spawn_bounds_xz", "radius_min_m", "radius_max_m", "response_min", "response_max", "h_on_m", "h_off_m", "speed_on_m_s", "speed_off_m_s", "h_epsilon_m", "speed_cap_m_s", "max_step_cell_fraction", "max_microsteps", "bed_reconstruction", "mesh_path", "material_path"]
var rd: RenderingDevice
var textures: Array[RID] = []
var uniform_sets: Array[Array] = []
var shader := RID()
var pipeline := RID()
var profile := {}
var current_index := 0
var generation := -1
var completed_tick := -1
var revision := -1
var grid_size := 0
var cell_size_m := 0.0
var last_error: StringName = &""
var pending := 0
var readback_requests := 0
var dispatches := 0
var cap_events := 0
var last_microsteps := 0
var last_effective_cap := 0.0
var cpu_submission_us := 0
var active_count := 0

static func default_profile(scene_key := "main", count := 512) -> Dictionary:
	return {"schema_version":1,"count":count,"capacity":1024,"seed":57849,
		"spawn_bounds_xz": [-6.0,-8.0,6.0,8.0] if scene_key == "main" else [-10.0,-6.0,6.0,6.0],
		"radius_min_m":0.02,"radius_max_m":0.05,"response_min":0.25,"response_max":0.65,
		"h_on_m":0.012,"h_off_m":0.006,"speed_on_m_s":0.08,"speed_off_m_s":0.04,
		"h_epsilon_m":0.006,"speed_cap_m_s":4.0,"max_step_cell_fraction":0.5,
		"max_microsteps":8,"bed_reconstruction":true,"mesh_path":"res://assets/gravel/stone_mesh.tres",
		"material_path":"res://assets/gravel/stone_material.tres"}

static func profile_hash(values: Dictionary) -> String:
	var ordered := {}
	for key in PROFILE_KEYS: ordered[key] = values.get(key)
	return JSON.stringify(ordered).sha256_text()

static func validate_profile(values: Dictionary, size: int, cell: float) -> StringName:
	if values.size() != PROFILE_KEYS.size() or size < 2 or not is_finite(cell) or cell <= 0.0: return &"invalid_gravel_profile"
	for key in PROFILE_KEYS:
		if not values.has(key): return &"invalid_gravel_profile"
	for key in ["schema_version","count","capacity","seed","max_microsteps"]:
		if typeof(values[key]) != TYPE_INT: return &"invalid_gravel_profile"
	if values.schema_version != 1 or values.capacity != 1024 or values.count < 0 or values.count > 1024 or values.seed < 0 or values.seed > 0xffffffff or values.max_microsteps < 1 or values.max_microsteps > 64: return &"invalid_gravel_profile"
	for key in ["radius_min_m","radius_max_m","response_min","response_max","h_on_m","h_off_m","speed_on_m_s","speed_off_m_s","h_epsilon_m","speed_cap_m_s","max_step_cell_fraction"]:
		if typeof(values[key]) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(values[key])) or float(values[key]) < 0.0: return &"invalid_gravel_profile"
	if values.radius_min_m <= 0.0 or values.radius_max_m < values.radius_min_m or values.response_max < values.response_min or values.h_on_m <= values.h_off_m or values.speed_on_m_s <= values.speed_off_m_s or values.h_epsilon_m <= 0.0 or values.speed_cap_m_s <= 0.0 or values.max_step_cell_fraction <= 0.0 or values.max_step_cell_fraction > 0.5: return &"invalid_gravel_profile"
	if typeof(values.bed_reconstruction) != TYPE_BOOL or typeof(values.mesh_path) != TYPE_STRING or typeof(values.material_path) != TYPE_STRING: return &"invalid_gravel_profile"
	var bounds: Variant = values.spawn_bounds_xz
	if not bounds is Array or bounds.size() != 4: return &"invalid_gravel_profile"
	for value in bounds:
		if typeof(value) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(value)) or absf(value) > size*cell*0.5: return &"invalid_gravel_profile"
	if bounds[0] >= bounds[2] or bounds[1] >= bounds[3]: return &"invalid_gravel_profile"
	return &""

func initialize(solver, spirv: RDShaderSPIRV, values: Dictionary, token: int, tick: int, state_revision: int, restore := {}) -> bool:
	if solver == null or solver.rd == null or spirv == null or rd != null: return _error(&"invalid_gravel_profile")
	last_error = validate_profile(values, solver.grid_size, solver.cell_size_m)
	if not last_error.is_empty(): return false
	if typeof(restore.get("active_count", values.count)) != TYPE_INT: return _error(&"gravel_state_invalid")
	active_count = restore.get("active_count", values.count)
	if active_count < values.count or active_count > values.capacity: return _error(&"gravel_state_invalid")
	if not restore.is_empty():
		if typeof(restore.get("current_index"))!=TYPE_INT or restore.current_index not in [0,1]: return _error(&"gravel_state_invalid")
		for key in ["state_0","state_1"]:
			if not restore.get(key) is PackedByteArray or restore[key].size()!=16384: return _error(&"gravel_state_invalid")
			var raw: PackedFloat32Array=restore[key].to_float32_array()
			for id in 1024:
				for k in 4:
					if not is_finite(raw[id*4+k]) or (id>=active_count and raw[id*4+k]!=0.0): return _error(&"gravel_state_invalid")
				if absf(raw[id*4])>solver.grid_size*solver.cell_size_m*0.5 or absf(raw[id*4+2])>solver.grid_size*solver.cell_size_m*0.5 or raw[id*4+3] not in [0.0,1.0]: return _error(&"gravel_state_invalid")
	rd = solver.rd
	profile = values.duplicate(true)
	generation = token
	completed_tick = tick
	revision = state_revision
	grid_size = solver.grid_size
	cell_size_m = solver.cell_size_m
	var format := RDTextureFormat.new()
	format.width = 64
	format.height = 16
	format.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
	var zeros := PackedByteArray()
	zeros.resize(64*16*16)
	zeros.fill(0)
	for index in 2:
		var data: PackedByteArray = restore.get("state_%d" % index, zeros)
		if data.size() != zeros.size(): release(); return _error(&"gravel_state_invalid")
		textures.append(rd.texture_create(format, RDTextureView.new(), [data]))
		if not textures.back().is_valid(): release(); return _error(&"gravel_restore_failed")
	shader = rd.shader_create_from_spirv(spirv)
	if not shader.is_valid(): release(); return _error(&"gravel_restore_failed")
	pipeline = rd.compute_pipeline_create(shader)
	if not pipeline.is_valid(): release(); return _error(&"gravel_restore_failed")
	for solver_index in 2:
		var sets: Array[RID] = []
		for index in 2:
			var ids: Array[RID] = [textures[index], textures[1-index], solver.textures.rock, solver.textures.sand[solver_index], solver.textures.water[solver_index], solver.textures.momentum_x[solver_index], solver.textures.momentum_z[solver_index]]
			var bindings: Array[RDUniform] = []
			for binding in ids.size():
				var uniform := RDUniform.new()
				uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
				uniform.binding = binding
				uniform.add_id(ids[binding])
				bindings.append(uniform)
			sets.append(rd.uniform_set_create(bindings, shader, 0))
			if not sets.back().is_valid():
				uniform_sets.append(sets)
				release()
				return _error(&"gravel_restore_failed")
		uniform_sets.append(sets)
	if restore.is_empty():
		_dispatch(solver, 0.0, 1)
		# Both ping-pong states are deterministic initial completed states.
		if rd.texture_copy(current_texture(), textures[1-current_index], Vector3.ZERO, Vector3.ZERO, Vector3(64,16,1),0,0,0,0) != OK:
			release()
			return _error(&"gravel_restore_failed")
	else:
		current_index = restore.current_index
	return true

func _error(value: StringName) -> bool:
	last_error = value
	return false

func advance(solver, target_tick: int, state_revision: int, token: int, dt: float) -> bool:
	if token != generation: return _error(&"gravel_generation_mismatch")
	if target_tick == completed_tick: return state_revision == revision or _error(&"gravel_state_invalid")
	if target_tick != completed_tick+1 or state_revision < revision or not is_finite(dt) or dt <= 0.0: return _error(&"gravel_state_invalid")
	if rd == null or solver == null or solver.rd != rd: return _error(&"gravel_state_invalid")
	_dispatch(solver, dt, 0)
	completed_tick = target_tick
	revision = state_revision
	last_error = &""
	return true

func reproject(solver, tick: int, state_revision: int, token: int) -> bool:
	if token != generation: return _error(&"gravel_generation_mismatch")
	if tick != completed_tick or state_revision < revision or rd == null or solver == null or solver.rd != rd: return _error(&"gravel_state_invalid")
	_dispatch(solver, 0.0, 2)
	revision = state_revision
	last_error = &""
	return true

func add_at(solver, point: Vector2, count: int, token: int, tick: int, state_revision: int) -> StringName:
	if rd == null or solver == null or solver.rd != rd or token != generation or tick != completed_tick or state_revision != revision: return &"gravel_state_invalid"
	if not point.is_finite() or count < 1 or count > 128 or absf(point.x) > grid_size*cell_size_m*0.5-0.45 or absf(point.y) > grid_size*cell_size_m*0.5-0.45: return &"out_of_domain"
	if active_count + count > profile.capacity: return &"gravel_capacity_full"
	var old_count := active_count
	active_count += count
	_dispatch(solver, 0.0, 3, PackedFloat32Array([point.x-0.45,point.y-0.45,point.x+0.45,point.y+0.45]), old_count)
	return &""

func _dispatch(solver, dt: float, mode: int, spawn_bounds := PackedFloat32Array(), old_count := 0) -> void:
	var profiling: bool="profile_passes" in solver and solver.profile_passes
	var begin_us := Time.get_ticks_usec() if profiling else 0
	if profiling: rd.capture_timestamp("sandcastle_gravel_start")
	var max_distance: float = cell_size_m*profile.max_step_cell_fraction
	var wanted := maxi(1, ceili(dt*profile.response_max*profile.speed_cap_m_s/max_distance))
	last_microsteps = mini(wanted, profile.max_microsteps)
	last_effective_cap = profile.speed_cap_m_s
	if wanted > profile.max_microsteps:
		last_effective_cap = max_distance*profile.max_microsteps/(dt*profile.response_max)
		cap_events += 1
	var push := PackedInt32Array([active_count, profile.capacity, profile.seed, mode]).to_byte_array()
	push.append_array(PackedFloat32Array([grid_size,cell_size_m,dt,last_microsteps,profile.h_on_m,profile.h_off_m,profile.speed_on_m_s,profile.speed_off_m_s,profile.response_min,profile.response_max,profile.h_epsilon_m,last_effective_cap]).to_byte_array())
	push.append_array((PackedFloat32Array(profile.spawn_bounds_xz) if spawn_bounds.is_empty() else spawn_bounds).to_byte_array())
	push.append_array(PackedFloat32Array([1.0 if profile.bed_reconstruction else 0.0,float(old_count),0.0,0.0]).to_byte_array())
	var list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list, pipeline)
	rd.compute_list_bind_uniform_set(list, uniform_sets[solver.current_index][current_index], 0)
	rd.compute_list_set_push_constant(list, push, push.size())
	rd.compute_list_dispatch(list, 16, 1, 1)
	rd.compute_list_end()
	if profiling:
		rd.capture_timestamp("sandcastle_gravel_end")
		cpu_submission_us+=Time.get_ticks_usec()-begin_us
	current_index = 1-current_index
	dispatches += 1

func current_texture() -> RID:
	return textures[current_index] if textures.size() == 2 else RID()

func capture_async(callback: Callable, request_id: int) -> Error:
	if rd == null or not callback.is_valid(): return ERR_UNAVAILABLE
	var identity := {"request_id":request_id,"generation":generation,"tick":completed_tick,"revision":revision}
	for index in 2:
		pending += 1
		readback_requests += 1
		var error := rd.texture_get_data_async(textures[index],0,_captured.bind(callback,"state_%d" % index,identity))
		if error != OK:
			pending -= 1
			callback.call(PackedByteArray(),"state_%d" % index,identity)
			last_error = &"gravel_capture_failed"
	return OK if last_error != &"gravel_capture_failed" else ERR_CANT_ACQUIRE_RESOURCE

func _captured(bytes: PackedByteArray, callback: Callable, key: String, identity: Dictionary) -> void:
	pending -= 1
	callback.call(bytes,key,identity)

func release() -> bool:
	if pending > 0: return false
	if rd == null: return true
	for sets in uniform_sets:
		for rid in sets:
			if rid.is_valid(): rd.free_rid(rid)
	uniform_sets.clear()
	for rid in [pipeline,shader]:
		if rid.is_valid(): rd.free_rid(rid)
	for rid in textures:
		if rid.is_valid(): rd.free_rid(rid)
	textures.clear()
	pipeline = RID()
	shader = RID()
	rd = null
	return true
