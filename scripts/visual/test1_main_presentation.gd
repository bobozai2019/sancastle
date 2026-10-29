extends RefCounted
class_name Test1MainPresentation

## Only projects the completed capture state into main's render field contract.
const PROJECT := preload("res://shaders/simulation/test1_main_display.glsl")
const FOAM := preload("res://shaders/simulation/visual_foam_step.glsl")
const FRONT_X := preload("res://tests/visual_water_alignment/prototypes/reference_local_front_x.glsl")
const FRONT_Z := preload("res://tests/visual_water_alignment/prototypes/reference_local_front_z.glsl")
const Front := preload("res://tests/visual_water_alignment/prototypes/reference_local_front_field.gd")
var rd: RenderingDevice
var fields := {}
var shader := RID()
var pipeline := RID()
var sets: Array[RID] = []
var solver := SandcastleGpuShallowSolver.new()
var foam := SandcastleGpuFoamField.new()
var front = Front.new()
var generation := 0

func initialize(device: RenderingDevice, inputs: Array[RID]) -> bool:
	rd = device
	var format := RDTextureFormat.new()
	format.width = 256
	format.height = 256
	format.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	var empty := PackedByteArray()
	empty.resize(256 * 256 * 4)
	for name in ["rock", "sand", "water", "momentum_x", "momentum_z", "wetness", "compaction"]:
		fields[name] = rd.texture_create(format, RDTextureView.new(), [empty])
	shader = rd.shader_create_from_spirv(PROJECT.get_spirv())
	pipeline = rd.compute_pipeline_create(shader)
	for source in inputs:
		var uniforms: Array[RDUniform] = []
		var ids := [source]
		for name in fields:
			ids.append(fields[name])
		for binding in ids.size():
			var uniform := RDUniform.new()
			uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
			uniform.binding = binding
			uniform.add_id(ids[binding])
			uniforms.append(uniform)
		sets.append(rd.uniform_set_create(uniforms, shader, 0))
	solver.rd = rd
	solver.grid_size = 256
	solver.cell_size_m = 0.125
	for name in fields:
		solver.textures[name] = fields[name] if name == "rock" else [fields[name], fields[name]]
	return reset()

func project_state(index: int, dt: float, reset_wetness: bool = false) -> void:
	var list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list, pipeline)
	rd.compute_list_bind_uniform_set(list, sets[index], 0)
	rd.compute_list_set_push_constant(list, PackedFloat32Array([dt, 1.0 if reset_wetness else 0.0, 0.0, 0.0]).to_byte_array(), 16)
	rd.compute_list_dispatch(list, 32, 32, 1)
	rd.compute_list_end()

func reset() -> bool:
	front.release()
	foam.release()
	project_state(0, 0.0, true)
	# Initialization only: seed history with actual depth to avoid a false first-frame crest.
	var depths := rd.texture_get_data(fields.water, 0).to_float32_array()
	var bed := rd.texture_get_data(fields.sand, 0).to_float32_array()
	var history := PackedFloat32Array()
	history.resize(256 * 256 * 2)
	for i in depths.size():
		history[2 * i] = 0.0
		history[2 * i + 1] = depths[i]
	generation = 0
	return foam.initialize(solver, FOAM.get_spirv(), history, bed) and front.initialize(solver, foam, FRONT_X.get_spirv(), FRONT_Z.get_spirv())

func dispatch(index: int, tick: int, dt: float) -> bool:
	project_state(index, dt)
	if not foam.dispatch(solver, dt) or not front.dispatch(solver, foam):
		return false
	generation = tick
	return true

func published() -> Dictionary:
	var result := fields.duplicate()
	result.foam_state = foam.current_texture()
	result.foam_previous_state = foam.textures[1 - foam.current_index]
	result.local_front_state = front.texture
	return result

func release() -> void:
	front.release()
	foam.release()
	for rid in sets + fields.values() + [pipeline, shader]:
		if rid.is_valid():
			rd.free_rid(rid)
	# The solver is a field view only; it never executes or owns the capture solver.
	solver.rd = null
	solver.textures.clear()
