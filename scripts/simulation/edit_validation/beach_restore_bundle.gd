extends RefCounted

var gravel_field
var gravel_initialization := ""

const Foam=preload("res://scripts/simulation/edit_validation/checkpoint_foam_field.gd")
const Front=preload("res://tests/visual_water_alignment/prototypes/reference_local_front_field.gd")
const Audit=preload("res://scripts/simulation/gpu_sand_audit.gd")
const Sediment=preload("res://scripts/simulation/erosion/gpu_sediment_coupler.gd")
const Collision=preload("res://scripts/collision/gpu_collision_proxy.gd")
var solver
var foam_field
var local_front_field
var sand_audit
var sediment_coupler
var material_coupler
var stable_q := {}
var collision := {}
var pending := 0
var expected := {}
var observed := {}
var error: StringName=&""
var done := false
var released := false
var last_callback_us := -1
var release_us := -1

func build(owner, checkpoint: Dictionary, domain) -> bool:
	solver=owner._create_solver()
	if not solver.initialize(RenderingServer.get_rendering_device(),domain,owner.spirvs[0],owner.spirvs[1],owner.spirvs[2],owner.spirvs[3],owner.spirvs[4],owner.spirvs[5],owner.spirvs[6],owner.spirvs[7],checkpoint.fields.momentum_x,checkpoint.fields.momentum_z): return false
	var native: Dictionary=checkpoint.gpu_beach_native
	if not solver.restore_native_fields(native.fields,checkpoint.revision,native.spare,native.current_index): return false
	if not owner._restore_native_extensions(solver,native): return false
	solver.water_source_m3=checkpoint.water_source_m3;solver.water_sink_m3=checkpoint.water_sink_m3
	foam_field=Foam.new();foam_field.native_history=native.foam.duplicate(true)
	var bed: PackedFloat32Array=native.fields.rock.to_float32_array()
	var sand: PackedFloat32Array=native.fields.sand.to_float32_array()
	for i in bed.size(): bed[i]+=sand[i]
	if not foam_field.initialize(solver,owner.spirvs[17],checkpoint.foam_history,bed,owner.prototype_front_band_foam_source): return false
	local_front_field=Front.new()
	if not local_front_field.initialize(solver,foam_field,owner.local_front_x_spirv,owner.local_front_z_spirv,checkpoint.local_front_history): return false
	if owner.prototype_front_band_foam_source and not foam_field.configure_uniforms(solver,local_front_field.texture): return false
	sand_audit=Audit.new()
	if not sand_audit.initialize(solver,owner.spirvs[9]): return false
	sediment_coupler=Sediment.new()
	if not sediment_coupler.initialize(solver,owner.spirvs[10],owner.spirvs[11]): return false
	material_coupler=owner._create_material_coupler()
	material_coupler.cohesion_yield_height_m=checkpoint.sand_cohesion_yield_height_m
	if not material_coupler.initialize(solver,sediment_coupler.dirty_max_texture,owner.spirvs[12],owner.spirvs[13],owner.spirvs[14]): return false
	var rd: RenderingDevice=solver.rd
	collision.shader=rd.shader_create_from_spirv(owner.spirvs[8])
	if not collision.shader.is_valid(): return false
	collision.pipeline=rd.compute_pipeline_create(collision.shader)
	collision.chunk_buffer=rd.storage_buffer_create(Collision.MAX_BATCH_CHUNKS*4)
	if not collision.pipeline.is_valid() or not collision.chunk_buffer.is_valid(): return false
	for field in ["momentum_x","momentum_z"]:
		stable_q[field]=solver._create_texture(RenderingDevice.DATA_FORMAT_R32_SFLOAT,PackedByteArray())
		if not stable_q[field].is_valid() or rd.texture_copy(solver.current_texture(field),stable_q[field],Vector3.ZERO,Vector3.ZERO,Vector3(256,256,1),0,0,0,0)!=OK: return false
	# gpu_water_editor.publish_sand also publishes its stable water texture.
	solver.publish_sand()
	for field in native.fields: _verify(owner,solver.current_texture(field),"raw_"+field,native.fields[field])
	for field in native.spare: _verify(owner,solver.textures[field][1-solver.current_index],"spare_"+field,native.spare[field])
	if native.version==2:
		_verify(owner,solver.textures.mold_support[solver.current_index],"material_current",native.material.current_support)
		_verify(owner,solver.textures.mold_support[1-solver.current_index],"material_spare",native.material.spare_support)
	for index in 2:
		_verify(owner,foam_field.textures[index],"foam_%d"%index,native.foam["foam_%d"%index])
		_verify(owner,foam_field.bed_textures[index],"bed_%d"%index,native.foam["bed_%d"%index])
	_verify(owner,local_front_field.texture,"local_front",checkpoint.local_front_history.to_byte_array())
	return error.is_empty()

func _verify(owner, texture: RID, key: String, bytes: PackedByteArray) -> void:
	expected[key]=bytes;pending+=1
	if solver.rd.texture_get_data_async(texture,0,_on_field.bind(owner,key))!=OK:
		pending-=1;error=&"candidate_readback_failed"

func _on_field(bytes: PackedByteArray, owner, key: String) -> void:
	owner.call_deferred("_beach_restore_field",self,bytes,key)

func record(bytes: PackedByteArray, key: String) -> void:
	last_callback_us=Time.get_ticks_usec()
	observed[key]=bytes;pending-=1
	if bytes!=expected[key]: error=&"candidate_native_mismatch"

func release() -> void:
	if released: return
	assert(pending==0)
	if gravel_field!=null: gravel_field.release(); gravel_field=null
	if solver!=null:
		# Free dependent uniforms/pipeline before their shader. Godot invalidates
		# dependent RIDs when a shader is freed.
		for key in ["uniform_set","pipeline","chunk_buffer","shader"]:
			var rid: RID=collision.get(key,RID())
			if rid.is_valid(): solver.rd.free_rid(rid)
	if foam_field!=null: foam_field.release_uniform_sets()
	for object in [local_front_field,foam_field,material_coupler,sediment_coupler,sand_audit]:
		if object!=null: object.release()
	if solver!=null:
		for rid in stable_q.values():
			if rid.is_valid(): solver.rd.free_rid(rid)
		solver.release()
	released=true
	release_us=Time.get_ticks_usec()
