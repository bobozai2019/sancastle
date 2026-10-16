extends RefCounted

const Protocol = preload("res://scripts/simulation/brushes/brush_protocol.gd")
const STAGES := ["begin", "prepare", "reduce", "validate", "commit", "rollback", "shovel_allocate"]
var solver
var rd: RenderingDevice
var owned: Array[RID] = []
var shaders: Array[RID] = []
var pipelines: Array[RID] = []
var sets: Array = []
var buffers: Dictionary = {}
var images: Dictionary = {}
var spirv_hashes: Array[String] = []
var last_error := ""
var baseline_token := 0
var stroke_id := 0
var generation := 0
var last_sample := -1
var active := false
var begin_pending := false
var baseline_copy_count := 0
var baseline_submit_us := -1
var baseline_callback_us := -1
var bytes_allocated := 0
var inject_candidate_failure_once := false
var inject_transport_failure_once := false
var inject_wrong_receipt_once := false
var receipt_diagnostic := {}
var material_transaction
var water_transaction
var castle_template_sha256 := ""

func _remember(rid: RID) -> RID:
	if rid.is_valid(): owned.append(rid)
	return rid

func initialize(owner) -> bool:
	solver = owner; rd = owner.rd; generation = owner.owner_generation
	var castle_definition=Protocol.registry.definition(&"castle_v1")
	if castle_definition==null:last_error="castle definition identity";return false
	var template_path: String=castle_definition.template_path
	if not FileAccess.file_exists(template_path):last_error="castle template missing";return false
	var template_bytes:=FileAccess.get_file_as_bytes(template_path)
	if template_bytes.size()!=65*65*16: last_error="castle template size"; return false
	var template_values:=template_bytes.to_float32_array()
	for i in 65*65:
		var h:float=template_values[i*4]
		if not is_finite(h) or h<0.0 or h>1.0 or template_values[i*4+1] not in [0.0,1.0] or template_values[i*4+2] not in [0.0,1.0] or template_values[i*4+3]!=0.0:
			last_error="castle template data";return false
	castle_template_sha256=FileAccess.get_sha256(template_path)
	var template_format:=RDTextureFormat.new()
	template_format.width=65;template_format.height=65;template_format.format=RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	template_format.usage_bits=RenderingDevice.TEXTURE_USAGE_STORAGE_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	images["castle_template"]=_remember(rd.texture_create(template_format,RDTextureView.new(),[template_bytes]))
	if not images.castle_template.is_valid(): last_error="castle template allocation";return false
	bytes_allocated+=template_bytes.size()
	for item in [["command",256],["receipt",256],["cells",256*256*64],["scratch",256*64+128]]:
		buffers[item[0]] = _remember(rd.storage_buffer_create(item[1]))
		bytes_allocated += item[1]
	for item in [["baseline",4],["coverage",8],["candidate",8],["backup_coverage",8],["backup_sand0",4],["backup_sand1",4]]:
		var format_id: int = RenderingDevice.DATA_FORMAT_R32_SFLOAT if item[1]==4 else RenderingDevice.DATA_FORMAT_R32G32_SFLOAT
		images[item[0]] = _remember(solver._create_texture(format_id,PackedByteArray()))
		bytes_allocated += 256*256*int(item[1])
	for stage in STAGES:
		var source := RDShaderSource.new()
		source.source_compute = FileAccess.get_file_as_string("res://shaders/simulation/brushes/"+stage+".glsl").replace("#[compute]","")
		var code: RDShaderSPIRV = rd.shader_compile_spirv_from_source(source)
		var error := code.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
		if not error.is_empty(): last_error = stage+": "+error; return false
		var hash := HashingContext.new(); hash.start(HashingContext.HASH_SHA256); hash.update(code.get_stage_bytecode(RenderingDevice.SHADER_STAGE_COMPUTE)); spirv_hashes.append(hash.finish().hex_encode())
		var shader := _remember(rd.shader_create_from_spirv(code)); shaders.append(shader)
		if not shader.is_valid(): last_error = stage+" shader create"; return false
		var pipeline := _remember(rd.compute_pipeline_create(shader)); pipelines.append(pipeline)
		if not pipeline.is_valid(): last_error = stage+" pipeline create"; return false
	var sand := {1:solver.textures.sand[0],2:solver.textures.sand[1]}
	sets.append([_uniform_set(0,0,{1:buffers.receipt},{4:images.baseline,5:images.coverage,6:images.candidate}),_uniform_set(0,1,{}, {0:solver.textures.rock,1:sand[1],2:sand[2]})])
	sets.append([_uniform_set(1,0,{0:buffers.command,2:buffers.cells,3:buffers.scratch},{4:images.baseline,5:images.coverage,6:images.candidate,7:images.castle_template}),_uniform_set(1,1,{}, {0:solver.textures.rock,1:sand[1],2:sand[2],3:solver.textures.water[0],4:solver.textures.water[1],15:solver.textures.obstacle})])
	sets.append([_uniform_set(2,0,{2:buffers.cells,3:buffers.scratch},{}),RID()])
	sets.append([_uniform_set(3,0,{0:buffers.command,1:buffers.receipt,3:buffers.scratch},{}),RID()])
	sets.append([_uniform_set(4,0,{1:buffers.receipt,2:buffers.cells},{5:images.coverage,6:images.candidate}),_uniform_set(4,1,{},sand)])
	sets.append([_uniform_set(5,0,{}, {0:images.backup_sand0,1:images.backup_sand1,2:images.backup_coverage,5:images.coverage}),_uniform_set(5,1,{},sand)])
	sets.append([_uniform_set(6,0,{0:buffers.command,2:buffers.cells,3:buffers.scratch},{6:images.candidate}),_uniform_set(6,1,{}, {13:solver.textures.compaction[0],14:solver.textures.compaction[1],16:solver.textures.mold_support[0],17:solver.textures.mold_support[1]})])
	for index in sets.size():
		if not sets[index][0].is_valid() or (index in [0,1,4,5,6] and not sets[index][1].is_valid()): last_error="uniform set"; return false
	material_transaction=preload("res://scripts/simulation/brushes/brush_material_transaction.gd").new()
	if not material_transaction.initialize(solver,buffers): last_error=material_transaction.last_error; return false
	if owner.brush_water_enabled:
		water_transaction=preload("res://scripts/simulation/brushes/brush_water_transaction.gd").new()
		if not water_transaction.initialize(solver,buffers):last_error=water_transaction.last_error;return false
	return true

func _uniform_set(stage: int, set_index: int, storage: Dictionary, textures: Dictionary) -> RID:
	var uniforms: Array[RDUniform] = []
	for binding in storage:
		var uniform := RDUniform.new(); uniform.binding=binding; uniform.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER; uniform.add_id(storage[binding]); uniforms.append(uniform)
	for binding in textures:
		var uniform := RDUniform.new(); uniform.binding=binding; uniform.uniform_type=RenderingDevice.UNIFORM_TYPE_IMAGE; uniform.add_id(textures[binding]); uniforms.append(uniform)
	return _remember(rd.uniform_set_create(uniforms,shaders[stage],set_index))

func _dispatch(stage: int, phase: int=0) -> void:
	var mark := "edit_shape_%d_%d" % [solver.active_ticket,stage]
	if solver.profile_passes: rd.capture_timestamp(mark+"_start")
	var list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list,pipelines[stage])
	rd.compute_list_bind_uniform_set(list,sets[stage][0],0)
	if sets[stage][1].is_valid(): rd.compute_list_bind_uniform_set(list,sets[stage][1],1)
	var actual_phase:int=2 if water_transaction!=null and stage in [1,6] and phase==0 else phase
	rd.compute_list_set_push_constant(list,PackedInt32Array([256,0,0,256,256,solver.current_index,actual_phase,0]).to_byte_array(),32)
	if phase==1 or stage==6: rd.compute_list_dispatch(list,1,1,1)
	elif stage==2: rd.compute_list_dispatch(list,256,1,1)
	elif stage==3: rd.compute_list_dispatch(list,1,1,1)
	else: rd.compute_list_dispatch(list,16,16,1)
	rd.compute_list_end()
	if solver.profile_passes: rd.capture_timestamp(mark+"_end")

func begin(stroke: int, token: int, callback: Callable) -> bool:
	if rd==null or solver._writes_locked() or active or begin_pending or stroke<=0 or token<=0: return false
	stroke_id=stroke; baseline_token=token; last_sample=-1; begin_pending=true
	solver.receipt_pending=true; baseline_submit_us=Time.get_ticks_usec()
	var clear := PackedByteArray(); clear.resize(256); clear.fill(0)
	rd.buffer_update(buffers.receipt,0,256,clear)
	_dispatch(0)
	var error := rd.buffer_get_data_async(buffers.receipt,_baseline_ready.bind(callback,generation,token))
	if error!=OK: begin_pending=false; solver.receipt_pending=false; return false
	return true

func _baseline_ready(data: PackedByteArray, callback: Callable, epoch: int, token: int) -> void:
	if rd==null or not begin_pending or generation!=epoch or baseline_token!=token: return
	begin_pending=false; solver.receipt_pending=false; baseline_callback_us=Time.get_ticks_usec()
	active=data.size()==256 and data.decode_u32(252)==0xbeefcafe
	if active: baseline_copy_count+=1
	callback.call(active)

func end(token: int) -> bool:
	if rd==null or begin_pending or solver._writes_locked() or token!=baseline_token: return false
	active=false; baseline_token=0; stroke_id=0; last_sample=-1
	return true

func _copy(source: RID, target: RID) -> bool:
	return rd.texture_copy(source,target,Vector3.ZERO,Vector3.ZERO,Vector3(256,256,1),0,0,0,0)==OK

func _rollback() -> void:
	_dispatch(5)
	material_transaction.dispatch(2)
	if water_transaction!=null:water_transaction.rollback()
	receipt_diagnostic.rollback_dispatched=true

func dispatch(data: PackedByteArray, callback: Callable, execution_tick: int) -> bool:
	if data.size()==256 and data.decode_u32(12)==1 and data.slice(216,248).hex_encode()!=castle_template_sha256: return false
	if rd==null or not active or solver._writes_locked() or data.size()!=256 or not callback.is_valid(): return false
	if data.decode_u32(0)!=Protocol.COMMAND_MAGIC or data.decode_u32(4)!=2 or data.decode_u32(8)!=256 or data.decode_s64(40)!=generation or data.decode_s64(56)!=solver.state_revision or data.decode_s64(64)!=baseline_token or data.decode_s64(32)!=stroke_id or data.decode_u32(80)<=last_sample: return false
	if not _copy(solver.textures.sand[0],images.backup_sand0) or not _copy(solver.textures.sand[1],images.backup_sand1) or not _copy(images.coverage,images.backup_coverage): return false
	if water_transaction!=null and not water_transaction.backup():return false
	var receipt := PackedByteArray(); receipt.resize(256); receipt.fill(0)
	receipt.encode_u32(0,Protocol.RECEIPT_MAGIC); receipt.encode_u32(4,2); receipt.encode_u32(8,256)
	for pair in [[16,16],[24,24],[32,32],[40,40],[48,56],[56,56],[72,64]]: receipt.encode_s64(pair[0],data.decode_s64(pair[1]))
	receipt.encode_s64(64,execution_tick); receipt.encode_u32(84,data.decode_u32(80))
	if inject_candidate_failure_once: receipt.encode_u32(80,16); inject_candidate_failure_once=false
	if rd.buffer_update(buffers.command,0,256,data)!=OK or rd.buffer_update(buffers.receipt,0,256,receipt)!=OK: return false
	solver.receipt_pending=true; solver.settlement_authorized=false; solver.active_ticket=data.decode_s64(16)
	last_sample=data.decode_u32(80)
	if data.decode_u32(12)==1: _dispatch(1,1)
	_dispatch(1)
	if data.decode_u32(12)==3: _dispatch(6)
	material_transaction.dispatch(0)
	for stage in [2,3]: _dispatch(stage)
	if water_transaction!=null:water_transaction.prepare(data)
	_dispatch(4)
	material_transaction.dispatch(1)
	if water_transaction!=null:water_transaction.commit()
	if inject_transport_failure_once:
		inject_transport_failure_once=false; _rollback(); solver.receipt_pending=false; return false
	var error := rd.buffer_get_data_async(buffers.receipt,_receipt_ready.bind(callback,data,solver.state_revision))
	if error!=OK: _rollback(); solver.receipt_pending=false; return false
	return true

func _receipt_ready(bytes: PackedByteArray, callback: Callable, data: PackedByteArray, revision: int) -> void:
	# Readback callbacks are delivered while the device processes completed work.
	# Queue further GPU mutations through the render owner, outside that callback.
	call_deferred("_schedule_finalize",bytes,callback,data,revision)

func _schedule_finalize(bytes: PackedByteArray, callback: Callable, data: PackedByteArray, revision: int) -> void:
	RenderingServer.call_on_render_thread(_finalize_receipt.bind(bytes,callback,data,revision))

func _finalize_receipt(bytes: PackedByteArray, callback: Callable, data: PackedByteArray, revision: int) -> void:
	if rd==null: return
	if inject_wrong_receipt_once: bytes.encode_s64(16,bytes.decode_s64(16)+1); inject_wrong_receipt_once=false
	var receipt := Protocol.decode_receipt(bytes)
	var brush_id: StringName=&"castle_v1" if data.decode_u32(12)==1 else (&"wall_v1" if data.decode_u32(12)==2 else &"shovel_v1")
	var command := {"command_id":data.decode_s64(24),"stroke_id":data.decode_s64(32),"generation":data.decode_s64(40),"baseline_token":data.decode_s64(64),"sample_index":data.decode_u32(80),"brush_id":brush_id}
	receipt_diagnostic={"receipt":receipt,"expected_ticket":solver.active_ticket,"expected_revision":revision,"matches":Protocol.receipt_matches(receipt,command,solver.active_ticket,revision)}
	if not Protocol.receipt_matches(receipt,command,solver.active_ticket,revision) or solver.state_revision!=revision:
		_rollback()
		# Keep the shared writer lock until a readback after the restore completes.
		var error := rd.texture_get_data_async(images.coverage,0,_rollback_ready.bind(bytes,callback))
		if error==OK: return
		last_error="rollback readback failed"
	elif receipt.status==1:
		solver.state_revision=receipt.output_revision; solver.publication_pending=true
		if data.decode_u32(92)==1: solver.mold_field_ever_used=true
	solver.receipt_pending=false; solver.receipt_callback_us=Time.get_ticks_usec()
	callback.call(bytes)

func _rollback_ready(_coverage: PackedByteArray, bytes: PackedByteArray, callback: Callable) -> void:
	if rd==null: return
	solver.receipt_pending=false; solver.receipt_callback_us=Time.get_ticks_usec()
	callback.call(bytes)

func statistics() -> Dictionary:
	var material: Dictionary=material_transaction.statistics() if material_transaction!=null else {"rid_count":0,"bytes":0}
	var water:Dictionary=water_transaction.statistics() if water_transaction!=null else {"rid_count":0,"bytes":0}
	return {"rid_count":owned.size()+material.rid_count+water.rid_count,"bytes":bytes_allocated+material.bytes+water.bytes,"core_rid_count":owned.size(),"core_bytes":bytes_allocated,"material_transaction":material,"water_transaction":water,"active":active,"baseline_token":baseline_token,"stroke_id":stroke_id,"baseline_copy_count":baseline_copy_count,"baseline_submit_us":baseline_submit_us,"baseline_callback_us":baseline_callback_us,"spirv_hashes":spirv_hashes.duplicate(),"receipt_diagnostic":receipt_diagnostic.duplicate(true)}

func release() -> void:
	if rd==null:return
	if water_transaction!=null:water_transaction.release();water_transaction=null
	if material_transaction!=null: material_transaction.release(); material_transaction=null
	for i in range(owned.size()-1,-1,-1):
		if owned[i].is_valid(): rd.free_rid(owned[i])
	owned.clear(); sets.clear(); shaders.clear(); pipelines.clear(); buffers.clear(); images.clear()
	bytes_allocated=0; active=false; baseline_token=0; begin_pending=false; rd=null
