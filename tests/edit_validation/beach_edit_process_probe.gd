extends "res://tests/edit_validation/beach_history_process_probe.gd"

const Recovery=preload("res://tests/edit_validation/beach_recovery_entry.gd")
var spare_data := {}
var material_trace_armed := false
var slope_record_bytes := PackedByteArray()

func _read_slope_record() -> void:
	preview.solver.rd.buffer_get_data_async(preview.material_coupler.record_buffer,_slope_record_callback)

func _slope_record_callback(bytes: PackedByteArray) -> void: call_deferred("_slope_record_ready",bytes)
func _slope_record_ready(bytes: PackedByteArray) -> void: slope_record_bytes=bytes

func _collect_slope_records(offset: int) -> void:
	slope_record_bytes.clear();RenderingServer.call_on_render_thread(_read_slope_record)
	while slope_record_bytes.is_empty(): await process_frame
	var file:=FileAccess.open(output.path_join("slope_record_raw.bin"),FileAccess.WRITE);file.store_buffer(slope_record_bytes);file.close()
	var metadata: Array=preview.material_coupler.record_metadata.slice(offset)
	var counter_only: bool="--beach-slope-counter" in OS.get_cmdline_user_args()
	var output_only: bool="--beach-slope-output" in OS.get_cmdline_user_args()
	var normalized:=PackedByteArray();var valid: bool=slope_record_bytes.size()==16+4*128*128 and not metadata.is_empty()
	for slot in 4:
		var count: int=slope_record_bytes.decode_u32(slot*4)
		valid=valid and count==preview.material_coupler.record_metadata.size() and count<=128
		for sample in range(offset,mini(count,128)):
			var base: int=16+(slot*128+sample)*128
			var record: PackedByteArray=slope_record_bytes.slice(base,base+128)
			record.encode_u32(7*4,sample-offset);normalized.append_array(record)
	file=FileAccess.open(output.path_join("slope_record_continued.bin"),FileAccess.WRITE);file.store_buffer(normalized);file.close()
	var meta:=var_to_bytes({"metadata":metadata,"spirv_sha256":preview.material_coupler.record_spirv_sha256,"counter_only":counter_only,"output_only":output_only})
	file=FileAccess.open(output.path_join("slope_record_metadata.bin"),FileAccess.WRITE);file.store_buffer(meta);file.close()
	rows.append({"case":"slope_shader_late_record_pair","pass":valid and (mode=="write" or (normalized==FileAccess.get_file_as_bytes(source.path_join("slope_record_continued.bin")) and meta==FileAccess.get_file_as_bytes(source.path_join("slope_record_metadata.bin")))),"records_per_cell":metadata.size(),"writer_offset":offset,"counter_only":counter_only,"diagnostic_shader_changed":true,"additional_tick_record_readbacks":false})

func _arm_material_trace() -> void:
	preview.material_coupler.observe_enabled=true
	call_deferred("_material_trace_arm_done")

func _material_trace_arm_done() -> void:
	material_trace_armed=true


func _read_spare() -> void:
	for field in ["sand","water","momentum_x","momentum_z","sediment","wetness","compaction","flux"]:
		preview.solver.rd.texture_get_data_async(preview.solver.textures[field][1-preview.solver.current_index],0,_spare_callback.bind(field))

func _spare_callback(bytes: PackedByteArray, field: String) -> void: call_deferred("_spare_record",bytes,field)
func _spare_record(bytes: PackedByteArray, field: String) -> void: spare_data[field]=bytes

func _compare_spare(prefix: String) -> bool:
	spare_data.clear();RenderingServer.call_on_render_thread(_read_spare)
	while spare_data.size()<8: await process_frame
	var exact:=true
	for field in spare_data:
		var name: String=prefix+"_spare_"+String(field)+".bin"
		var file:=FileAccess.open(output.path_join(name),FileAccess.WRITE);file.store_buffer(spare_data[field]);file.close()
		if mode=="read": exact=exact and spare_data[field]==FileAccess.get_file_as_bytes(source.path_join(name))
	return exact

func _write(ok: bool, error: String="") -> void:
	var file:=FileAccess.open(output.path_join("beach_edit_process_probe.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":ok,"rows":rows,"error":error,"mode":mode,"source":source,"scope":"full beach actual GPU edits, cold independent native checkpoint restore and continuation"},"\t"))

func _ledger() -> Dictionary:
	var values:= {}
	for key in ["tool_inventory_m3","sand_source_m3","sand_sink_m3"]: values[key]=preview.shadow_domain.get(key)
	values.water_source_m3=preview.solver.water_source_m3;values.water_sink_m3=preview.solver.water_sink_m3
	return values

func _compare_metadata(prefix: String) -> bool:
	var bytes:=var_to_bytes({"ledger":_ledger(),"prefix":preview.gpu_prefix,"highwater":preview.command_queue.last_command_id,"selection":{"policy":preview.water_policy,"speed":preview.signed_speed_m_s}})
	var file:=FileAccess.open(output.path_join(prefix+"_metadata.bin"),FileAccess.WRITE);file.store_buffer(bytes);file.close()
	return mode=="write" or bytes==FileAccess.get_file_as_bytes(source.path_join(prefix+"_metadata.bin"))

func _run() -> void:
	root.size=Vector2i(1920,1080);DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var mixed_cpu: bool="--beach-mixed-cpu" in OS.get_cmdline_user_args()
	var prefix_count: int=4 if mixed_cpu else 2
	preview=load("res://tests/edit_validation/edit_beach_recovery_lab.tscn").instantiate();preview.playing=false;preview.capture_substep_trace=true;preview.observe_coupled_parameters=not "--beach-no-parameter-trace" in OS.get_cmdline_user_args()
	preview.defer_shader_identity="--beach-late-shader-identity" in OS.get_cmdline_user_args()
	if mode=="read":
		var loaded:=Store.load(source.path_join("full_beach_edit.scp"))
		if not loaded.error.is_empty(): _write(false,String(loaded.error));finished=true;quit(1);return
		var signature:=Recovery.configuration_signature()
		var error:=Recovery.validate_gpu_checkpoint(loaded.checkpoint,signature)
		if not error.is_empty(): _write(false,String(error));finished=true;quit(1);return
		for mutation in ["configuration","ledger","identity","pending","selection"]:
			var bad: Dictionary=loaded.checkpoint.duplicate(true)
			match mutation:
				"configuration": bad.gpu_beach_edit.configuration.profile_sha256="0".repeat(64)
				"ledger": bad.gpu_beach_edit.ledger.tool_inventory_m3+=0.01
				"identity": bad.gpu_beach_edit.prefix[0].command.command_id=1
				"pending": bad.gpu_beach_edit.pending_count=1
				"selection": bad.gpu_beach_edit.selection.speed=NAN
			rows.append({"case":"cold_preflight_"+mutation,"pass":not Recovery.validate_gpu_checkpoint(bad,signature).is_empty()})
		preview.replay_checkpoint=loaded.checkpoint;preview.replay_prefix_commands.clear();preview.replay_target_tick=loaded.checkpoint.tick
	root.add_child(preview)
	while not preview.ready_for_ticks and preview.last_error.is_empty(): await process_frame
	if not preview.last_error.is_empty(): _write(false,preview.last_error);finished=true;quit(1);return
	if mode=="read":
		while not preview.replay_ready and preview.last_error.is_empty(): await process_frame
		preview.replay_target_tick=-1
	else:
		await _ticks(15)
		for i in 2:
			preview.water_policy=3 if i==0 else 1;preview.signed_speed_m_s=0.25 if i==0 else 0.0
			var command: Dictionary={"domain_id":preview.shadow_domain.domain_id,"generation":preview.generation,"sim_tick":preview.completed_ticks,"command_id":9007199254741103+i,"kind":&"remove_sand" if i==0 else &"place_sand","shape":&"circle","transform":{"position_m":Vector3(-14.8125,0,-14.8125)},"radius_m":0.75,"strength":1.0,"amount_m3":0.01 if i==0 else 0.005,"seed":101}
			var result: Dictionary=await preview.apply_gpu_command(command)
			rows.append({"case":"writer_real_gpu_edit_%d" % i,"pass":result.get("status")==1,"receipt":result})
		if mixed_cpu:
			for i in 2:
				var command: Dictionary={"domain_id":preview.shadow_domain.domain_id,"generation":preview.generation,"sim_tick":preview.completed_ticks,"command_id":9007199254741105+i,"kind":&"compact" if i==0 else &"smooth","shape":&"circle","transform":{"position_m":Vector3(-14.8125,0,-14.8125)},"radius_m":0.75,"strength":0.6,"seed":101}
				var result: Dictionary=await preview.apply_legacy_command(command)
				rows.append({"case":"writer_legacy_cpu_%d"%i,"pass":result.get("results",[]).size()==1 and result.results[0].status==&"applied","result":result})
		await _ticks(2)
		preview.water_policy=3;preview.signed_speed_m_s=0.4
		var saved: StringName=await preview.save_gpu_checkpoint(output.path_join("full_beach_edit.scp"))
		rows.append({"case":"writer_complete_native_prefix_save","pass":saved==&"" and preview.gpu_prefix.size()==prefix_count,"error":String(saved)})
	var first: bool=await _snapshot("checkpoint")
	var saved_revision: int=preview.solver.state_revision
	var metadata_exact: bool=_compare_metadata("checkpoint")
	var observe: bool="--beach-step-readbacks" in OS.get_cmdline_user_args()
	var spare_exact: bool=await _compare_spare("checkpoint") if observe else true
	rows.append({"case":"full_edited_checkpoint_state_pixels_ledger_prefix","pass":first and metadata_exact and spare_exact and preview.command_queue.last_command_id==9007199254741102+prefix_count and preview.gpu_prefix.size()==prefix_count,"tick":preview.completed_ticks,"generation":preview.generation,"mixed_cpu":mixed_cpu,"spare_exact":spare_exact if observe else null,"index":preview.solver.current_index,"cohesion":preview.material_coupler.cohesion_yield_height_m})
	if "--beach-material-trace-continuation-only" in OS.get_cmdline_user_args():
		RenderingServer.call_on_render_thread(_arm_material_trace)
		while not material_trace_armed: await process_frame
	var slope_offset: int=preview.material_coupler.record_metadata.size() if "--beach-slope-record" in OS.get_cmdline_user_args() else 0
	for tick in 7:
		await _ticks(1)
		if observe:
			var step: bool=await _snapshot("step_%d" % preview.completed_ticks)
			rows.append({"case":"continued_step_%d" % preview.completed_ticks,"pass":step,"index":preview.solver.current_index,"substeps":preview.last_substeps})
	var continued: bool=await _snapshot("continued")
	if "--beach-slope-record" in OS.get_cmdline_user_args(): await _collect_slope_records(slope_offset)
	metadata_exact=_compare_metadata("continued")
	rows.append({"case":"full_edited_seven_tick_continuation","pass":continued and metadata_exact and preview.completed_ticks==24,"tick":preview.completed_ticks,"metadata_exact":metadata_exact,"cohesion":preview.material_coupler.cohesion_yield_height_m})
	var parameters:=[]
	if preview.defer_shader_identity: preview.collect_compiled_shader_identity()
	for item in preview.coupled_parameter_trace:
		if item.tick>=17: parameters.append(item)
	var staged_identity: Array=preview.material_coupler.staged_shader_hashes if "--beach-staged-slope" in OS.get_cmdline_user_args() else []
	var bytes:=var_to_bytes({"parameters":parameters,"spirv":preview.compiled_shader_identity,"staged_shader_sha256":staged_identity})
	var file:=FileAccess.open(output.path_join("coupled_parameters.bin"),FileAccess.WRITE);file.store_buffer(bytes);file.close()
	rows.append({"case":"actual_coupled_parameters_and_spirv_match","pass":mode=="write" or bytes==FileAccess.get_file_as_bytes(source.path_join("coupled_parameters.bin")),"parameter_trace_enabled":preview.observe_coupled_parameters,"parameters":parameters,"spirv":preview.compiled_shader_identity})
	if "--beach-push-trace" in OS.get_cmdline_user_args():
		var pushes:=[]
		for item in preview.material_coupler.push_trace:
			if item.revision>saved_revision: pushes.append(item)
		bytes=var_to_bytes(pushes)
		file=FileAccess.open(output.path_join("material_push_bytes.bin"),FileAccess.WRITE);file.store_buffer(bytes);file.close()
		rows.append({"case":"actual_material_push_bytes_match","pass":pushes.size()==28 and (mode=="write" or bytes==FileAccess.get_file_as_bytes(source.path_join("material_push_bytes.bin"))),"pushes":pushes})
	if "--beach-material-stage-trace" in OS.get_cmdline_user_args():
		var stages: Dictionary=await preview.collect_material_trace()
		var stage_exact := true
		for key in stages.data:
			var stage_name: String="material_"+String(key)+".bin"
			file=FileAccess.open(output.path_join(stage_name),FileAccess.WRITE);file.store_buffer(stages.data[key]);file.close()
			if mode=="read": stage_exact=stage_exact and stages.data[key]==FileAccess.get_file_as_bytes(source.path_join(stage_name))
		file=FileAccess.open(output.path_join("material_stage_metadata.json"),FileAccess.WRITE);file.store_string(JSON.stringify(stages.metadata,"\t"));file.close()
		rows.append({"case":"ordinary_continuation_material_stages","pass":stage_exact and stages.data.size()>0,"records":stages.data.size(),"substeps":stages.metadata.size(),"diagnostic_submission_changed":true})
	var ok: bool=preview.last_error.is_empty()
	for row in rows: ok=ok and row.pass
	_write(ok,preview.last_error);await preview.shutdown();preview.queue_free();for i in 8: await process_frame
	finished=true;print("BEACH_EDIT_PROCESS_COMPLETE mode=%s pass=%s" % [mode,str(ok)]);quit(0 if ok else 1)
