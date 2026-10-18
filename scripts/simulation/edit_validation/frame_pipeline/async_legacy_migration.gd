extends RefCounted

const Store=preload("res://scripts/simulation/checkpoint_store.gd")
const Recovery=preload("res://scripts/beach/beach_recovery_entry.gd")
const Snapshot=preload("res://scripts/simulation/edit_validation/frame_pipeline/async_checkpoint_codec.gd")

static func legacy_configuration(current: Dictionary) -> Dictionary:
	var result:=current.duplicate(true)
	result.async_pipeline_enabled=false
	result.erase("pipeline_protocol")
	result.erase("ledger_precision")
	return result

static func convert(owner, original: Dictionary) -> Dictionary:
	# This is a decoder/explicit projection of a real old snapshot, never a
	# producer of synthetic v4 receipts for the approximate pipeline.
	var old:=original.duplicate(true)
	if not old.get("gpu_beach_edit") is Dictionary or old.gpu_beach_edit.get("version")!=4 or not old.get("gpu_beach_native") is Dictionary or old.gpu_beach_native.get("version")!=2:return {"error":&"unsupported_legacy_pipeline_version"}
	var error:=Store._validate({"format_version":Store.FORMAT_VERSION,"enable_erosion":owner.enable_erosion,"checkpoint":old,"prefix_commands":[]})
	if not error.is_empty():return {"error":error}
	error=Recovery.validate_gpu_checkpoint(old,legacy_configuration(owner.source_signature))
	if not error.is_empty():return {"error":error}
	if String(old.shadow.domain_id)!=String(owner._domain_id()):return {"error":&"pipeline_domain_mismatch"}
	if old.get("enable_structures",false) or not old.get("structures",{}).is_empty() or not old.get("support_loss_events",[]).is_empty():return {"error":&"unsupported_legacy_pipeline_history"}
	if not old.get("visual_extensions") is Dictionary or not old.visual_extensions.has("gravel_v1"):return {"error":&"missing_legacy_gravel_state"}
	error=owner._validate_gravel(old)
	if not error.is_empty():return {"error":error}
	var native: Dictionary=old.gpu_beach_native
	var simulation: Dictionary=owner._async_snapshot_simulation_configuration()
	if simulation.enable_structures or simulation.rise_front_history or simulation.contact_history:return {"error":&"unsupported_legacy_pipeline_history"}
	var histories:={}
	if simulation.local_front_history:
		if not old.get("local_front_history") is PackedFloat32Array:return {"error":&"missing_legacy_local_front"}
		histories.local_front=old.local_front_history.to_byte_array()
	# Under the exact supported old source/profile, every completed water tick
	# called dispatch_wave_boundary; initial state alone has no prescribed edge.
	simulation.prescribed_tide_boundary=old.tick>0
	var actual_time: float=PackedFloat32Array([float(old.tick)*owner.SIM_DELTA])[0]
	var control:=PackedByteArray();control.resize(128)
	control.encode_u32(0,1);control.encode_u64(8,old.shadow.generation)
	control.encode_u64(24,old.tick);control.encode_float(32,actual_time);control.encode_u64(40,old.revision)
	# New state_seq and pipeline success/skip diagnostics start at zero; old
	# receipts have been validated, but are not reinterpreted as GPU completions.
	var ticket:=0
	for row in old.gpu_beach_edit.prefix:ticket=maxi(ticket,int(row.result.get("ticket_id",0)))
	var clocks:={}
	for wave in old.wave_requests:clocks[wave.request_id]=(float(wave.start_tick)-1.5)*owner.SIM_DELTA
	var initial_total: float=old.gpu_beach_edit.ledger.tool_inventory_m3-old.gpu_beach_edit.ledger.sand_source_m3+old.gpu_beach_edit.ledger.sand_sink_m3
	for field in ["sand","sediment"]:
		for amount in native.fields[field].to_float32_array():initial_total+=float(amount)*0.015625
	var checkpoint:={"version":5,"pipeline_protocol_version":1,"grid_size":256,"cell_size_m":0.125,"domain_id":String(old.shadow.domain_id),"generation":old.shadow.generation,"state_seq":0,"sim_tick":old.tick,"revision":old.revision,"advanced_time_s":actual_time,"highwater_id":old.highwater_id,"ticket_id":ticket,"configuration":owner.source_signature.duplicate(true),"simulation":simulation,"ledger_precision":"approximate","ledger":old.gpu_beach_edit.ledger.duplicate(true),"initial_sand_total_m3":initial_total,"nominal_upper_supply":0.0,"selection":{"policy":old.gpu_beach_edit.selection.policy,"speed":old.gpu_beach_edit.selection.speed},"cohesion_yield_height_m":old.sand_cohesion_yield_height_m,"wave_requests":old.wave_requests.duplicate(true),"wave_highwater_id":old.wave_highwater_id,"wave_start_times":clocks,"native":{"version":3,"current_index":0,"fields":native.fields.duplicate(true),"spare":native.spare.duplicate(true),"material":native.material.duplicate(true),"foam":native.foam.duplicate(true),"histories":histories,"control":control},"visual_extensions":old.visual_extensions.duplicate(true)}
	checkpoint.selection.brush=old.gpu_beach_edit.selection.brush.duplicate(true)
	error=Snapshot.validate(checkpoint,owner.source_signature)
	if not error.is_empty():return {"error":error}
	return {"error":&"","checkpoint":checkpoint,"brush_selection":old.gpu_beach_edit.selection.brush.duplicate(true),"provenance":{"edit_version":4,"native_version":2,"validated_prefix_count":old.gpu_beach_edit.prefix.size(),"state_seq_policy":"new_pipeline_zero","clock_policy":"old_tick_over_30_f32","initial_total_policy":"native_total_minus_old_sources_plus_sinks"}}
