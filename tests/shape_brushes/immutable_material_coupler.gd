extends "res://tests/shape_brushes/barrier_material_coupler.gd"

var immutable_inputs: Array[RID]=[]
var input_copy_count:=0

func initialize(owner: SandcastleGpuShallowSolver, dirty: RID, step: RDShaderSPIRV, slope: RDShaderSPIRV, commit: RDShaderSPIRV) -> bool:
	if not super.initialize(owner,dirty,step,slope,commit): return false
	for i in 2:
		immutable_inputs.append(owner._create_texture(RenderingDevice.DATA_FORMAT_R16_SFLOAT,PackedByteArray()))
		if not immutable_inputs[-1].is_valid(): return false
	for rid in step_sets: rd.free_rid(rid)
	step_sets.clear()
	for live in 2:
		var resources: Array[RID]=[immutable_inputs[0],immutable_inputs[1],owner.textures.water[live],owner.textures.sand[live],owner.textures.obstacle,owner.textures.wetness[1-live],owner.textures.compaction[1-live]]
		step_sets.append(_image_set(resources,step_shader))
		if not step_sets[-1].is_valid(): return false
	return true

func dispatch_after_erosion(delta_s: float) -> bool:
	if rd==null or immutable_inputs.size()!=2: return false
	for i in 2:
		var source: RID=solver.textures["wetness" if i==0 else "compaction"][solver.current_index]
		if rd.texture_copy(source,immutable_inputs[i],Vector3.ZERO,Vector3.ZERO,Vector3(256,256,1),0,0,0,0)!=OK: return false
	input_copy_count+=1
	return super.dispatch_after_erosion(delta_s)

func release() -> void:
	var device:=rd
	super.release()
	if device!=null:
		for rid in immutable_inputs:
			if rid.is_valid(): device.free_rid(rid)
	immutable_inputs.clear()
