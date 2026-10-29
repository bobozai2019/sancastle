extends "res://tests/shape_brushes/original_retention_lab.gd"

var snapshot_inputs: Array[RID]=[]
var snapshot_copy_count := 0
var snapshot_device: RenderingDevice
var snapshot_identity := {}

func _render_setup(target: SandWaterDomain, token: int) -> void:
	super._render_setup(target,token)
	if solver==null or solver.rd==null or sediment_coupler==null: return
	snapshot_device=solver.rd
	for format_id in [RenderingDevice.DATA_FORMAT_R32_SFLOAT,RenderingDevice.DATA_FORMAT_R32_SFLOAT,RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT,RenderingDevice.DATA_FORMAT_R8_UNORM,RenderingDevice.DATA_FORMAT_R32_SFLOAT,RenderingDevice.DATA_FORMAT_R16_SFLOAT,RenderingDevice.DATA_FORMAT_R16_SFLOAT,RenderingDevice.DATA_FORMAT_R32_SFLOAT]:
		var image: RID=solver._create_texture(format_id,PackedByteArray());snapshot_inputs.append(image)
		if not image.is_valid(): call_deferred("_fail","snapshot diagnostic texture create failed");return
	for rid in sediment_coupler.sets: snapshot_device.free_rid(rid)
	sediment_coupler.sets.clear()
	for live in 2:
		var images: Array[RID]=snapshot_inputs.duplicate()
		images.append_array([solver.textures.sand[live],solver.textures.sediment[live],sediment_coupler.dirty_max_texture])
		var uniforms: Array[RDUniform]=[]
		for binding in images.size():
			var u:=RDUniform.new();u.binding=binding;u.uniform_type=RenderingDevice.UNIFORM_TYPE_IMAGE;u.add_id(images[binding]);uniforms.append(u)
		var set_id:=snapshot_device.uniform_set_create(uniforms,sediment_coupler.shader,0)
		sediment_coupler.sets.append(set_id)
		if not set_id.is_valid(): call_deferred("_fail","snapshot diagnostic set create failed");return
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(spirvs[10].get_stage_bytecode(RenderingDevice.SHADER_STAGE_COMPUTE))
	snapshot_identity={"compiled_spirv_sha256":hash.finish().hex_encode(),"original_source_sha256":FileAccess.get_sha256("res://shaders/simulation/erosion/sediment_step.glsl"),"actual_solver_script":solver.get_script().resource_path,"input_texture_count":8,"input_bytes_requested":65536*37,"scope":"Diagnostic-only immutable input texture copies before original sediment dispatch; original shader and production binding unchanged."}

func _dispatch_coupled_substep(delta_s: float) -> bool:
	if snapshot_inputs.size()!=8: return false
	var live: int=solver.current_index;var old:=1-live
	var sources: Array[RID]=[solver.textures.sediment[old],solver.textures.water[old],solver.textures.flux[live],solver.textures.obstacle,solver.textures.sand[old],solver.textures.wetness[old],solver.textures.compaction[old],solver.textures.water[live]]
	for i in sources.size():
		if snapshot_device.texture_copy(sources[i],snapshot_inputs[i],Vector3.ZERO,Vector3.ZERO,Vector3(256,256,1),0,0,0,0)!=OK: return false
	snapshot_copy_count+=1
	return super._dispatch_coupled_substep(delta_s)

func _render_release() -> void:
	super._render_release()
	if snapshot_device!=null:
		for rid in snapshot_inputs:
			if rid.is_valid(): snapshot_device.free_rid(rid)
	snapshot_inputs.clear();snapshot_device=null
