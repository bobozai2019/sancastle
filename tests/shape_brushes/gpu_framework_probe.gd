extends "res://tests/water_material_natural/rdc_main_smoke.gd"

const BrushProtocol = preload("res://scripts/simulation/brushes/brush_protocol.gd")
const SPARES := ["sand","water","momentum_x","momentum_z","sediment","wetness","compaction","flux"]
var expected_fields := 0
var direct_result: Variant = null
var sample_index := 0
var raw_index := []

func read_all() -> void:
	for field in FIELDS: preview.solver.rd.texture_get_data_async(preview.solver.current_texture(field),0,_record.bind(field))
	for field in SPARES: preview.solver.rd.texture_get_data_async(preview.solver.textures[field][1-preview.solver.current_index],0,_record.bind("spare_"+field))
	for item in [["published_sand",preview.solver.published_sand],["published_water",preview.solver.published_water],["baseline",preview.shape_gpu.images.baseline],["coverage",preview.shape_gpu.images.coverage],["foam0",preview.foam_field.textures[0]],["foam1",preview.foam_field.textures[1]],["bed0",preview.foam_field.bed_textures[0]],["bed1",preview.foam_field.bed_textures[1]],["local_front",preview.local_front_field.texture]]: preview.solver.rd.texture_get_data_async(item[1],0,_record.bind(item[0]))

func snapshot(tag: String) -> Dictionary:
	readbacks.clear(); expected_fields=FIELDS.size()+SPARES.size()+9
	RenderingServer.call_on_render_thread(read_all)
	var deadline := Time.get_ticks_msec()+30000
	while readbacks.size()<expected_fields and Time.get_ticks_msec()<deadline: await process_frame
	_check(tag+"_complete_readback",readbacks.size()==expected_fields,readbacks.size())
	var state := readbacks.duplicate(true)
	var index := {}
	for key in state:
		var path := output.path_join(tag+"_"+key+".bin")
		var file := FileAccess.open(path,FileAccess.WRITE); file.store_buffer(state[key]); file.close()
		index[key]={"path":path,"bytes":state[key].size(),"sha256":FileAccess.get_sha256(path)}
	raw_index.append({"tag":tag,"fields":index,"revision":preview.solver.state_revision,"generation":preview.generation,"source":preview.shadow_domain.sand_source_m3,"sink":preview.shadow_domain.sand_sink_m3,"inventory":preview.shadow_domain.tool_inventory_m3})
	return state

func exact(a: Dictionary,b: Dictionary,exclude: Array = []) -> bool:
	if a.size()!=b.size(): return false
	for key in a:
		if key not in exclude and a[key]!=b[key]: return false
	return true

func command(start: Vector2, finish: Vector2, zero_budget: bool = false) -> Dictionary:
	var value := BrushProtocol.make_command(&"wall_v1",{"height_m":0.3,"bottom_width_m":1.0,"top_width_m":0.5},start,finish,preview.domain.domain_id,preview.generation,preview.command_queue.last_command_id+1,preview.shape_stroke_id,sample_index,preview.completed_ticks,preview.shape_baseline_token)
	sample_index+=1
	if zero_budget: value.add_budget_m3=0.0
	return value

func settle() -> void:
	var deadline := Time.get_ticks_msec()+30000
	while (preview.busy or preview.input_running or preview.input_scheduler.pumping or not preview.command_queue.pending.is_empty()) and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline: await process_frame
	_check("bounded_settlement",not preview.busy and not preview.input_running and preview.command_queue.pending.is_empty(),preview.last_error)

func submit(value: Dictionary) -> Dictionary:
	var error: StringName=preview.input_scheduler.submit(value)
	_check("admit_v2",error.is_empty(),String(error))
	await settle()
	return preview.input_scheduler.terminal[-1].result if not preview.input_scheduler.terminal.is_empty() else {}

func render_locked() -> void:
	call_deferred("locked_done",not preview.solver.dispatch_substep(1.0/30.0))

func locked_done(value: bool) -> void: direct_result=value

func render_old_epoch(data: PackedByteArray) -> void:
	data.encode_s64(40,preview.generation-1)
	var rejected: bool = not preview.shape_gpu.dispatch(data,Callable(self,"unused_receipt"),preview.completed_ticks)
	call_deferred("locked_done",rejected)

func unused_receipt(_bytes: PackedByteArray) -> void: _check("unexpected_stale_callback",false)

func _run() -> void:
	root.size=Vector2i(1280,720)
	preview=load("res://tests/shape_brushes/brush_lab.tscn").instantiate()
	preview.brush_fixture="dry_slope"; root.add_child(preview)
	var deadline := Time.get_ticks_msec()+90000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline: await process_frame
	_check("gpu_backend_ready",preview.ready_for_ticks and preview.shape_backend_ready,preview.last_error)
	if not preview.ready_for_ticks: _finish(); quit(1); return
	var initial := await snapshot("initial")
	var begin_error: StringName=await preview.begin_shape_stroke(71)
	_check("begin_gpu_baseline",begin_error.is_empty() and preview.shape_gpu.active,String(begin_error))
	if not begin_error.is_empty(): _finish(); quit(1); return
	var baseline := await snapshot("baseline")
	_check("begin_keeps_authoritative_fields",exact(initial,baseline,["baseline"]))
	var expected := PackedFloat32Array()
	for i in 65536: expected.append(preview.domain.rock[i]+preview.domain.sand[i])
	_check("gpu_baseline_is_actual_bed",baseline.baseline==expected.to_byte_array())
	var count: int=preview.shape_gpu.owned.size()
	var result := await submit(command(Vector2.ZERO,Vector2.ZERO))
	_check("zero_segment_no_change",result.get("status")==2 and preview.solver.state_revision==0,result)
	if result.get("status")!=2: await preview.shutdown(); _finish(); quit(1); return
	var unchanged := await snapshot("no_change")
	_check("no_change_exact",exact(baseline,unchanged))
	var valid := command(Vector2.ZERO,Vector2(0.125,0))
	preview.hold_shape_receipt=true
	_check("admit_held_candidate",preview.input_scheduler.submit(valid).is_empty())
	deadline=Time.get_ticks_msec()+30000
	while preview.held_shape_receipts.is_empty() and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline: await process_frame
	_check("receipt_held_for_visibility_probe",not preview.held_shape_receipts.is_empty())
	if preview.held_shape_receipts.is_empty(): _finish(); quit(1); return
	var held := await snapshot("held")
	_check("not_published_before_cpu_settlement",held.published_sand==unchanged.published_sand and held.sand!=unchanged.sand and preview.shadow_domain.sand_source_m3==0.0 and preview.solver.publication_pending)
	direct_result=null; RenderingServer.call_on_render_thread(render_locked)
	while direct_result==null: await process_frame
	_check("solver_tick_locked_until_authorized",direct_result==true)
	var held_packet: Dictionary=preview.held_shape_receipts[0].duplicate(true)
	preview._settle_gpu_receipt(held_packet.bytes,preview.generation-1)
	_check("old_generation_cpu_receipt_ignored",not preview.gpu_settled and preview.shadow_domain.sand_source_m3==0.0 and preview.solver.publication_pending)
	preview.release_shape_receipts()
	var source_once: float=preview.shadow_domain.sand_source_m3
	var applied_once: int=preview.command_queue.applied_log.size()
	preview._settle_gpu_receipt(held_packet.bytes,held_packet.token)
	_check("duplicate_receipt_during_publication_ignored",preview.shadow_domain.sand_source_m3==source_once and preview.command_queue.applied_log.size()==applied_once)
	await settle()
	preview._settle_gpu_receipt(held_packet.bytes,held_packet.token)
	_check("late_duplicate_receipt_ignored",preview.shadow_domain.sand_source_m3==source_once and preview.command_queue.applied_log.size()==applied_once and preview.last_error.is_empty())
	var applied := await snapshot("applied")
	result=preview.input_scheduler.terminal[-1].result
	_check("one_revision_and_source",result.get("status")==1 and preview.solver.state_revision==1 and preview.shadow_domain.sand_source_m3==result.added_m3 and preview.shadow_domain.sand_sink_m3==0.0 and preview.shadow_domain.tool_inventory_m3==0.0,result)
	_check("published_matches_committed",applied.published_sand==applied.sand)
	_check("only_sand_and_private_coverage_changed",exact(unchanged,applied,["sand","spare_sand","published_sand","coverage"]))
	var a: PackedFloat32Array=unchanged.sand.to_float32_array()
	var b: PackedFloat32Array=applied.sand.to_float32_array()
	var volume := 0.0
	for i in a.size(): volume+=(b[i]-a[i])*0.015625
	_check("raw_volume_matches_receipt",absf(volume-result.added_m3)<=result.eps_sand_m3,{"raw_delta":volume,"receipt":result.added_m3,"eps":result.eps_sand_m3})
	var collision_ok := true
	for chunk in preview.collision_needed: collision_ok=collision_ok and preview.collision_proxy.applied_revisions.get(chunk,-1)>=preview.collision_needed[chunk]
	_check("collision_revision_acknowledged",collision_ok and not preview.collision_needed.is_empty())
	result=await submit(command(Vector2.ZERO,Vector2(0.125,0)))
	_check("same_stroke_target_is_idempotent",result.get("status")==2 and preview.solver.state_revision==1)
	var repeated := await snapshot("repeated")
	_check("repeat_exact",exact(applied,repeated))
	preview.shape_gpu.inject_candidate_failure_once=true
	result=await submit(command(Vector2(1,0),Vector2(1.125,0)))
	_check("candidate_rejected",result.get("status")==3 and result.get("error_code")==16,result)
	var failed := await snapshot("candidate_rejected")
	_check("candidate_rejection_keeps_both_slots_and_history",exact(repeated,failed) and preview.solver.state_revision==1)
	result=await submit(command(Vector2(1,0),Vector2(1.125,0),true))
	_check("finite_budget_rejected",result.get("status")==3 and result.get("error_code")==9,result)
	var budget := await snapshot("budget_rejected")
	_check("budget_rejection_exact",exact(failed,budget))
	var stale := command(Vector2(2,0),Vector2(2.125,0))
	direct_result=null; RenderingServer.call_on_render_thread(render_old_epoch.bind(BrushProtocol.encode(stale,999,preview.solver.state_revision)))
	while direct_result==null: await process_frame
	_check("old_epoch_rejected_before_gpu_writes",direct_result==true)
	var old := await snapshot("old_epoch")
	_check("old_epoch_exact",exact(budget,old))
	_check("save_during_stroke_refused",await preview.save_gpu_checkpoint(output.path_join("unexpected.bin"))==&"brush_stroke_active")
	var end_error: StringName=await preview.end_shape_stroke()
	_check("logical_baseline_released",end_error.is_empty() and not preview.shape_gpu.active and preview.shape_gpu.baseline_token==0)
	begin_error=await preview.begin_shape_stroke(72)
	_check("next_stroke_reuses_bounded_pool",begin_error.is_empty() and preview.shape_gpu.owned.size()==count and preview.shape_gpu.baseline_copy_count==2)
	await preview.end_shape_stroke()
	var evidence := FileAccess.open(output.path_join("gpu_framework_evidence.json"),FileAccess.WRITE)
	evidence.store_string(JSON.stringify({"raw_index":raw_index,"statistics":preview.shape_gpu.statistics(),"prefix":preview.gpu_prefix,"events":preview.gpu_events,"source_signature":preview.source_signature,"adapter":RenderingServer.get_video_adapter_name(),"vsync":DisplayServer.window_get_vsync_mode(),"viewport":root.size,"scope":"dry GPU lifecycle and bounded wall candidate; complete geometry and wet integration are later gates"},"\t")); evidence.close()
	root.get_texture().get_image().save_png(output.path_join("bounded_candidate.png"))
	await preview.shutdown(); _check("all_brush_resources_released",preview.gpu_release_done and preview.shape_gpu==null)
	_finish(); var passed := true
	for row in checks: passed=passed and row.pass
	quit(0 if passed else 1)
