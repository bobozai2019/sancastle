extends RefCounted

# Reuses the main erosion/material sets and coefficients. Only timestep reads
# become GPU decision-buffer reads; existing static shader ABIs stay unchanged.
var water
var sediment
var material
var ready:=false
var erosion_push:=PackedByteArray()
var material_push:=PackedByteArray()
var slope_push:=PackedByteArray()
var ordinary_push:=PackedByteArray()
var support_pushes:=[]

func initialize(recorder, erosion, materials) -> bool:
	water=recorder
	sediment=erosion
	material=materials
	var dt:="uintBitsToFloat(async_d[2])"
	var erosion_fraction:="async_fraction(%.16f*%s)"%[sediment.erosion_rate_per_s,dt]
	var deposition_fraction:="async_fraction(%.16f*%s)"%[sediment.deposition_rate_per_s,dt]
	# Preserve the existing 1-exp(-rate*dt) formula without float32 cancellation
	# for very small GPU substeps. Sixth-order expansion error <2e-11 at x=.1.
	var fraction_function:="float async_fraction(float x){return x<0.1?x*(1.0+x*(-0.5+x*(1.0/6.0+x*(-1.0/24.0+x*(1.0/120.0-x/720.0))))):1.0-exp(-x);}\nvoid main() {"
	if not water._compile("sediment","res://shaders/simulation/erosion/sediment_step.glsl",{"params.delta_s":dt,"params.erosion_fraction":erosion_fraction,"params.deposition_fraction":deposition_fraction,"void main() {":fraction_function}):return false
	if not water._compile("material_step","res://shaders/simulation/material/material_step.glsl",{"params.delta_s":dt}):return false
	if not water._compile("material_ordinary","res://shaders/simulation/edit_validation/staged_slope.glsl",{"params.delta_s":dt,"void main() {":"void main() { if(async_support[0]!=0u)return;"},[material.support_flags]):return false
	if not water._compile("material_molded","res://shaders/simulation/brushes/molded_slope.glsl",{"params.delta_s":dt,"void main() {":"void main() { if(async_support[0]==0u)return;"},[material.support_flags]):return false
	water.coupled_recorder=record
	ready=true
	return true

func _static_dispatch(pipeline: RID, binding: RID, push: PackedByteArray, step: int) -> void:
	var device: RenderingDevice=water.rd
	var list:=device.compute_list_begin()
	device.compute_list_bind_compute_pipeline(list,pipeline)
	device.compute_list_bind_uniform_set(list,binding,0)
	if not push.is_empty():device.compute_list_set_push_constant(list,push,push.size())
	device.compute_list_dispatch_indirect(list,water.indirect,step*12)
	device.compute_list_end()

func _support(phase: int, index: int, step: int) -> void:
	_static_dispatch(material.support_pipeline,material.support_set,support_pushes[index][phase],step)

func record(_decision: RID, _indirect: RID, step: int, live: int) -> void:
	if step==0:
		if not sediment.observe_pushes:erosion_push=sediment._erosion_push(1.0)
		material_push=PackedFloat32Array([0.0,material.WET_RATE_PER_S,material.DRY_RATE_PER_S,material.DIFFUSION_PER_S,material.RESIDUAL_WETNESS,material.SOAK_DEPTH_M,material.DRY_DEPTH_M,material.COMPACT_RATE_PER_S]).to_byte_array()
		slope_push=material._slope_push(0.0)
		ordinary_push=slope_push.slice(0,32)
		support_pushes.clear()
		for index in 2:
			var phases:=[]
			for phase in 3:phases.append(PackedInt32Array([water.solver.grid_size,index,phase,0]).to_byte_array())
			support_pushes.append(phases)
	water._dispatch("sediment",sediment.sets[live],sediment._erosion_push(1.0) if sediment.observe_pushes else erosion_push,step)
	# Reset/scan runs only for an active substep. Both slope branches are then
	# indirect-gated by that same step and choose tagged/ordinary work on GPU.
	_support(2,live,step)
	_support(0,live,step)
	water._dispatch("material_step",material.step_sets[live],material_push,step)
	water._dispatch("material_ordinary",material.ordinary_sets[live],ordinary_push,step)
	water._dispatch("material_molded",material.slope_sets[live],slope_push,step)
	_static_dispatch(material.consume_pipeline,material.consume_sets[live],PackedByteArray(),step)
	_static_dispatch(material.commit_pipeline,material.commit_sets[live],PackedByteArray(),step)
	_support(1,live,step)

func detach() -> void:
	if water!=null:water.coupled_recorder=Callable()
	water=null
	sediment=null
	material=null
	ready=false
