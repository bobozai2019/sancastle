extends RefCounted

# Retained GPU CFL/water numerical recorder; submission belongs to unified transport.
# Main frame-pump and lifecycle integration is independently verified in G5/G6.
var solver
var rd: RenderingDevice
var decision := RID()
var indirect := RID()
var owned: Array[RID] = []
var kernels := {}
var last_error := ""
var coupled_recorder := Callable()
var tail_recorder := Callable()
var boundary_enabled:=false
var waves:=RID()
var wave_count:=0
var tide:=Vector3(0.10,0.11,0.35)
var tide_mode:=0
var tide_phase:=0.0
var tide_period:=16.0
var last_recording_us:=0
var recorded_ticks:=0
var inject_boundary_upload_failure_once:=false
const MAX_WAVES:=128 # Main's existing staged workload has 80 scheduled packets.

func _own(rid: RID) -> RID:
	if rid.is_valid(): owned.append(rid)
	return rid

func _compile(name: String, path: String, replacements: Dictionary={}, extra_buffers: Array=[], use_decision: bool=true) -> bool:
	var source := RDShaderSource.new()
	source.source_compute=FileAccess.get_file_as_string(path).trim_prefix("#[compute]")
	for token in replacements:
		if not source.source_compute.contains(token): last_error="missing_dynamic_token:"+token;return false
		source.source_compute=source.source_compute.replace(token,replacements[token])
	if use_decision and not replacements.is_empty():
		source.source_compute=source.source_compute.replace("#version 450","#version 450\nlayout(set=1,binding=0,std430) readonly buffer AsyncDecision {uint async_d[];};")
		if not extra_buffers.is_empty():source.source_compute=source.source_compute.replace("#version 450","#version 450\nlayout(set=1,binding=1,std430) readonly buffer AsyncSupport {uint async_support[];};")
	var spirv:=rd.shader_compile_spirv_from_source(source)
	last_error=spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
	if not last_error.is_empty(): return false
	var shader:=_own(rd.shader_create_from_spirv(spirv))
	var pipeline:=_own(rd.compute_pipeline_create(shader))
	kernels[name]={"shader":shader,"pipeline":pipeline,"dynamic":not replacements.is_empty()}
	if use_decision and (not replacements.is_empty() or name=="normalize" or name.ends_with("_normalize")): kernels[name].decision_set=_make_binding(shader,1,[],[decision]+extra_buffers)
	return pipeline.is_valid()

func _make_binding(shader: RID, set_index: int, images: Array, buffers: Array) -> RID:
	var uniforms: Array[RDUniform]=[]
	var binding:=0
	for collection in [images,buffers]:
		for rid in collection:
			var u:=RDUniform.new()
			u.binding=binding
			u.uniform_type=RenderingDevice.UNIFORM_TYPE_IMAGE if collection==images else RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
			u.add_id(rid)
			uniforms.append(u)
			binding+=1
	return _own(rd.uniform_set_create(uniforms,shader,set_index))

func initialize(owner) -> bool:
	if owner==null or owner.rd==null or not owner.async_active or owner.current_index!=0:return false
	solver=owner
	rd=owner.rd
	decision=_own(rd.storage_buffer_create(64))
	indirect=_own(rd.storage_buffer_create(64*12,PackedByteArray(),RenderingDevice.STORAGE_BUFFER_USAGE_DISPATCH_INDIRECT))
	var base:="res://scripts/simulation/edit_validation/frame_pipeline/"
	for name in ["cfl_tiles","cfl_decide","sim_finish","normalize","boundary"]:
		if not _compile(name,"res://scripts/simulation/unified_edit/cfl_decide.glsl" if name=="cfl_decide" else base+"async_"+name+".glsl"):return false
	for name in ["drain_scale","update_state"]:
		if not _compile(name,"res://shaders/simulation/shallow_"+name+".glsl",{"params.delta_over_cell_size":"uintBitsToFloat(async_d[9])"}):return false
	kernels.cfl_tiles.binding=_make_binding(kernels.cfl_tiles.shader,0,[owner.textures.water[0],owner.textures.momentum_x[0],owner.textures.momentum_z[0],owner.textures.cfl_tiles],[])
	kernels.cfl_decide.binding=_make_binding(kernels.cfl_decide.shader,0,[owner.textures.cfl_tiles],[decision,indirect,owner.async_transport.control])
	kernels.sim_finish.binding=_make_binding(kernels.sim_finish.shader,0,[],[decision,owner.async_transport.control])
	var images:=[]
	for field in ["water","momentum_x","momentum_z","sediment","sand","wetness","compaction","flux"]:
		images.append(owner.textures[field][1])
		images.append(owner.textures[field][0])
	kernels.normalize.binding=_make_binding(kernels.normalize.shader,0,images,[])
	waves=_own(rd.storage_buffer_create(MAX_WAVES*16))
	kernels.boundary.binding=_make_binding(kernels.boundary.shader,0,[owner.textures.rock,owner.textures.sand[0],owner.textures.water[0],owner.textures.momentum_x[0],owner.textures.momentum_z[0]],[owner.async_transport.control,decision,waves])
	return last_error.is_empty()

# Render-thread, low-frequency configuration. Each packet is
# start_time_s/duration_s/amplitude_m/seed_phase; times use actual GPU time.
func configure_boundary(parameters: Vector3, packets: Array) -> bool:
	if not parameters.is_finite():last_error="boundary_nonfinite_tide";return false
	if packets.size()>MAX_WAVES:last_error="boundary_wave_capacity";return false
	var data:=PackedByteArray()
	for packet in packets:
		if not packet is Vector4 or not packet.is_finite() or packet.y<=0.0 or packet.z<0.0 or packet.z>0.25:last_error="boundary_wave_packet";return false
		data.append_array(PackedFloat32Array([packet.x,packet.y,packet.z,packet.w]).to_byte_array())
	data.resize(MAX_WAVES*16)
	if inject_boundary_upload_failure_once:inject_boundary_upload_failure_once=false;last_error="boundary_wave_upload";return false
	if rd.buffer_update(waves,0,data.size(),data)!=OK:last_error="boundary_wave_upload";return false
	tide=parameters
	wave_count=packets.size()
	boundary_enabled=true
	solver.prescribed_tide_boundary=true
	return true

func _dispatch(name: String, binding: RID, push: PackedByteArray, step: int=-1) -> void:
	var k: Dictionary=kernels[name]
	var list:=rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list,k.pipeline)
	rd.compute_list_bind_uniform_set(list,binding,0)
	if k.has("decision_set"):rd.compute_list_bind_uniform_set(list,k.decision_set,1)
	if not push.is_empty():rd.compute_list_set_push_constant(list,push,push.size())
	if step>=0:rd.compute_list_dispatch_indirect(list,indirect,step*12)
	else:rd.compute_list_dispatch(list,1 if name in ["cfl_decide","sim_finish","boundary"] else solver.grid_size/8,1 if name in ["cfl_decide","sim_finish","boundary"] else solver.grid_size/8,1)
	rd.compute_list_end()

func record_tick(_input: RID, _control: RID, _output: RID, _count: int, requested_dt: float) -> void:
	var record_start:=Time.get_ticks_usec() if solver.profile_passes else 0
	if solver.profile_passes:rd.capture_timestamp("sandcastle_async_water_tick_start")
	_dispatch("cfl_tiles",kernels.cfl_tiles.binding,PackedByteArray())
	var push:=PackedFloat32Array([requested_dt,solver.cell_size_m,solver.COURANT,0.0]).to_byte_array()
	push.encode_u32(12,solver.grid_size)
	_dispatch("cfl_decide",kernels.cfl_decide.binding,push)
	if boundary_enabled:
		var boundary_push:=PackedFloat32Array([solver.cell_size_m*solver.cell_size_m,tide.x,tide.y,tide.z]).to_byte_array()
		boundary_push.append_array(PackedInt32Array([wave_count,tide_mode,0,0]).to_byte_array())
		boundary_push.encode_float(24,tide_phase)
		boundary_push.encode_float(28,tide_period)
		_dispatch("boundary",kernels.boundary.binding,boundary_push)
		# Validate before changing authority; recalculate the safe CFL bound after
		# the boundary change. Neither decision leaves the GPU sequence.
		_dispatch("cfl_tiles",kernels.cfl_tiles.binding,PackedByteArray())
		_dispatch("cfl_decide",kernels.cfl_decide.binding,push)
	var drain_push:=PackedFloat32Array([0.0,0.0,0.0,0.0]).to_byte_array()
	var update_push:=PackedFloat32Array([0.0,solver.cell_size_m,1.0 if solver.prescribed_tide_boundary else 0.0,0.0]).to_byte_array()
	for step in 64:
		var index:=step%2
		var list:=rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(list,solver.pipelines[0])
		rd.compute_list_bind_uniform_set(list,solver.uniform_sets[index][0],0)
		rd.compute_list_dispatch_indirect(list,indirect,step*12)
		rd.compute_list_end()
		_dispatch("drain_scale",solver.uniform_sets[index][1],drain_push,step)
		_dispatch("update_state",solver.uniform_sets[index][2],update_push,step)
		if coupled_recorder.is_valid():coupled_recorder.call(decision,indirect,step,1-index)
	_dispatch("normalize",kernels.normalize.binding,PackedByteArray())
	_dispatch("sim_finish",kernels.sim_finish.binding,PackedByteArray())
	if tail_recorder.is_valid():tail_recorder.call(decision)
	if solver.profile_passes:
		rd.capture_timestamp("sandcastle_async_water_tick_end")
		last_recording_us=Time.get_ticks_usec()-record_start
		recorded_ticks+=1

func release() -> void:
	if rd!=null:
		for index in range(owned.size()-1,-1,-1):rd.free_rid(owned[index])
	owned.clear()
	kernels.clear()
	rd=null
	solver=null
