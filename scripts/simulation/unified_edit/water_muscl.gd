extends RefCounted

# A recorder owned by Water. It never submits, publishes or reads back per step.
const COUPLING_SUPPORTED=true
const BASE="res://shaders/simulation/muscl/"
const SOURCES=["res://scripts/simulation/unified_edit/water_muscl.gd","res://scripts/simulation/unified_edit/water_numerics.gd",BASE+"muscl_math.glslinc",BASE+"muscl_stats.glslinc",BASE+"muscl_spatial.glslinc",BASE+"rk_edge.glsl",BASE+"rk_drain.glsl",BASE+"rk_euler.glsl",BASE+"rk_decide.glsl",BASE+"rk_finalize.glsl",BASE+"rk_normalize.glsl",BASE+"rk_validate.glsl"]
var water
var rd: RenderingDevice
var images: Dictionary={}
var buffers: Dictionary={}
var sets: Dictionary={}
var last_error:=""

func _texture(format_id: int,width: int=256,height: int=256) -> RID:
	var format:=RDTextureFormat.new();format.width=width;format.height=height;format.format=format_id
	format.usage_bits=RenderingDevice.TEXTURE_USAGE_STORAGE_BIT|RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
	return water._own(rd.texture_create(format,RDTextureView.new()))

func _source(path: String) -> String:
	var source:=FileAccess.get_file_as_string(path).trim_prefix("#[compute]")
	for _pass in 4:
		for name in ["muscl_spatial.glslinc","muscl_math.glslinc","muscl_stats.glslinc"]:
			source=source.replace("#include \""+name+"\"",FileAccess.get_file_as_string(BASE+name))
	if source.contains("#include"):last_error="unresolved_muscl_include";return ""
	return source

func _compile(name: String) -> bool:
	var source:=RDShaderSource.new();source.source_compute=_source(BASE+name+".glsl")
	if not last_error.is_empty():return false
	var spirv:=rd.shader_compile_spirv_from_source(source)
	last_error=spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
	if not last_error.is_empty():last_error=name+":"+last_error;return false
	var shader: RID=water._own(rd.shader_create_from_spirv(spirv))
	var pipeline: RID=water._own(rd.compute_pipeline_create(shader))
	water.kernels[name]={"shader":shader,"pipeline":pipeline}
	return shader.is_valid() and pipeline.is_valid()

func initialize(recorder) -> bool:
	water=recorder;rd=water.rd
	for name in ["u1","u2","edge0_x","edge0_z","edge1_x","edge1_z","correction"]:
		images[name]=_texture(RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT)
	images.bed_source=_texture(RenderingDevice.DATA_FORMAT_R32G32_SFLOAT)
	images.speed_tiles=_texture(RenderingDevice.DATA_FORMAT_R32G32_SFLOAT,32,32)
	for name in ["drain0","drain1","exchange_sediment"]:images[name]=_texture(RenderingDevice.DATA_FORMAT_R32_SFLOAT)
	for pair in [["trial",128],["safety",128],["audit",2048],["trial_indirect",768]]:
		var zero:=PackedByteArray();zero.resize(pair[1])
		buffers[pair[0]]=water._own(rd.storage_buffer_create(pair[1],zero,RenderingDevice.STORAGE_BUFFER_USAGE_DISPATCH_INDIRECT if pair[0]=="trial_indirect" else 0))
	for rid in images.values()+buffers.values():
		if not rid.is_valid():last_error="muscl_work_resource";return false
	for name in ["rk_edge","rk_drain","rk_euler","rk_decide","rk_finalize","rk_normalize","rk_validate"]:
		if not _compile(name):return false
	var t: Dictionary=water.solver.textures
	var spatial_buffers: Array=[water.decision,buffers.trial,buffers.safety]
	for name in ["rk_edge","rk_drain","rk_euler"]:
		sets[name]=[]
		for phase in 2:
			var images_for_phase: Array=[t.rock,t.sand[0],t.water[0],t.momentum_x[0],t.momentum_z[0],t.sediment[0],t.obstacle,images.u2 if phase==0 else images.u1,images.u1 if phase==0 else images.u2,images["edge%d_x"%phase],images["edge%d_z"%phase],images.correction,images.bed_source,images["drain%d"%phase],images.speed_tiles]
			sets[name].append(water._make_binding(water.kernels[name].shader,0,images_for_phase,spatial_buffers))
	sets.rk_decide=water._make_binding(water.kernels.rk_decide.shader,0,[images.speed_tiles],[water.decision,buffers.trial,buffers.safety,buffers.audit,buffers.trial_indirect,water.indirect,water.solver.async_transport.control])
	var finalize_images: Array=[t.water[0],t.momentum_x[0],t.momentum_z[0],t.sediment[0],images.u2,t.sand[0],t.wetness[0],t.compaction[0],t.obstacle,images.edge0_x,images.edge0_z,images.edge1_x,images.edge1_z,images.drain0,images.drain1,t.water[1],t.momentum_x[1],t.momentum_z[1],t.sediment[1],t.sand[1],t.wetness[1],t.compaction[1],t.flux[1]]
	sets.rk_finalize=water._make_binding(water.kernels.rk_finalize.shader,0,finalize_images,spatial_buffers)
	var normal_images: Array=[]
	for name in ["water","momentum_x","momentum_z","sediment","sand","wetness","compaction","flux"]:normal_images.append_array([t[name][1],t[name][0]])
	sets.rk_normalize=water._make_binding(water.kernels.rk_normalize.shader,0,normal_images,[water.decision])
	sets.rk_validate=water._make_binding(water.kernels.rk_validate.shader,0,[t.water[0],t.momentum_x[0],t.momentum_z[0],t.sediment[0],t.sand[0],t.wetness[0],t.compaction[0]],[buffers.trial,water.solver.async_transport.control])
	for value in sets.values():
		for binding in (value if value is Array else [value]):
			if not binding.is_valid():last_error="muscl_uniform_set";return false
	return true

func _dispatch(name: String,binding: RID,push: PackedByteArray=PackedByteArray(),step: int=-1,accepted: bool=false,direct_groups: Vector3i=Vector3i(32,32,1)) -> void:
	var list:=rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list,water.kernels[name].pipeline)
	rd.compute_list_bind_uniform_set(list,binding,0)
	if not push.is_empty():rd.compute_list_set_push_constant(list,push,push.size())
	if step>=0:rd.compute_list_dispatch_indirect(list,water.indirect if accepted else buffers.trial_indirect,step*12)
	else:rd.compute_list_dispatch(list,direct_groups.x,direct_groups.y,direct_groups.z)
	rd.compute_list_end()

func _decide(mode: int,index: int,requested_dt: float) -> void:
	var push:=PackedFloat32Array([0.0,0.0,requested_dt,water.solver.cell_size_m]).to_byte_array()
	push.encode_u32(0,mode);push.encode_u32(4,index)
	_dispatch("rk_decide",sets.rk_decide,push,-1,false,Vector3i.ONE)

func record_tick(requested_dt: float) -> void:
	var began:=Time.get_ticks_usec() if water.solver.profile_passes else 0
	if water.solver.profile_passes:rd.capture_timestamp("sandcastle_async_water_tick_start")
	var push0:=PackedInt32Array([0,1 if water.boundary_enabled else 0,0,0]).to_byte_array()
	var push1:=PackedInt32Array([1,1 if water.boundary_enabled else 0,0,0]).to_byte_array()
	push0.encode_float(8,water.solver.wave_retention)
	push1.encode_float(8,water.solver.wave_retention)
	_decide(0,1 if water.boundary_enabled else 0,requested_dt)
	_dispatch("rk_edge",sets.rk_edge[0],push0)
	_decide(7,0,requested_dt)
	if water.boundary_enabled:
		var boundary_push:=PackedFloat32Array([water.solver.cell_size_m*water.solver.cell_size_m,water.tide.x,water.tide.y,water.tide.z]).to_byte_array()
		boundary_push.append_array(PackedInt32Array([water.wave_count,water.tide_mode,0,0]).to_byte_array())
		boundary_push.encode_float(24,water.tide_phase);boundary_push.encode_float(28,water.tide_period)
		water._dispatch("boundary",water.kernels.boundary.binding,boundary_push)
	for step in 64:
		_decide(1,step,requested_dt)
		_dispatch("rk_edge",sets.rk_edge[0],push0,step)
		_decide(2,step,requested_dt)
		_dispatch("rk_drain",sets.rk_drain[0],push0,step)
		_dispatch("rk_euler",sets.rk_euler[0],push0,step)
		_dispatch("rk_edge",sets.rk_edge[1],push1,step)
		_decide(3,step,requested_dt)
		_dispatch("rk_drain",sets.rk_drain[1],push1,step,true)
		_dispatch("rk_euler",sets.rk_euler[1],push1,step,true)
		_decide(4,step,requested_dt)
		_dispatch("rk_finalize",sets.rk_finalize,PackedByteArray(),step,true)
		_decide(4,step,requested_dt)
		if water.coupled_recorder.is_valid():water.coupled_recorder.call(water.decision,water.indirect,step,1)
		_dispatch("rk_normalize",sets.rk_normalize,PackedByteArray(),step,true)
		_decide(5,step,requested_dt)
	_dispatch("rk_validate",sets.rk_validate)
	_decide(6,0,requested_dt)
	water._dispatch("sim_finish",water.kernels.sim_finish.binding,PackedByteArray())
	if water.tail_recorder.is_valid():water.tail_recorder.call(water.decision)
	if water.solver.profile_passes:
		rd.capture_timestamp("sandcastle_async_water_tick_end");water.last_recording_us=Time.get_ticks_usec()-began;water.recorded_ticks+=1

func release() -> void:
	sets.clear();images.clear();buffers.clear();water=null;rd=null
