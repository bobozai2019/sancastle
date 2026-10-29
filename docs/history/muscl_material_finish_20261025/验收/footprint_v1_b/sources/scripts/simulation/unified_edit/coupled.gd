extends "res://scripts/simulation/unified_edit/gpu.gd"

# Numerical resources only; invoked by the unified water substep recorder.
const Recorder=preload("res://scripts/simulation/unified_edit/water.gd")
const EXCHANGE_SOURCE="res://shaders/simulation/erosion/sediment_exchange.glsl"
const SOURCES=["res://scripts/simulation/unified_edit/coupled.gd","res://shaders/simulation/erosion/sediment_step_momentum.glsl","res://shaders/simulation/material/material_step.glsl","res://shaders/simulation/edit_validation/staged_slope.glsl","res://shaders/simulation/brushes/molded_slope.glsl","res://shaders/simulation/material/material_finish.glsl","res://shaders/simulation/brushes/mold_support_step.glsl",EXCHANGE_SOURCE]
const CAPACITY_PER_SPEED_S:=0.003
const EROSION_RATE_PER_S:=0.7295628483661365
const DEPOSITION_RATE_PER_S:=0.2419645313921744
var water
var state
var images: Dictionary={}
var buffers: Dictionary={}
var sets: Dictionary={}
var erosion_push:=PackedByteArray()
var material_push:=PackedByteArray()
var slope_push:=PackedByteArray()
var _passes: Array=[]
var _erosion_pushes: Array[PackedByteArray]=[]
var stage_transport:=false

func initialize(bundle, recorder, material: Dictionary) -> bool:
	if rd!=null or bundle.rd==null or recorder.rd!=bundle.rd:return false
	state=bundle;water=recorder;rd=bundle.rd
	stage_transport=water.muscl!=null
	images.dirty=state._create_texture(RenderingDevice.DATA_FORMAT_R32_UINT,PackedByteArray(),8,8)
	for pair in [["slope",65536*8],["support",65536*8],["flags",4],["support_indirect",24]]:
		var zero:=PackedByteArray();zero.resize(pair[1]);buffers[pair[0]]=own(rd.storage_buffer_create(pair[1],zero))
		if not buffers[pair[0]].is_valid():last_error="coupled_buffer";return false
	var dt:="uintBitsToFloat(async_d[2])"
	var fraction:="float async_fraction(float x){return x<0.1?x*(1.0+x*(-0.5+x*(1.0/6.0+x*(-1.0/24.0+x*(1.0/120.0-x/720.0))))):1.0-exp(-x);}\nvoid main() {"
	var sediment_replacements:={"params.erosion_fraction":"async_fraction(%.16f*%s)"%[float(state.coupling_parameters.get("erosion_rate_per_s",EROSION_RATE_PER_S)),dt],"params.deposition_fraction":"async_fraction(%.16f*%s)"%[float(state.coupling_parameters.get("deposition_rate_per_s",DEPOSITION_RATE_PER_S)),dt],"void main() {":fraction}
	if not stage_transport:sediment_replacements["params.delta_s"]=dt
	if not water._compile("sediment",EXCHANGE_SOURCE if stage_transport else SOURCES[1],sediment_replacements,[],not stage_transport):last_error=water.last_error;return false
	if stage_transport:
		water.kernels.sediment.decision_set=water._make_binding(water.kernels.sediment.shader,1,[],[water.decision,buffers.flags])
	if not water._compile("material_step",SOURCES[2],{"params.delta_s":dt}):last_error=water.last_error;return false
	if not water._compile("material_ordinary",SOURCES[3],{"params.delta_s":dt,"void main() {":"void main() { if(async_support[0]!=0u)return;"},[buffers.flags]):last_error=water.last_error;return false
	if not water._compile("material_molded",SOURCES[4],{"params.delta_s":dt,"void main() {":"void main() { if(async_support[0]==0u)return;"},[buffers.flags]):last_error=water.last_error;return false
	for pair in [["finish",SOURCES[5]],["support",SOURCES[6]]]:
		if not compile(pair[0],pair[1]):return false
	sets.support=binding("support",{4:buffers.support,5:buffers.flags,6:buffers.support_indirect},{0:state.textures.mold_support[0],1:state.textures.mold_support[1],2:state.textures.sand[0],3:state.textures.sand[1]})
	for name in ["sediment","material_step","material_ordinary","material_molded","finish"]:sets[name]=[]
	for live in 2:
		var spare:=1-live
		if stage_transport:
			sets.sediment.append(water._make_binding(water.kernels.sediment.shader,0,[state.textures.sediment[live],state.textures.sand[spare],state.textures.momentum[live],state.textures.water[live],state.textures.obstacle,state.textures.sand[live],images.dirty],[]))
		else:
			sets.sediment.append(water._make_binding(water.kernels.sediment.shader,0,[state.textures.sediment[spare],state.textures.water[spare],state.textures.flux[live],state.textures.obstacle,state.textures.sand[spare],state.textures.momentum[live],state.textures.water[live],state.textures.sand[live],state.textures.sediment[live],images.dirty],[]))
		sets.material_step.append(water._make_binding(water.kernels.material_step.shader,0,[state.textures.wetness[live],state.textures.compaction[live],state.textures.water[live],state.textures.sand[live],state.textures.obstacle,state.textures.wetness[spare],state.textures.compaction[spare]],[]))
		var ordinary:=[state.textures.sand[live],state.textures.rock,state.textures.wetness[spare],state.textures.compaction[spare],state.textures.obstacle,state.textures.sand[spare],images.dirty]
		sets.material_ordinary.append(water._make_binding(water.kernels.material_ordinary.shader,0,ordinary,[buffers.slope]))
		var uniforms: Array[RDUniform]=[]
		for index in ordinary.size():
			var u:=RDUniform.new();u.binding=index;u.uniform_type=RenderingDevice.UNIFORM_TYPE_IMAGE;u.add_id(ordinary[index]);uniforms.append(u)
		for pair in [[7,buffers.slope,RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER],[8,state.textures.mold_support[spare],RenderingDevice.UNIFORM_TYPE_IMAGE],[9,buffers.support,RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER]]:
			var u:=RDUniform.new();u.binding=pair[0];u.uniform_type=pair[2];u.add_id(pair[1]);uniforms.append(u)
		sets.material_molded.append(water._own(rd.uniform_set_create(uniforms,water.kernels.material_molded.shader,0)))
		sets.finish.append(binding("finish",{0:buffers.slope,7:buffers.support,8:buffers.flags},{1:state.textures.wetness[spare],2:state.textures.compaction[spare],3:state.textures.wetness[live],4:state.textures.compaction[live],5:state.textures.sand[0],6:state.textures.sand[1],9:state.textures.mold_support[0],10:state.textures.mold_support[1]}))
	for value in sets.values():
		for uniform in (value if value is Array else [value]):
			if not uniform.is_valid():last_error="coupled_uniform";return false
	material_push=PackedFloat32Array([0.0,tuning("wet_rate_per_s",1.5),tuning("dry_rate_per_s",0.07),tuning("diffusion_per_s",4.0),tuning("residual_wetness",0.05),tuning("soak_depth_m",0.06),tuning("dry_depth_m",0.001),tuning("compact_rate_per_s",0.05)]).to_byte_array()
	slope_push=PackedFloat32Array([0.0,state.cell_size_m,tuning("relax_rate_per_s",15.0),tuning("dry_repose_tan",0.674),tuning("wet_repose_tan",1.0),tuning("compaction_repose_gain",0.3),tuning("min_drop_m",0.0005),state.cohesion_yield_height_m,material.cohesion_yield_height_m,material.saturation_tagged_depth_m,0,0]).to_byte_array()
	for boundary in 2:_erosion_pushes.append(PackedFloat32Array([1.0,state.cell_size_m*state.cell_size_m,tuning("capacity_per_speed_s",CAPACITY_PER_SPEED_S),0,0,0.001,1.0/30.0,float(boundary)]).to_byte_array())
	for live in 2:
		var passes: Array[Recorder.RecordingPass]=[Recorder.RecordingPass.new(water.kernels.sediment.pipeline,sets.sediment[live],water.kernels.sediment.decision_set,_erosion_pushes[0])]
		# The non-MUSCL exchange has no flag write; keep its independent reset.
		if not stage_transport:passes.append(Recorder.RecordingPass.new(kernels.support.pipeline,sets.support,RID(),PackedInt32Array([256,live,2,0]).to_byte_array()))
		passes.append_array([
			Recorder.RecordingPass.new(kernels.support.pipeline,sets.support,RID(),PackedInt32Array([256,live,0,0]).to_byte_array()),
			Recorder.RecordingPass.new(water.kernels.material_step.pipeline,sets.material_step[live],water.kernels.material_step.decision_set,material_push),
			Recorder.RecordingPass.new(water.kernels.material_ordinary.pipeline,sets.material_ordinary[live],water.kernels.material_ordinary.decision_set,slope_push.slice(0,32)),
			Recorder.RecordingPass.new(water.kernels.material_molded.pipeline,sets.material_molded[live],water.kernels.material_molded.decision_set,slope_push),
			Recorder.RecordingPass.new(kernels.finish.pipeline,sets.finish[live])])
		_passes.append(passes)
	water.coupled_recorder=record
	return true

func muscl_recording_passes(live: int) -> Array:
	# MUSCL owns the flattened descriptors; the boundary selector is part of its
	# cache key. These resources and constants remain owned by this instance.
	for passes in _passes:passes[0].push=_erosion_pushes[1 if state.prescribed_tide_boundary else 0]
	return _passes[live]

func record(_decision: RID, _indirect: RID, step: int, live: int) -> void:
	if step==0:muscl_recording_passes(live)
	for stage: Recorder.RecordingPass in _passes[live]:
		var list:=rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(list,stage.pipeline)
		rd.compute_list_bind_uniform_set(list,stage.uniform,0)
		if stage.has_decision:rd.compute_list_bind_uniform_set(list,stage.decision_set,1)
		if stage.push_size>0:rd.compute_list_set_push_constant(list,stage.push,stage.push_size)
		rd.compute_list_dispatch_indirect(list,_indirect,step*12)
		rd.compute_list_end()

func release() -> void:
	if water!=null:water.coupled_recorder=Callable()
	_passes.clear();_erosion_pushes.clear()
	sets.clear();buffers.clear();images.clear();water=null;state=null;super.release()

func tuning(key: String, fallback: float) -> float:
	return float(state.coupling_parameters.get(key,fallback))
