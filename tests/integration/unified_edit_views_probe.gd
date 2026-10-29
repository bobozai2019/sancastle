extends "res://tests/integration/unified_edit_height_probe.gd"

var viewport_probe
var preview_done:=false
var preview_value: Dictionary={}
var query_rows: Array=[]

class DisposableReceiver extends Node:
	func accept_preview(_value: Dictionary) -> void:pass

func _configure_domain() -> void:
	super._configure_domain()
	domain.wetness[0]=pow(2.0,-24);domain.compaction[1]=pow(2.0,-24)
	var momentum:=PackedFloat32Array();momentum.resize(65536);momentum[2]=-0.0
	domain.set_meta("edit_validation_initial_qx",momentum)

func _additional_sources() -> PackedStringArray:
	var paths:=super._additional_sources()
	paths.append_array(PackedStringArray(["res://tests/integration/unified_edit_height_probe.gd","res://tests/fixtures/unified_edit/view_consumer.tscn","res://tests/fixtures/unified_edit/view_consumer.gdshader"]))
	return paths

func _extra_image_fields() -> Dictionary:
	var images:=super._extra_image_fields()
	for field in pipeline.views.textures:images["view_"+String(field)]=pipeline.views.textures[field]
	return images

func _extra_buffer_fields() -> Dictionary:
	var fields:=super._extra_buffer_fields()
	fields.view_stroke=[pipeline.views.buffers.stroke,64];fields.view_result=[pipeline.views.buffers.result,96]
	return fields

func _preview_received(value: Dictionary) -> void:preview_value=value.duplicate(true);preview_done=true

func _wait_preview() -> void:
	var deadline:=Time.get_ticks_msec()+10000
	while not preview_done and Time.get_ticks_msec()<deadline:await process_frame
	check("preview_returned_"+str(checks.size()),preview_done)

func _save_query(label: String, request: Dictionary, expected: StringName=&"") -> void:
	check("preview_result_"+label,preview_value.get("error",&"missing")==expected)
	var row:={"label":label,"request":request.duplicate(true),"result":preview_value.duplicate(true)}
	var frozen:=preload("res://scripts/simulation/unified_edit/intent.gd").freeze(registry,request,"main_beach",pipeline._generation)
	row.wire=Wire.decode_command(Wire.encode_command(frozen.value,registry)).value
	if preview_value.has("raw"):
		var path: String=output.get_base_dir()+"/preview_"+label+".bin"
		FileAccess.open(path,FileAccess.WRITE).store_buffer(preview_value.raw)
		row.result.erase("raw");row.raw={"path":path,"bytes":preview_value.raw.size(),"sha256":FileAccess.get_sha256(path)}
	query_rows.append(row)

func query(label: String, request: Dictionary, minimum: int=0, expected: StringName=&"") -> void:
	preview_done=false
	check("preview_admitted_"+label,pipeline.views.request_preview(request,_preview_received,minimum).accepted)
	await _wait_preview();_save_query(label,request,expected)

func render_observation(label: String) -> Dictionary:
	await RenderingServer.frame_post_draw;await RenderingServer.frame_post_draw
	var image: Image=viewport_probe.get_texture().get_image()
	var pixels:=[]
	for x in [8,24,40]:
		var color:=image.get_pixel(x,8);pixels.append([color.r,color.g,color.b,color.a])
	var path: String=output.get_base_dir()+"/render_"+label+".png";check("render_capture_"+label,image.save_png(path)==OK)
	return {"path":path,"sha256":FileAccess.get_sha256(path),"pixels":pixels,"format":image.get_format(),"width":image.get_width(),"height":image.get_height()}

func _next_fill() -> Dictionary:
	serial=maxi(serial,pipeline._highwater)+1
	var command:=request(serial,&"fill_v1",Vector2(8.0625,0.0625),0.01);command.parameters.radius_m=0.01;return command

func _native_half_render(fields: Dictionary) -> void:
	for pair in [["wetness0","wetness",0],["compact0","compaction",2]]:
		var bytes:=FileAccess.get_file_as_bytes(fields[pair[0]].path);bytes.encode_u16(pair[2],1)
		var texture: RID=pipeline.state._create_texture(RenderingDevice.DATA_FORMAT_R16_SFLOAT,bytes)
		for target in pipeline.state.textures[pair[1]]:pipeline.transport.rd.texture_copy(texture,target,Vector3.ZERO,Vector3.ZERO,Vector3(256,256,1),0,0,0,0)
	call_deferred("_snapshot_armed")

func _consumer_extension() -> void:
	viewport_probe=load("res://tests/fixtures/unified_edit/view_consumer.tscn").instantiate();root.add_child(viewport_probe)
	var parameters:={"sand_state":"sand","water_state":"water","compaction_state":"compaction","wetness_state":"wetness","sediment_state":"sediment","qx_state":"momentum_x","rock_state":"rock","stroke_baseline":"baseline","async_clock":"clock"}
	for name in ["Bed","Water","Preview"]:check("bind_material_"+name,pipeline.views.bind_material(viewport_probe.get_node(name).material,parameters).is_empty())
	check("unknown_view_field_rejected",pipeline.views.bind_material(viewport_probe.get_node("Bed").material,{"sand_state":"not_a_field"})==&"unknown_view_field")
	check("unknown_view_parameter_rejected",pipeline.views.bind_material(viewport_probe.get_node("Bed").material,{"not_a_parameter":"sand"})==&"unknown_view_parameter")
	check("bound_views_keep_resource_lease",not pipeline.views.can_release())
	var codec:=PackedByteArray();codec.resize(2);codec.encode_half(0,pow(2.0,-24))
	var native_before:=await snapshot("native_half_before")
	armed_snapshot=false;RenderingServer.call_on_render_thread(_native_half_render.bind(native_before))
	while not armed_snapshot:await process_frame
	var refresh:=_next_fill();refresh.parameters.strength=0.0
	expect("view_native_refresh",await perform("view_native_refresh",refresh),L.Outcome.NO_CHANGE)
	observations.half_initialization={"requested_value":pow(2.0,-24),"godot_encode_half_bits":codec.decode_u16(0),"native_fixture_bits":1,"before":native_before}
	var initial:={"physical":await snapshot("views_initial"),"render":await render_observation("initial")}
	check("native_half_subnormal_inputs_present",FileAccess.get_file_as_bytes(initial.physical.wetness0.path).decode_u16(0)==1 and FileAccess.get_file_as_bytes(initial.physical.compact0.path).decode_u16(2)==1)
	check("native_signed_zero_input_present",FileAccess.get_file_as_bytes(initial.physical.qx0.path).decode_u32(8)==0x80000000)
	var highwater:=pipeline._highwater;var reservations:=pipeline.result_reservations();var seq:=pipeline.completed_state_seq
	var disk:=request(1,&"fill_v1",Vector2(8.0625,0.0625),0.01);disk.parameters.radius_m=0.01
	await query("disk",disk)
	await query("capsule",request(1,&"fill_sweep_v1",Vector2(-3,1)))
	await query("stamp",shape_request(&"castle_v1",Vector2(-5,0),Vector2(-5,0),1,{"height_m":0.5,"scale_xz":1.2,"yaw_rad":0.4}))
	check("preview_does_not_admit_or_advance",pipeline._highwater==highwater and pipeline.result_reservations()==reservations and pipeline.completed_state_seq==seq)
	var after_pure_highwater:=pipeline._highwater;var after_pure_reservations:=pipeline.result_reservations()
	var after_queries:=await snapshot("views_after_queries")
	var wrong_generation:=disk.duplicate(true);wrong_generation.generation+=1
	check("foreign_generation_preview_rejected",not pipeline.views.request_preview(wrong_generation,_preview_received).accepted)
	var cpu_before:=pipeline.completed_state_seq
	var ahead_fill:=_next_fill();ahead_fill.start_xz_m=Vector2(9.0625,0.0625)
	pipeline.hold_completions=true
	check("gpu_ahead_work_admitted",pipeline.submit_intent(ahead_fill).accepted);pipeline.pump()
	var ahead_deadline:=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<ahead_deadline:
		var ready:=false
		for index in L.WORK_SLOTS:ready=ready or pipeline.slots.slot_snapshot(index).state==Pipeline.Slots.State.GPU_COMPLETE
		if ready:break
		await process_frame
	var ahead_request:=disk.duplicate(true);ahead_request.start_xz_m=Vector2(9.0625,0.0625)
	await query("gpu_ahead",ahead_request,cpu_before)
	check("preview_reports_gpu_version_not_cpu_guess",pipeline.completed_state_seq==cpu_before and preview_value.state_seq==cpu_before+1 and pipeline.result(ahead_fill.command_id).is_empty())
	observations.gpu_ahead_view={"physical":await snapshot("gpu_ahead_view"),"cpu_state_seq":pipeline.completed_state_seq,"query_state_seq":preview_value.state_seq}
	pipeline.hold_completions=false;await await_idle()
	check("gpu_ahead_cache_survives_matching_completion",not pipeline.views.last_preview.is_empty() and pipeline.views.last_preview.state_seq==pipeline.completed_state_seq)
	serial=pipeline._highwater
	expect("view_begin",await perform("view_begin",control_identity(),"begin"),L.Outcome.NO_CHANGE)
	var wall:=shape_request(&"wall_v1",Vector2(8.0625,0.0625),Vector2(9,0.0625),1)
	await query("wall_baseline",wall)
	check("preview_uses_published_baseline",preview_value.uses_baseline)
	await query("stamp_during_stroke",shape_request(&"castle_v1",Vector2(-5,0),Vector2(-5,0),1,{"height_m":0.5,"scale_xz":1.2,"yaw_rad":0.4}))
	check("fixed_world_does_not_claim_baseline",not preview_value.uses_baseline)
	pipeline.views.hold_delivery=true;preview_done=false
	check("held_preview_admitted",pipeline.views.request_preview(disk,_preview_received).accepted)
	var deadline:=Time.get_ticks_msec()+10000
	while pipeline.views.held.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check("preview_busy_backpressure",not pipeline.views.request_preview(disk,_preview_received).accepted)
	expect("view_fill",await perform("view_fill",_next_fill()),L.Outcome.APPLIED)
	pipeline.views.invalidate_preview();pipeline.views.deliver_held();await _wait_preview();_save_query("superseded",disk,&"preview_superseded")
	check("superseded_not_cached",pipeline.views.last_preview.is_empty())
	await query("latest",disk,pipeline.completed_state_seq)
	await query("future_minimum",disk,pipeline.completed_state_seq+1,&"stale_preview_version")
	pipeline.views.inject_readback_failure_once=true;preview_done=false
	var unknown_version:=pipeline.completed_state_seq
	check("preview_unknown_admitted",pipeline.views.request_preview(disk,_preview_received).accepted)
	deadline=Time.get_ticks_msec()+10000
	while not pipeline.views._query.get("unknown",false) and Time.get_ticks_msec()<deadline:await process_frame
	check("preview_unknown_retains_resources",pipeline.views.pending and not pipeline.views.can_release())
	serial=maxi(serial,pipeline._highwater)+1
	var compact:=request(serial,&"compact_v1",Vector2(8.0625,0.0625));compact.parameters={"strength":0.3,"radius_m":0.5}
	expect("view_compact",await perform("view_compact",compact),L.Outcome.APPLIED)
	pipeline.views.retry_preview_readback();await _wait_preview();_save_query("unknown_old_output",disk,&"stale_preview_version")
	check("preview_retry_did_not_recapture",preview_value.state_seq==unknown_version)
	await query("newest",disk,pipeline.completed_state_seq)
	check("actual_tick_admitted",pipeline.request_tick(0.001).is_empty());await await_idle();await settle_heights()
	await query("after_tick",disk,pipeline.completed_state_seq)
	var receiver:=DisposableReceiver.new()
	pipeline.views.hold_delivery=true
	check("orphan_query_admitted",pipeline.views.request_preview(disk,receiver.accept_preview).accepted)
	deadline=Time.get_ticks_msec()+10000
	while pipeline.views.held.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check("orphan_retains_pending_until_delivery",pipeline.views.pending)
	receiver.free();pipeline.views.deliver_held()
	check("orphan_callback_reclaims_without_calling_dead_node",not pipeline.views.pending)
	observations.orphan_preview={"receiver_valid":is_instance_valid(receiver),"pending_after_delivery":pipeline.views.pending,"query_serial":pipeline.views.query_serial}
	var final:={"physical":await snapshot("views_final"),"surface":capture_surface("views_final"),"render":await render_observation("final")}
	if probe_case=="views_fatal":await fatal_view(disk)
	else:
		pipeline.views.hold_delivery=true;preview_done=false
		check("closing_query_admitted",pipeline.views.request_preview(disk,_preview_received).accepted)
		deadline=Time.get_ticks_msec()+10000
		while pipeline.views.held.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
		pipeline.views.inject_detach_failure_once=true
		check("detach_unknown_retains_resources",not await pipeline.views.detach_bindings() and not pipeline.views.can_release())
		check("detach_retry_real_fence",await pipeline.views.detach_bindings())
		check("pending_preview_still_prevents_release",not pipeline.views.can_release())
		pipeline.views.deliver_held();await _wait_preview();_save_query("closing",disk,&"view_closed")
	if not pipeline.views.detached_confirmed:check("material_detach",await pipeline.views.detach_bindings())
	check("all_view_consumers_released",pipeline.views.can_release())
	for name in ["Bed","Water","Preview"]:check("original_material_restored_"+name,viewport_probe.get_node(name).material.get_shader_parameter("sand_state")==null)
	observations.views={"initial":initial,"after_queries":after_queries,"final":final,"queries":query_rows,"bound_materials":3,"before_preview_highwater":highwater,"after_pure_preview_highwater":after_pure_highwater,"before_preview_reservations":reservations,"after_pure_preview_reservations":after_pure_reservations,"actual_gpu_generation":pipeline._generation}
	viewport_probe.queue_free();await process_frame

func fatal_view(disk: Dictionary) -> void:
	pipeline.heights.close()
	armed_snapshot=false;RenderingServer.call_on_render_thread(_near_revision_end_render)
	while not armed_snapshot:await process_frame
	var before:=await snapshot("view_fatal_before")
	for offset in 3:
		var command:=_next_fill();command.start_xz_m=Vector2((float([192,64,80][offset])+0.5-128.0)*0.125,0.0625)
		check("view_fatal_admit_"+str(offset),pipeline.submit_intent(command).accepted)
	pipeline.pump()
	var deadline:=Time.get_ticks_msec()+10000
	while pipeline.fault_reason().is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check("view_midbatch_fatal",not pipeline.fault_reason().is_empty())
	var after:=await snapshot("view_fatal_after")
	await query("fatal_last_complete",disk)
	observations.view_fatal={"before":before,"after":after,"render":await render_observation("fatal"),"fault":String(pipeline.fault_reason())}
	pipeline.cleanup_fault()
	deadline=Time.get_ticks_msec()+10000
	while pipeline.active_count()>0 and Time.get_ticks_msec()<deadline:await process_frame
	check("view_fatal_real_terminal",pipeline.active_count()==0)
