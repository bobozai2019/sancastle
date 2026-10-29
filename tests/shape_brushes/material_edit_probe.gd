extends "res://tests/shape_brushes/legacy_pair_probe.gd"

var material_cases := []
var spare_seed_done := false

func seed_distinct_material_spares() -> void:
	var tags:=PackedFloat32Array();tags.resize(256*256*2)
	var compact:=PackedFloat32Array();compact.resize(256*256);compact.fill(0.125)
	for i in 256*256: tags[i*2]=0.05;tags[i*2+1]=1.0
	var s: RID=preview.solver._create_texture(RenderingDevice.DATA_FORMAT_R32G32_SFLOAT,tags.to_byte_array())
	var c: RID=preview.solver._create_texture(RenderingDevice.DATA_FORMAT_R16_SFLOAT,preview.solver._float32_to_half_bytes(compact))
	var ok: bool=preview.shape_gpu._copy(s,preview.solver.textures.mold_support[1-preview.solver.current_index]) and preview.shape_gpu._copy(c,preview.solver.textures.compaction[1-preview.solver.current_index])
	preview.solver.rd.free_rid(s);preview.solver.rd.free_rid(c)
	call_deferred("material_spares_seeded",ok)

func material_spares_seeded(ok: bool) -> void:
	_check("distinct_material_spares_seeded",ok);spare_seed_done=true

func read_fault_material_candidate() -> void:
	preview.solver.rd.buffer_get_data_async(preview.shape_gpu.buffers.receipt,_record.bind("candidate_receipt"))
	for name in ["candidate_support","candidate_compact"]:
		preview.solver.rd.texture_get_data_async(preview.shape_gpu.material_transaction.images[name],0,_record.bind(name))

func fault_material_candidate(fault: String) -> Dictionary:
	readbacks.clear();RenderingServer.call_on_render_thread(read_fault_material_candidate)
	var deadline:=Time.get_ticks_msec()+30000
	while readbacks.size()<3 and Time.get_ticks_msec()<deadline: await process_frame
	var positive: bool=readbacks.size()==3 and readbacks.candidate_receipt.decode_u32(12)==1 and readbacks.candidate_support.to_float32_array()[(128*256+128)*2]>0.0
	_check(fault+"_validated_positive_material_candidate",positive)
	var index: Dictionary={}
	for name in readbacks:
		var path:=output.path_join(fault+"_"+name+".bin")
		var file:=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(readbacks[name]);file.close()
		index[name]={"path":path,"bytes":readbacks[name].size(),"sha256":FileAccess.get_sha256(path)}
	return index

func read_all() -> void:
	super.read_all()
	for slot in 2: preview.solver.rd.texture_get_data_async(preview.solver.textures.mold_support[slot],0,_record.bind("mold_support_"+str(slot)))

func open_material_lab() -> void:
	preview=load("res://tests/shape_brushes/brush_lab.tscn").instantiate()
	preview.brush_fixture="dry_flat";preview.playing=false;preview.visual_time_s=0.0;sample_index=0;root.add_child(preview)
	var deadline:=Time.get_ticks_msec()+90000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline: await process_frame
	_check("material_edit_ready",preview.ready_for_ticks,preview.last_error)
	if preview.ready_for_ticks: _check("material_edit_baseline",(await preview.begin_shape_stroke(800)).is_empty())

func molded_command(height: float=0.3) -> Dictionary:
	var value:=command(Vector2.ZERO,Vector2(0.125,0))
	value.material_profile_id=&"molded_v1";value.height_m=height
	return value

func record_case(name: String,before: Dictionary,after: Dictionary,result: Dictionary) -> void:
	material_cases.append({"name":name,"before":before,"after":after,"result":result,"metadata":metadata(),"statistics":preview.shape_gpu.statistics()})

func _run() -> void:
	root.size=Vector2i(1280,720);pair_fields=27
	await open_material_lab()
	if not preview.ready_for_ticks: _finish();quit(1);return
	var before:=await snapshot("formed_before");var before_index: Dictionary=raw_index[-1]
	var result:=await submit(molded_command())
	var after:=await snapshot("formed_after");var after_index: Dictionary=raw_index[-1]
	_check("molded_transaction_accepted",result.get("status")==1 and preview.solver.mold_field_ever_used,result)
	var tags: PackedFloat32Array=after.mold_support_0.to_float32_array();var old: PackedFloat32Array=before.sand.to_float32_array();var sand: PackedFloat32Array=after.sand.to_float32_array()
	var legal: bool=after.mold_support_0==after.mold_support_1;var touched:=0
	for i in sand.size():
		legal=legal and is_equal_approx(tags[i*2],sand[i]-old[i]) and tags[i*2]>=0.0 and tags[i*2]<=sand[i] and tags[i*2+1]==(sand[i] if tags[i*2]>0.0 else 0.0)
		if tags[i*2]>0.0: touched+=1
	_check("molded_added_layer_dual_slots",legal and touched>0,touched)
	record_case("formed",before_index,after_index,result)
	# Reject a valid positive candidate before commit: no field or ledger may change.
	before=after;before_index=after_index;preview.shape_gpu.inject_candidate_failure_once=true
	result=await submit(molded_command(0.5));after=await snapshot("rejected_after")
	_check("rejected_material_candidate_atomic",result.get("status")==3 and exact(before,after),result)
	record_case("candidate_rejected",before_index,raw_index[-1],result)
	await preview.end_shape_stroke()
	before=after;before_index=raw_index[-1]
	var cut_error: StringName=preview.input_scheduler.submit(legacy_command(preview.command_queue.last_command_id+1,&"remove_sand"))
	await settle();after=await snapshot("legacy_cut_after")
	result=preview.input_scheduler.terminal[-1].result
	_check("paused_legacy_cut_accepted",cut_error.is_empty() and result.get("status")==1 and preview.completed_ticks==0,result)
	tags=after.mold_support_0.to_float32_array();old=before.sand.to_float32_array();sand=after.sand.to_float32_array()
	var previous_tags: PackedFloat32Array=before.mold_support_0.to_float32_array()
	legal=after.mold_support_0==after.mold_support_1;var lost:=false
	for i in sand.size():
		var expected:=clampf(previous_tags[i*2]-maxf(old[i]-sand[i],0.0),0.0,sand[i])
		legal=legal and is_equal_approx(tags[i*2],expected) and tags[i*2]<=sand[i] and tags[i*2+1]==(sand[i] if tags[i*2]>0.0 else 0.0)
		lost=lost or tags[i*2]<previous_tags[i*2]
	_check("paused_cut_immediately_weakens_material",legal and lost)
	record_case("legacy_cut",before_index,raw_index[-1],result)
	var transaction=preview.shape_gpu.material_transaction
	var legacy_transaction=preview.solver.legacy_material_transaction
	await preview.shutdown()
	_check("material_transaction_released",transaction.rd==null and transaction.owned.is_empty());preview.queue_free();await process_frame
	_check("legacy_material_transaction_released",legacy_transaction.rd==null and legacy_transaction.owned.is_empty())
	# Original dig transaction can fail after commit while material is nonzero.
	await open_material_lab()
	if preview.ready_for_ticks:
		result=await submit(molded_command());await preview.end_shape_stroke()
		before=await snapshot("legacy_fault_before");before_index=raw_index[-1]
		var source_before: float=preview.shadow_domain.sand_source_m3
		preview.solver.inject_receipt_failure_once=true
		var legacy_error: StringName=preview.input_scheduler.submit(legacy_command(preview.command_queue.last_command_id+1,&"remove_sand"))
		_check("legacy_fault_admitted",legacy_error.is_empty())
		var deadline:=Time.get_ticks_msec()+30000
		while (preview.busy or preview.input_running or not preview.command_queue.pending.is_empty()) and Time.get_ticks_msec()<deadline: await process_frame
		after=await snapshot("legacy_fault_after")
		_check("legacy_nonzero_material_fault_exact",exact(before,after) and preview.shadow_domain.sand_source_m3==source_before and preview.shadow_domain.sand_sink_m3==0.0,preview.last_error)
		record_case("legacy_transport",before_index,raw_index[-1],{"scene_error":preview.last_error})
		legacy_transaction=preview.solver.legacy_material_transaction;await preview.shutdown()
		_check("legacy_fault_material_released",legacy_transaction.rd==null and legacy_transaction.owned.is_empty());preview.queue_free();await process_frame
	for fault in ["transport","identity"]:
		await open_material_lab()
		if not preview.ready_for_ticks: break
		spare_seed_done=false;RenderingServer.call_on_render_thread(seed_distinct_material_spares)
		while not spare_seed_done: await process_frame
		before=await snapshot(fault+"_before");before_index=raw_index[-1]
		_check(fault+"_spares_distinct",before.mold_support_0!=before.mold_support_1 and before.compaction!=before.spare_compaction)
		if fault=="transport": preview.shape_gpu.inject_transport_failure_once=true
		else: preview.shape_gpu.inject_wrong_receipt_once=true
		var error: StringName=preview.input_scheduler.submit(molded_command())
		_check(fault+"_material_admitted",error.is_empty())
		var deadline:=Time.get_ticks_msec()+30000
		while (preview.busy or preview.input_running or not preview.command_queue.pending.is_empty()) and Time.get_ticks_msec()<deadline: await process_frame
		after=await snapshot(fault+"_after")
		_check(fault+"_material_rollback_exact",exact(before,after) and not preview.solver.mold_field_ever_used and preview.shadow_domain.sand_source_m3==0.0,preview.last_error)
		_check(fault+"_material_injection_consumed",not preview.shape_gpu.inject_transport_failure_once if fault=="transport" else not preview.shape_gpu.inject_wrong_receipt_once)
		var candidate: Dictionary=await fault_material_candidate(fault)
		record_case(fault,before_index,raw_index[-1],{"scene_error":preview.last_error})
		material_cases[-1]["candidate"]=candidate
		transaction=preview.shape_gpu.material_transaction;await preview.shutdown()
		_check(fault+"_material_released",transaction.rd==null and transaction.owned.is_empty());preview.queue_free();await process_frame
	var file:=FileAccess.open(output.path_join("material_edit_evidence.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases":material_cases,"material_profile_sha256":FileAccess.get_sha256("res://assets/brushes/molded_material_candidate.json")},"\t"));file.close()
	_finish();var passed:=true
	for row in checks: passed=passed and row.pass
	quit(0 if passed else 1)
