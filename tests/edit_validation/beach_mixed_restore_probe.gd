extends "res://tests/edit_validation/beach_gpu_probe.gd"

const Domain=preload("res://scripts/simulation/sand_water_domain.gd")
const Store=preload("res://scripts/simulation/checkpoint_store.gd")
const Recovery=preload("res://tests/edit_validation/beach_recovery_entry.gd")
const Protocol=preload("res://scripts/simulation/edit_validation/edit_protocol.gd")
var history := {}

func _write() -> void:
	var file:=FileAccess.open(output.path_join("beach_mixed_restore_probe.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":not failed,"checks":checks,"prefix":preview.gpu_prefix if preview!=null else [],"scope":"full beach GPU dig + CPU compact/smooth, native checkpoint active restore; no undo/redo, no cold strict continuation or performance claim"},"\t"))

func _command(id: int, kind: StringName) -> Dictionary:
	return {"domain_id":preview.shadow_domain.domain_id,"generation":preview.generation,"sim_tick":preview.completed_ticks,"command_id":9007199254741103+id,"kind":kind,"shape":&"circle","transform":{"position_m":Vector3(-11.875,0,0.0625)},"radius_m":0.75,"strength":0.6 if kind in [&"compact",&"smooth"] else 1.0,"amount_m3":0.02,"seed":101}

func _read_history() -> void:
	for index in 2:
		preview.solver.rd.texture_get_data_async(preview.foam_field.textures[index],0,_history_callback.bind("foam_%d"%index))
		preview.solver.rd.texture_get_data_async(preview.foam_field.bed_textures[index],0,_history_callback.bind("bed_%d"%index))
	preview.local_front_field.request_data(_history_callback.bind("front"))

func _history_callback(bytes: PackedByteArray,key: String) -> void: call_deferred("_history_record",bytes,key)
func _history_record(bytes: PackedByteArray,key: String) -> void: history[key]=bytes

func _all(prefix: String) -> Dictionary:
	var state: Dictionary=await _snapshot(prefix)
	history.clear();RenderingServer.call_on_render_thread(_read_history)
	while history.size()<5: await process_frame
	for key in history:
		state[key]=history[key]
		var file:=FileAccess.open(output.path_join(prefix+"_"+key+".bin"),FileAccess.WRITE);file.store_buffer(history[key]);file.close()
	return state

func _reference(state: Dictionary):
	var domain=Domain.new(256,0.125);domain.restore(preview.shadow_domain.snapshot())
	for key in ["rock","sand","water","sediment"]: domain.set(key,state[key].to_float32_array())
	for key in ["wetness","compaction"]:
		var values:=PackedFloat32Array();values.resize(65536)
		for i in 65536: values[i]=state[key].decode_half(i*2)
		domain.set(key,values)
	return domain

func _run() -> void:
	root.size=Vector2i(1920,1080);DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	preview=load("res://tests/edit_validation/edit_beach_recovery_lab.tscn").instantiate();preview.playing=false
	root.add_child(preview)
	while not preview.ready_for_ticks and preview.last_error.is_empty(): await process_frame
	if not preview.last_error.is_empty(): _error(preview.last_error);_write();finished=true;quit(1);return
	await _ticks(15)
	preview.water_policy=0
	var gpu: Dictionary=await preview.apply_gpu_command(_command(0,&"remove_sand"))
	_check("mixed_gpu_initial_dig",gpu.get("status")==1)
	for index in 2:
		var kind: StringName=&"compact" if index==0 else &"smooth"
		var before: Dictionary=await _snapshot("before_"+String(kind))
		var reference=_reference(before)
		var command: Dictionary=_command(index+1,kind);command.erase("amount_m3")
		# Domain consumes flat coordinates; the public queue consumes transform.
		var reference_command: Dictionary=command.duplicate(true)
		reference_command.position_m=command.transform.position_m
		var expected: Dictionary=reference.apply_tool(reference_command)
		var result: Dictionary=await preview.apply_legacy_command(command)
		var after: Dictionary=await _snapshot("after_"+String(kind))
		var water_exact:=true
		for field in ["water","sediment","momentum_x","momentum_z"]: water_exact=water_exact and before[field]==after[field]
		var comp:=Image.create_from_data(256,256,false,Image.FORMAT_RF,reference.compaction.to_byte_array());comp.convert(Image.FORMAT_RH)
		var exact: bool=after.sand==reference.sand.to_byte_array() and after.compaction==comp.get_data()
		var changed: bool=before["compaction" if kind==&"compact" else "sand"]!=after["compaction" if kind==&"compact" else "sand"]
		_check("mixed_cpu_"+String(kind)+"_current_completion_oracle",result.get("results",[]).size()==1 and result.results[0].status==&"applied" and expected.status==&"applied" and exact and changed and water_exact and preview.shadow_domain.tool_inventory_m3==reference.tool_inventory_m3 and _chunks_exact(after),{"result":result,"expected_status":String(expected.status),"expected_error":String(expected.error_code),"oracle_exact":exact,"sand_exact":after.sand==reference.sand.to_byte_array(),"compaction_exact":after.compaction==comp.get_data(),"changed":changed,"water_exact":water_exact})
	var future: Dictionary=_command(3,&"compact");future.sim_tick+=1
	var highwater: int=preview.command_queue.last_command_id
	var denied: Dictionary=await preview.apply_legacy_command(future)
	_check("mixed_cpu_future_preflight",denied.get("error")=="invalid_command" and preview.command_queue.last_command_id==highwater and preview.command_queue.pending.is_empty())
	var path:=output.path_join("full_beach_mixed.scp")
	var saved: StringName=await preview.save_gpu_checkpoint(path)
	var loaded:=Store.load(path)
	var valid: StringName=Recovery.validate_gpu_checkpoint(loaded.checkpoint,Recovery.configuration_signature()) if loaded.error.is_empty() else loaded.error
	var backends:=[]
	for item in preview.gpu_prefix: backends.append(item.get("backend","gpu"))
	_check("mixed_complete_native_save_prefix",saved==&"" and valid==&"" and backends==["gpu","legacy_cpu","legacy_cpu"],{"saved":String(saved),"valid":String(valid),"backends":backends})
	var checkpoint_state: Dictionary=await _all("checkpoint")
	var checkpoint_prefix: Array=preview.gpu_prefix.duplicate(true)
	var altered: Dictionary=await preview.apply_gpu_command(_command(3,&"remove_sand"))
	await _ticks(2)
	var generation: int=preview.generation
	var restored: StringName=await preview.restore_gpu_checkpoint(path)
	var state: Dictionary=await _all("restored")
	var same:=true
	for field in checkpoint_state: same=same and state[field]==checkpoint_state[field]
	_check("mixed_active_restore_native_and_history",altered.get("status")==1 and restored==&"" and same and preview.generation==generation+1 and preview.gpu_prefix==checkpoint_prefix and preview.command_queue.last_command_id==highwater and preview.command_queue.applied_log.size()==3 and _chunks_exact(state),{"restore":String(restored),"fields_exact":same})
	var next: Dictionary=_command(3,&"compact");next.erase("amount_m3")
	var healthy: Dictionary=await preview.apply_legacy_command(next)
	_check("mixed_restored_cpu_command_healthy",healthy.get("results",[]).size()==1 and healthy.results[0].status==&"applied" and preview.gpu_prefix.size()==4)
	for item in checks: failed=failed or not item.pass
	failed=failed or not preview.last_error.is_empty()
	await preview.shutdown();_write();preview.queue_free();finished=true;print("BEACH_MIXED_RESTORE_COMPLETE pass=%s"%str(not failed));quit(1 if failed else 0)
