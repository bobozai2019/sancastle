extends "res://scripts/simulation/edit_validation/beach_restore_bundle.gd"

const Controller=preload("res://scripts/simulation/edit_validation/frame_pipeline/async_controller.gd")
const Snapshot=preload("res://scripts/simulation/edit_validation/frame_pipeline/async_checkpoint_codec.gd")
var controller
var shape_gpu
var preview_query
var epoch:=0
var build_phase:="idle"
var inject_registration_failures:=0
var inject_terminal_unavailable:=false
var inject_build_failure_phase:=""
var discard_requested:=false
var terminal_pending:=false
var terminal_done:=false
var unconfirmed_ownership:=false
var release_queued:=false
var terminal_proofs:=0
var discard_request_started:=false
var hold_results:=false
var held_results:=[]

func record(bytes: PackedByteArray, key: String) -> void:
	if released or observed.has(key) or not expected.has(key):return
	if hold_results:
		held_results.append([bytes,key]);return
	super.record(bytes,key)

func release_held_results() -> void:
	hold_results=false
	for row in held_results:record(row[0],row[1])
	held_results.clear()

static func domain_from(checkpoint: Dictionary, generation: int):
	var domain=preload("res://scripts/simulation/sand_water_domain.gd").new(256,0.125)
	domain.domain_id=StringName(checkpoint.domain_id)
	domain.generation=generation
	domain.sim_tick=checkpoint.sim_tick
	var fields: Dictionary=checkpoint.native.fields
	for field in ["rock","sand","water","sediment"]:domain.set(field,fields[field].to_float32_array())
	for field in ["wetness","compaction","obstacle"]:
		var values:=PackedFloat32Array();values.resize(65536)
		for i in 65536:values[i]=float(fields[field][i])/255.0 if field=="obstacle" else fields[field].decode_half(i*2)
		domain.set(field,values)
	var flux: PackedFloat32Array=fields.flux.to_float32_array()
	for channel in 4:
		var values:=PackedFloat32Array();values.resize(65536)
		for i in 65536:values[i]=flux[i*4+channel]
		domain.set(["flux_left","flux_right","flux_up","flux_down"][channel],values)
	for key in Snapshot.LEDGER:domain.set(key,checkpoint.ledger[key])
	return domain

func build_async(owner, checkpoint: Dictionary, domain) -> bool:
	epoch=domain.generation
	var native: Dictionary=checkpoint.native
	build_phase="solver_initialize"
	solver=owner._create_solver()
	if not solver.initialize(RenderingServer.get_rendering_device(),domain,owner.spirvs[0],owner.spirvs[1],owner.spirvs[2],owner.spirvs[3],owner.spirvs[4],owner.spirvs[5],owner.spirvs[6],owner.spirvs[7],native.fields.momentum_x.to_float32_array(),native.fields.momentum_z.to_float32_array()):return false
	build_phase="authority_restore"
	if not solver.restore_native_fields(native.fields,checkpoint.revision,native.spare,0):return false
	if not solver.restore_native_material(native.material,native.fields.sand,native.spare.sand,0):return false
	if inject_build_failure_phase==build_phase:return false
	solver.water_source_m3=checkpoint.ledger.water_source_m3
	solver.water_sink_m3=checkpoint.ledger.water_sink_m3
	solver.prescribed_tide_boundary=checkpoint.simulation.prescribed_tide_boundary
	build_phase="visual_histories"
	foam_field=Foam.new();foam_field.native_history=native.foam.duplicate(true)
	var bed: PackedFloat32Array=native.fields.rock.to_float32_array()
	var sand: PackedFloat32Array=native.fields.sand.to_float32_array()
	for i in bed.size():bed[i]+=sand[i]
	if not foam_field.initialize(solver,owner.spirvs[17],PackedFloat32Array(),bed,owner.prototype_front_band_foam_source):return false
	if checkpoint.simulation.local_front_history:
		local_front_field=Front.new()
		if not local_front_field.initialize(solver,foam_field,owner.local_front_x_spirv,owner.local_front_z_spirv,native.histories.local_front.to_float32_array()):return false
	if owner.prototype_front_band_foam_source and not foam_field.configure_uniforms(solver,local_front_field.texture):return false
	build_phase="couplers"
	sand_audit=Audit.new()
	if not sand_audit.initialize(solver,owner.spirvs[9]):return false
	sediment_coupler=Sediment.new()
	if not sediment_coupler.initialize(solver,owner.spirvs[10],owner.spirvs[11]):return false
	material_coupler=owner._create_material_coupler()
	material_coupler.cohesion_yield_height_m=checkpoint.cohesion_yield_height_m
	if not material_coupler.initialize(solver,sediment_coupler.dirty_max_texture,owner.spirvs[12],owner.spirvs[13],owner.spirvs[14]):return false
	# Old controlled tools still use these resources, independently of new height slots.
	build_phase="legacy_resources"
	var rd: RenderingDevice=solver.rd
	collision.shader=rd.shader_create_from_spirv(owner.spirvs[8])
	if not collision.shader.is_valid():return false
	collision.pipeline=rd.compute_pipeline_create(collision.shader)
	collision.chunk_buffer=rd.storage_buffer_create(Collision.MAX_BATCH_CHUNKS*4)
	if not collision.pipeline.is_valid() or not collision.chunk_buffer.is_valid():return false
	for field in ["momentum_x","momentum_z"]:
		stable_q[field]=solver._create_texture(RenderingDevice.DATA_FORMAT_R32_SFLOAT,PackedByteArray())
		if not stable_q[field].is_valid() or rd.texture_copy(solver.current_texture(field),stable_q[field],Vector3.ZERO,Vector3.ZERO,Vector3(256,256,1),0,0,0,0)!=OK:return false
	gravel_field=owner._new_gravel(solver,epoch,checkpoint.sim_tick,checkpoint.revision,checkpoint)
	if owner.gravel_enabled and gravel_field==null:return false
	shape_gpu=preload("res://scripts/simulation/brushes/brush_gpu.gd").new()
	if not shape_gpu.initialize(solver):return false
	preview_query=preload("res://scripts/simulation/brushes/brush_preview_query.gd").new()
	if not preview_query.initialize(solver,shape_gpu.images.castle_template):return false
	build_phase="controller"
	controller=Controller.new(owner,epoch)
	if not controller.initialize_render({"solver":solver,"shape_gpu":shape_gpu,"sediment_coupler":sediment_coupler,"material_coupler":material_coupler,"foam_field":foam_field,"gravel_field":gravel_field,"local_front_field":local_front_field}):return false
	build_phase="control_seed"
	var control: PackedByteArray=native.control.duplicate()
	control.encode_u64(8,epoch)
	if rd.buffer_update(solver.async_transport.control,0,control.size(),control)!=OK:return false
	var clock:=PackedFloat32Array([checkpoint.advanced_time_s]).to_byte_array()
	if rd.texture_update(solver.async_transport.clock_texture,0,clock)!=OK:return false
	build_phase="verify_readbacks"
	solver.publish_sand()
	for field in native.fields:_verify(owner,solver.current_texture(field),"field/"+field,native.fields[field])
	for field in native.spare:_verify(owner,solver.textures[field][1],"spare/"+field,native.spare[field])
	_verify(owner,solver.textures.mold_support[0],"material_current",native.material.current_support)
	_verify(owner,solver.textures.mold_support[1],"material_spare",native.material.spare_support)
	for index in 2:
		_verify(owner,foam_field.textures[index],"foam_%d"%index,native.foam["foam_%d"%index])
		_verify(owner,foam_field.bed_textures[index],"bed_%d"%index,native.foam["bed_%d"%index])
		if gravel_field!=null:_verify(owner,gravel_field.textures[index],"gravel_%d"%index,checkpoint.visual_extensions.gravel_v1["state_%d"%index])
	if local_front_field!=null:_verify(owner,local_front_field.texture,"local_front",native.histories.local_front)
	_verify(owner,solver.published_sand,"published_sand",native.fields.sand)
	_verify(owner,solver.published_water,"published_water",native.fields.water)
	_verify(owner,solver.async_transport.clock_texture,"clock",clock)
	expected.control=control;pending+=1
	var status: Error=ERR_UNAVAILABLE
	if inject_registration_failures>0:inject_registration_failures-=1
	else:status=rd.buffer_get_data_async(solver.async_transport.control,_on_field.bind(owner,"control"),0,control.size())
	if status!=OK:pending-=1;error=&"candidate_readback_failed"
	return error.is_empty()

func _verify(owner, texture: RID, key: String, bytes: PackedByteArray) -> void:
	if inject_registration_failures>0:
		inject_registration_failures-=1
		expected[key]=bytes
		error=&"candidate_readback_failed"
		return
	super._verify(owner,texture,key,bytes)

func request_discard(owner) -> void:
	discard_requested=true
	discard_request_started=true
	if terminal_done or terminal_pending:return
	terminal_pending=true
	# The active control exists even when candidate initialization stopped before
	# its own transport was built. Both streams use the same main RD ordering.
	if inject_terminal_unavailable or owner.solver.async_transport.request_fence(_discard_arrived.bind(owner))!=OK:
		owner.call_deferred("_async_candidate_terminal",self,false)

func _discard_arrived(_bytes: PackedByteArray, owner) -> void:
	owner.call_deferred("_async_candidate_terminal",self,true)

func release() -> void:
	if released:return
	if discard_requested and not terminal_done:return
	if pending!=0:push_error("candidate release before final readback");return
	if controller!=null:
		if not controller.release_render():push_error("candidate controller still owned");return
		controller=null
	if preview_query!=null:preview_query.release();preview_query=null
	if shape_gpu!=null:shape_gpu.release();shape_gpu=null
	super.release()
