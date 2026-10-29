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

# CPU-only recording descriptors. RIDs remain owned by Water, and each pass
# retains its original compute-list boundary and dispatch order.
class RecordingPass:
	var pipeline: RID
	var uniform: RID
	var decision_set: RID
	var has_decision:=false
	var push: PackedByteArray
	var push_size: int
	var indirect: RID
	var indirect_dispatch:=false
	var offset: int
	var groups: Vector3i
	var callback_kind:=0 # 1: dynamic boundary, 2: coupled substep
	var step:=0
	var diagnostic_label:=""
	var diagnostic_slot:=-1
	var diagnostic_phase:=-1

var _recording: Array[RecordingPass]=[]
var _recording_key: Array=[]
# Optional developer observer. It owns only discardable diagnostic resources;
# simulation scheduling, callbacks and resource ownership remain unchanged.
var diagnostic
var _standard_coupling:=false

func _append_pass(name: String, binding: RID, push: PackedByteArray=PackedByteArray(), step: int=-1, accepted: bool=false, groups:=Vector3i(32,32,1)) -> void:
	var stage:=RecordingPass.new()
	stage.pipeline=water.kernels[name].pipeline;stage.uniform=binding
	stage.push=push;stage.push_size=push.size();stage.groups=groups
	stage.diagnostic_label=name.trim_prefix("rk_")
	stage.diagnostic_slot=step
	if name in ["rk_edge","rk_drain","rk_euler"]:stage.diagnostic_phase=push.decode_u32(0)
	if step>=0:stage.indirect=water.indirect if accepted else buffers.trial_indirect;stage.offset=step*12;stage.indirect_dispatch=true
	_recording.append(stage)

func _append_coupled_pass(source, step: int, ordinal: int) -> void:
	var stage:=RecordingPass.new()
	stage.pipeline=source.pipeline;stage.uniform=source.uniform
	stage.decision_set=source.decision_set;stage.has_decision=source.has_decision
	stage.push=source.push;stage.push_size=source.push_size
	stage.indirect=water.indirect;stage.offset=step*12;stage.indirect_dispatch=true
	stage.diagnostic_label="coupled_%02d"%ordinal;stage.diagnostic_slot=step
	_recording.append(stage)

func _append_decision(mode: int, index: int, requested_dt: float) -> void:
	var push:=PackedFloat32Array([0.0,0.0,requested_dt,water.solver.cell_size_m]).to_byte_array()
	push.encode_u32(0,mode);push.encode_u32(4,index)
	_append_pass("rk_decide",sets.rk_decide,push,-1,false,Vector3i.ONE)
	_recording[-1].diagnostic_label="decision_%d"%mode
	if mode in [1,2,3,4,5]:_recording[-1].diagnostic_slot=index

func _prepare_recording(requested_dt: float) -> void:
	var key: Array=[requested_dt,water.solver.cell_size_m,water.boundary_enabled,water.solver.wave_retention,water.coupled_recorder,water.solver.prescribed_tide_boundary,water.solver.muscl_max_attempts]
	if key==_recording_key:return
	_recording.clear();_recording_key=key;_standard_coupling=false
	var coupled_passes: Array=[]
	if water.coupled_recorder.is_valid():
		var provider=water.coupled_recorder.get_object()
		# Only inline the provider's unwrapped fixed recorder. Instrumentation and
		# custom callbacks retain the callback path at every original substep.
		if provider!=null and provider.has_method("muscl_recording_passes") and water.coupled_recorder==Callable(provider,"record"):
			coupled_passes=provider.muscl_recording_passes(1)
			_standard_coupling=not coupled_passes.is_empty()
	var push0:=PackedInt32Array([0,1 if water.boundary_enabled else 0,0,0]).to_byte_array()
	var push1:=PackedInt32Array([1,1 if water.boundary_enabled else 0,0,0]).to_byte_array()
	push0.encode_float(8,water.solver.wave_retention);push1.encode_float(8,water.solver.wave_retention)
	# The private initializer index packs boundary in bit 0 and cache policy in
	# bit 1. GPU mode 0 owns reset; custom/wrapped callbacks never reuse input.
	var cache_policy:=2 if _standard_coupling or not water.coupled_recorder.is_valid() else 0
	_append_decision(0,(1 if water.boundary_enabled else 0)|cache_policy,requested_dt)
	_append_pass("rk_edge",sets.rk_edge[0],push0)
	_append_decision(7,0,requested_dt)
	if water.boundary_enabled:
		var boundary:=RecordingPass.new();boundary.callback_kind=1;boundary.diagnostic_label="boundary";_recording.append(boundary)
	for step in water.solver.muscl_max_attempts:
		_append_decision(1,step,requested_dt)
		_append_pass("rk_edge",sets.rk_edge[0],push0,step)
		_append_decision(2,step,requested_dt)
		_append_pass("rk_drain",sets.rk_drain[0],push0,step)
		_append_pass("rk_euler",sets.rk_euler[0],push0,step)
		_append_pass("rk_edge",sets.rk_edge[1],push1,step)
		_append_decision(3,step,requested_dt)
		_append_pass("rk_drain",sets.rk_drain[1],push1,step,true)
		_append_pass("rk_euler",sets.rk_euler[1],push1,step,true)
		_append_decision(4,step,requested_dt)
		_append_pass("rk_finalize",sets.rk_finalize,PackedByteArray(),step,true)
		_append_decision(4,step,requested_dt)
		if not coupled_passes.is_empty():
			for ordinal in coupled_passes.size():_append_coupled_pass(coupled_passes[ordinal],step,ordinal)
		else:
			var coupled:=RecordingPass.new();coupled.callback_kind=2;coupled.step=step;coupled.diagnostic_slot=step;coupled.diagnostic_label="coupled_callback";_recording.append(coupled)
		_append_pass("rk_normalize",sets.rk_normalize,PackedByteArray(),step,true)
		_append_decision(5,step,requested_dt)
	_append_pass("rk_validate",sets.rk_validate)
	_append_decision(6,0,requested_dt)

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
	# Frozen per generation; both CFL decisions consume the same specialization.
	if name=="rk_decide":source.source_compute=source.source_compute.replace("const float MUSCL_CFL = 0.2;","const float MUSCL_CFL = %.9f;"%water.solver.muscl_cfl)
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
	# First-stage values survive phase 1 and are disposable on accepted/new ticks.
	images.retry_correction=_texture(RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT)
	images.retry_bed_source=_texture(RenderingDevice.DATA_FORMAT_R32G32_SFLOAT)
	images.retry_speed_tiles=_texture(RenderingDevice.DATA_FORMAT_R32G32_SFLOAT,32,32)
	for name in ["drain0","drain1","exchange_sediment"]:images[name]=_texture(RenderingDevice.DATA_FORMAT_R32_SFLOAT)
	for pair in [["trial",128],["safety",128],["audit",2048],["trial_indirect",768],["retry_cache",16]]:
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
			var images_for_phase: Array=[t.rock,t.sand[0],t.water[0],t.momentum[0],t.sediment[0],t.obstacle,images.u2 if phase==0 else images.u1,images.u1 if phase==0 else images.u2,images["edge%d_x"%phase],images["edge%d_z"%phase],(images.retry_correction if phase==0 else images.correction),(images.retry_bed_source if phase==0 else images.bed_source),images["drain%d"%phase],(images.retry_speed_tiles if phase==0 else images.speed_tiles)]
			sets[name].append(water._make_binding(water.kernels[name].shader,0,images_for_phase,spatial_buffers+[buffers.retry_cache]))
	sets.rk_decide=water._make_binding(water.kernels.rk_decide.shader,0,[images.speed_tiles,images.retry_speed_tiles],[water.decision,buffers.trial,buffers.safety,buffers.audit,buffers.trial_indirect,water.indirect,water.solver.async_transport.control,buffers.retry_cache])
	var finalize_images: Array=[t.water[0],t.momentum[0],t.sediment[0],images.u2,t.sand[0],t.wetness[0],t.compaction[0],t.obstacle,images.edge0_x,images.edge0_z,images.edge1_x,images.edge1_z,images.drain0,images.drain1,t.water[1],t.momentum[1],t.sediment[1],t.sand[1],t.wetness[1],t.compaction[1],t.flux[1]]
	sets.rk_finalize=water._make_binding(water.kernels.rk_finalize.shader,0,finalize_images,spatial_buffers)
	var normal_images: Array=[]
	for name in ["water","momentum","sediment","sand","wetness","compaction","flux"]:normal_images.append_array([t[name][1],t[name][0]])
	sets.rk_normalize=water._make_binding(water.kernels.rk_normalize.shader,0,normal_images,[water.decision])
	sets.rk_validate=water._make_binding(water.kernels.rk_validate.shader,0,[t.water[0],t.momentum[0],t.sediment[0],t.sand[0],t.wetness[0],t.compaction[0]],[buffers.trial,water.solver.async_transport.control])
	for value in sets.values():
		for binding in (value if value is Array else [value]):
			if not binding.is_valid():last_error="muscl_uniform_set";return false
	return true

func record_tick(requested_dt: float) -> void:
	var began:=Time.get_ticks_usec() if water.solver.profile_passes else 0
	var cpu_began:=Time.get_ticks_usec() if diagnostic!=null and diagnostic.enabled else 0
	if water.solver.profile_passes:rd.capture_timestamp("sandcastle_async_water_tick_start")
	_prepare_recording(requested_dt)
	var sampled: bool=diagnostic.begin_tick(_standard_coupling,requested_dt) if diagnostic!=null else false
	for stage: RecordingPass in _recording:
		if sampled:diagnostic.pass_begin(stage.diagnostic_label,stage.diagnostic_slot,stage.diagnostic_phase)
		if stage.callback_kind==1:
			water._dispatch("boundary",water.kernels.boundary.binding,water.boundary_push_constants())
			continue
		if stage.callback_kind==2:
			if water.coupled_recorder.is_valid():water.coupled_recorder.call(water.decision,water.indirect,stage.step,1)
			continue
		var list:=rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(list,stage.pipeline)
		rd.compute_list_bind_uniform_set(list,stage.uniform,0)
		if stage.has_decision:rd.compute_list_bind_uniform_set(list,stage.decision_set,1)
		if stage.push_size>0:rd.compute_list_set_push_constant(list,stage.push,stage.push_size)
		if stage.indirect_dispatch:rd.compute_list_dispatch_indirect(list,stage.indirect,stage.offset)
		else:rd.compute_list_dispatch(list,stage.groups.x,stage.groups.y,stage.groups.z)
		rd.compute_list_end()
	if sampled:diagnostic.pass_begin("finish",-1,-1)
	water._dispatch("sim_finish",water.kernels.sim_finish.binding,PackedByteArray())
	if sampled:diagnostic.pass_begin("tail",-1,-1)
	if water.tail_recorder.is_valid():water.tail_recorder.call(water.decision)
	if sampled:diagnostic.end_tick(water.decision,buffers.audit,water.solver.async_transport.control)
	if water.solver.profile_passes:
		rd.capture_timestamp("sandcastle_async_water_tick_end");water.last_recording_us=Time.get_ticks_usec()-began;water.recorded_ticks+=1
	if cpu_began!=0:diagnostic.record_cpu(cpu_began,Time.get_ticks_usec(),sampled)

func release() -> void:
	if diagnostic!=null:diagnostic.close();diagnostic=null
	_recording.clear();_recording_key.clear()
	sets.clear();images.clear();buffers.clear();water=null;rd=null
