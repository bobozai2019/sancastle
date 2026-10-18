extends "res://tests/integration/unified_edit_playable_probe.gd"

var callback_count:=0
var receipt: Dictionary={}

func _received(value: Dictionary) -> void:callback_count+=1;receipt=value

func _run() -> void:
	orphan_baseline=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	# Public reader fault injection runs on an entry without the live prop
	# consumer. Main's own unknown-reader retirement is covered by lifecycle_probe.
	scene=load("res://scenes/unified_edit/playable/test1_capture.tscn").instantiate();scene.playing=false;root.add_child(scene)
	var deadline:=Time.get_ticks_msec()+90000
	while not scene.ready_for_ticks and scene.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check("formal_entry_ready",scene.ready_for_ticks and scene.last_error.is_empty())
	if not scene.ready_for_ticks:await _close();return
	observations.sources=scene.configuration.sources.duplicate(true)
	observations.engine=Engine.get_version_info()
	check("current_checkpoint_saved",(await scene.save_gpu_checkpoint(output.get_base_dir()+"/current.sandue")).is_empty())
	var old=scene.runtime.current
	var request:={"request_id":1,"owner_token":1,"generation":old._generation,"pose_seq":1,"domain_id":scene.configuration.domain_id,"minimum_state_seq":0,"points":[{"body_id":1,"point_id":1,"position":Vector3.ZERO}],"footprints":[Rect2(-1,-1,2,2)]}
	old.views.probe.hold_delivery=true
	check("public_runtime_probe_admitted",scene.runtime.request_probe(request,_received).accepted)
	deadline=Time.get_ticks_msec()+15000
	while old.views.probe.held.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check("old_reader_pending",old.views.probe.pending)
	check("restore_while_probe_pending",(await scene.restore_gpu_checkpoint(output.get_base_dir()+"/current.sandue")).is_empty())
	check("retired_generation_retains_probe_resources",scene.runtime.current!=old and not old.released and old.views.probe.owned.size()>0 and old.views.probe.pending)
	old.views.probe.deliver_held()
	check("old_probe_callback_is_stale_generation",callback_count==1 and receipt.error==&"stale_generation")
	deadline=Time.get_ticks_msec()+15000
	while not old.released and Time.get_ticks_msec()<deadline:await process_frame
	check("retired_probe_released_after_real_delivery",old.released and old.ownership_counts().values().all(func(v):return v==0))
	var current=scene.runtime.current
	# Control the admission/unknown observation phase; shutdown itself must retry.
	scene.set_process(false)
	request.generation=current._generation
	current.views.probe.inject_readback_failure_once=true
	check("shutdown_unknown_probe_admitted",scene.runtime.request_probe(request,_received).accepted)
	deadline=Time.get_ticks_msec()+15000
	while not current.views.probe.unknown and Time.get_ticks_msec()<deadline:await process_frame
	check("shutdown_starts_with_unknown_reader",current.views.probe.pending and current.views.probe.unknown)
	await scene.shutdown()
	check("shutdown_maintenance_retries_and_reclaims_probe",scene.unified_release_complete() and current.released and callback_count==2 and receipt.error==&"stale_generation" and current.ownership_counts().values().all(func(v):return v==0))
	var service=root.get_node("BeachScenes")
	if service.active_scene==scene:service.active_scene=null
	root.remove_child(scene);scene.free();scene=null
	await process_frame;await process_frame
	check("no_orphan_nodes",int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))<=orphan_baseline)
	finish()

func finish() -> void:
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"checks":checks,"observations":observations,"scope":"G1 formal runtime generation/retirement/shutdown reader ownership; no prop lifecycle or clock assertion"},"\t"));quit(1 if failed else 0)
