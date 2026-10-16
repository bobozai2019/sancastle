extends RefCounted

var rd: RenderingDevice
var solver
var owned: Array[RID]=[]
var images := {}
var shader := RID()
var pipeline := RID()
var sets: Array[RID]=[]
var shader_sha256 := ""
var bytes_allocated := 0
var compact_target := 0.95
var last_error := ""
var legacy := false

func _own(rid: RID) -> RID:
	if rid.is_valid(): owned.append(rid)
	return rid

func initialize(owner, buffers: Dictionary, legacy_mode: bool=false) -> bool:
	solver=owner; rd=owner.rd
	legacy=legacy_mode
	if not owner.textures.has("mold_support"): last_error="material fields missing"; return false
	var profile=JSON.parse_string(FileAccess.get_file_as_string("res://assets/brushes/molded_material_candidate.json"))
	if not profile is Dictionary or not is_finite(float(profile.get("compaction_target",-1.0))) or profile.get("compaction_target")!=0.95:
		last_error="material profile invalid"; return false
	# Store an exact half value at or above the requested .95. The D3D12
	# R16F image store otherwise truncates .95 to .94970703125 on this device.
	if profile.get("compaction_storage_value")!=0.9501953125: last_error="material half target invalid";return false
	compact_target=float(profile.compaction_storage_value)
	for item in [["backup_support0",8],["backup_support1",8],["backup_compact0",2],["backup_compact1",2],["candidate_support",8],["candidate_compact",2]]:
		var format_id: int=RenderingDevice.DATA_FORMAT_R32G32_SFLOAT if item[1]==8 else RenderingDevice.DATA_FORMAT_R16_SFLOAT
		images[item[0]]=_own(rd.texture_create(_format(format_id),RDTextureView.new()))
		bytes_allocated+=solver.grid_size*solver.grid_size*int(item[1])
		if not images[item[0]].is_valid(): last_error="material texture create"; return false
	var source := RDShaderSource.new()
	var path: String="res://shaders/simulation/brushes/legacy_material_transaction.glsl" if legacy else "res://shaders/simulation/brushes/material_transaction.glsl"
	source.source_compute=FileAccess.get_file_as_string(path).replace("#[compute]","")
	var code:=rd.shader_compile_spirv_from_source(source)
	last_error=code.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
	if not last_error.is_empty(): return false
	var hash:=HashingContext.new(); hash.start(HashingContext.HASH_SHA256);hash.update(code.get_stage_bytecode(RenderingDevice.SHADER_STAGE_COMPUTE));shader_sha256=hash.finish().hex_encode()
	shader=_own(rd.shader_create_from_spirv(code));pipeline=_own(rd.compute_pipeline_create(shader))
	var uniforms: Array[RDUniform]=[]
	for pair in [[0,buffers.command],[1,buffers.receipt],[2,buffers.cells]]:
		var u:=RDUniform.new();u.binding=pair[0];u.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;u.add_id(pair[1]);uniforms.append(u)
	if not legacy:
		var u:=RDUniform.new();u.binding=3;u.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;u.add_id(buffers.scratch);uniforms.append(u)
	sets.append(_own(rd.uniform_set_create(uniforms,shader,0)))
	uniforms=[]
	var textures: Array[RID]=[owner.textures.mold_support[0],owner.textures.mold_support[1],owner.textures.compaction[0],owner.textures.compaction[1],images.backup_support0,images.backup_support1,images.backup_compact0,images.backup_compact1,images.candidate_support,images.candidate_compact]
	for binding in textures.size():
		var u:=RDUniform.new();u.binding=binding;u.uniform_type=RenderingDevice.UNIFORM_TYPE_IMAGE;u.add_id(textures[binding]);uniforms.append(u)
	sets.append(_own(rd.uniform_set_create(uniforms,shader,1)))
	return shader.is_valid() and pipeline.is_valid() and sets[0].is_valid() and sets[1].is_valid()

func _format(format_id: int) -> RDTextureFormat:
	var format:=RDTextureFormat.new();format.texture_type=RenderingDevice.TEXTURE_TYPE_2D
	format.width=solver.grid_size;format.height=solver.grid_size;format.format=format_id
	format.usage_bits=RenderingDevice.TEXTURE_USAGE_STORAGE_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	return format

func dispatch(phase: int, indirect: RID=RID()) -> void:
	var mark: String="edit_shape_material_%d" % phase
	if solver.profile_passes: rd.capture_timestamp(mark+"_start")
	var list:=rd.compute_list_begin();rd.compute_list_bind_compute_pipeline(list,pipeline)
	rd.compute_list_bind_uniform_set(list,sets[0],0);rd.compute_list_bind_uniform_set(list,sets[1],1)
	var push:=PackedInt32Array([solver.grid_size,solver.current_index,phase,0]).to_byte_array()
	if legacy:
		var rect: Rect2i=solver.edit_window
		push.append_array(PackedInt32Array([rect.position.x,rect.position.y,rect.size.x,rect.size.y]).to_byte_array())
	else: push.append_array(PackedFloat32Array([compact_target,0,0,0]).to_byte_array())
	rd.compute_list_set_push_constant(list,push,32)
	if indirect.is_valid(): rd.compute_list_dispatch_indirect(list,indirect,0 if phase==3 else 36)
	elif legacy and phase==3: rd.compute_list_dispatch(list,1,1,1)
	else: rd.compute_list_dispatch(list,solver.grid_size/16,solver.grid_size/16,1)
	rd.compute_list_end()
	if solver.profile_passes: rd.capture_timestamp(mark+"_end")

func statistics() -> Dictionary:
	return {"rid_count":owned.size(),"bytes":bytes_allocated,"shader_sha256":shader_sha256}

func release() -> void:
	if rd!=null:
		for i in range(owned.size()-1,-1,-1): rd.free_rid(owned[i])
	owned.clear();images.clear();sets.clear();shader=RID();pipeline=RID();bytes_allocated=0;rd=null
