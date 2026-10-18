extends "res://tests/integration/unified_edit_playable_probe.gd"

const Routes=preload("res://scripts/beach/unified_scene_routes.gd")
var raw: PackedByteArray
var raw_done:=false

func _run() -> void:
	orphan_baseline=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	DisplayServer.window_set_size(Vector2i(1280,720))
	scene=load(Routes.FORMAL[scene_key]).instantiate();scene.playing=false;scene.generation=1001;root.add_child(scene)
	var start:=Time.get_ticks_msec()
	while not scene.ready_for_ticks and scene.last_error.is_empty() and Time.get_ticks_msec()-start<180000:await process_frame
	check("formal_completion_ready",scene.ready_for_ticks and scene.last_error.is_empty())
	if not scene.ready_for_ticks:await _close();return
	observations.sources=scene.configuration.sources.duplicate(true)
	var owner=scene.runtime.current;owner.hold_completions=true
	owner.transport.inject_duplicate_completion_once=true;owner.transport.inject_reorder_first_completion=true
	check("first_edit",scene.input.begin(&"place_sand",Vector2(3,0),{},0.1,3,0.25).accepted);scene.input.finish()
	check("interleaved_real_water",scene.runtime.request_tick(0.001).is_empty())
	check("second_edit",scene.input.begin(&"place_sand",Vector2(3,1),{},0.1,3,0.25).accepted);scene.input.finish()
	start=Time.get_ticks_msec()
	while owner.arrival_order.size()<4 and Time.get_ticks_msec()-start<15000:await process_frame
	check("actual_out_of_order_duplicate_callbacks",owner.arrival_order.size()==4 and owner.arrival_order[0] in [2,3] and owner.arrival_order[1]==owner.arrival_order[0] and owner.arrival_order[2]==1 and owner.arrival_order[3] in [2,3] and owner.arrival_order[3]!=owner.arrival_order[0])
	check("no_cpu_publication_before_ordered_consume",owner.completed_state_seq==0 and scene.input.terminal.is_empty())
	var id: Dictionary=owner._records[1].identity.duplicate(true)
	RenderingServer.call_on_render_thread(_capture_render.bind(owner,id))
	while not raw_done and Time.get_ticks_msec()-start<20000:await process_frame
	check("actual_first_gpu_completion_captured",raw_done and raw.size()==L.COMPLETION_BYTES+L.RESULT_BYTES)
	FileAccess.open(output+"/first_completion.bin",FileAccess.WRITE).store_buffer(raw)
	owner.hold_completions=false;await _idle()
	check("ordered_publication_and_results_once",owner.completed_state_seq==3 and owner.completed_tick==1 and scene.input.terminal.size()==2 and scene.last_error.is_empty())
	var ledger: Dictionary=owner.accounting.ledger.duplicate(true)
	owner._receive(raw,id)
	var wrong: Dictionary=id.duplicate();wrong.generation=1000;owner._receive(raw,wrong)
	for frame in 3:await process_frame
	check("late_duplicate_and_wrong_epoch_do_not_change_authority",owner.completed_state_seq==3 and owner.completed_tick==1 and owner.accounting.ledger==ledger and scene.input.terminal.size()==2 and scene.last_error.is_empty())
	var path:=output+"/completed.sandue"
	check("completion_snapshot_save",(await scene.save_gpu_checkpoint(path)).is_empty());await process_frame
	var saved_ledger: Dictionary=owner.accounting.ledger.duplicate(true)
	check("completion_native_restore",(await scene.restore_gpu_checkpoint(path)).is_empty())
	start=Time.get_ticks_msec()
	while not scene.runtime.retired.is_empty() and Time.get_ticks_msec()-start<15000:await process_frame
	var current=scene.runtime.current
	current._receive(raw,id);owner._receive(raw,id)
	for frame in 3:await process_frame
	check("old_completion_cannot_publish_into_new_epoch",scene.generation==1002 and current.completed_state_seq==3 and current.completed_tick==1 and current.accounting.ledger==saved_ledger and current.fault_reason().is_empty() and owner.released)
	check("old_consumed_command_has_no_second_receipt",scene.runtime.take_result(1001,1).is_empty())
	observations.raw={"path":output+"/first_completion.bin","sha256":FileAccess.get_sha256(output+"/first_completion.bin"),"bytes":raw.size(),"identity":id}
	observations.arrivals=owner.arrival_order.duplicate();observations.results=scene.input.terminal.duplicate(true);observations.ledger=saved_ledger;observations.pre_save_ledger=ledger
	observations.current={"generation":scene.generation,"state_seq":current.completed_state_seq,"tick":current.completed_tick,"ledger":current.accounting.ledger.duplicate(true)}
	await _close()

func _capture_render(owner, id: Dictionary) -> void:
	var bytes: PackedByteArray=owner.transport.rd.buffer_get_data(owner.transport.resources[id.slot_id].output)
	var count:=bytes.decode_u32(L.COMPLETION_U32.result_count)
	call_deferred("_captured",bytes.slice(0,L.COMPLETION_BYTES+count*L.RESULT_BYTES))
func _captured(bytes: PackedByteArray) -> void:raw=bytes;raw_done=true
func finish() -> void:
	FileAccess.open(output+"/probe.json",FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"checks":checks,"observations":observations,"scope":"Formal actual duplicate/reordered GPU completions, replay of original raw completion after consumption and across native restore; no authority or ledger mutation"},"\t"))
	quit(1 if failed else 0)
