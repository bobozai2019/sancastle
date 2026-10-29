extends "res://tests/integration/async_pipeline_main_probe.gd"

var parent_path:=""
var policies:=[]

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):output=argument.trim_prefix("--output=")
		if argument.begins_with("--parent="):parent_path=argument.trim_prefix("--parent=")
	call_deferred("_run")

func _policy(path: String) -> Dictionary:
	var original:=FileAccess.get_file_as_string(path)
	var start:=original.find("func _capture_render(")
	var end:=original.find("\nfunc _gpu_matches",start)
	check("capture_stub_boundaries",start>=0 and end>start)
	var stub:="func _capture_render(id: Dictionary) -> void:\n\tcall_deferred(\"_selection_complete\",id)\n\nfunc _selection_complete(id: Dictionary) -> void:\n\tslots[id.slot_id]={\"identity\":{},\"result\":{},\"job\":null,\"task\":-1}\n"
	var script:=GDScript.new()
	script.source_code=original.substr(0,start)+stub+original.substr(end)
	check("selection_script_compiles",script.reload()==OK)
	var policy=script.new()
	policy.rd=RenderingServer.get_rendering_device()
	policy.generation=1
	policy.observe=true
	if policy.has_method("_take_pending_chunks"):
		check("empty_selection",policy._take_pending_chunks().is_empty())
		policy.mark_chunks(PackedInt32Array([-1,64,63,0,16,16]))
		policy.selection_cursor=60
		check("sparse_wrap_and_unique",policy._take_pending_chunks()==PackedInt32Array([63,0,16]))
		check("sparse_selection_drained",policy.pending.is_empty() and policy.selection_cursor==17)
		policy.selection_cursor=0
	var first_requested:={}
	var request_counts:={}
	var pump_times:=[]
	var snapshots:=[]
	for round_index in 48:
		policy.mark_all()
		var before:=Time.get_ticks_usec()
		var submitted: int=policy.pump()
		pump_times.append(Time.get_ticks_usec()-before)
		check("bounded_two_slots",submitted==2 and policy.active_count()==2)
		for slot in policy.slots:
			var identity: Dictionary=slot.identity.duplicate(true)
			snapshots.append(identity)
			check("snapshot_chunk_limit",identity.chunks.size()<=16)
			for chunk in identity.chunks:
				if not first_requested.has(chunk):first_requested[chunk]=round_index
				request_counts[chunk]=int(request_counts.get(chunk,0))+1
			policy.mark_chunks(identity.chunks)
		var deadline:=Time.get_ticks_msec()+5000
		while policy.active_count()>0 and Time.get_ticks_msec()<deadline:await process_frame
		check("capture_callbacks_drained",policy.active_count()==0)
		check("new_dirty_not_cleared",policy.pending.size()==64)
	var drain_rounds:=0
	while not policy.pending.is_empty() and drain_rounds<8:
		policy.pump()
		while policy.active_count()>0:await process_frame
		drain_rounds+=1
	check("stopped_pressure_drains",policy.pending.is_empty())
	policy.rd=null
	return {"source":path,"source_sha256":FileAccess.get_sha256(path),"stubbed_source_sha256":script.source_code.sha256_text(),"pressure_rounds":48,"first_requested_round":first_requested,"requested_unique_chunks":first_requested.size(),"request_counts":request_counts,"pump_us":pump_times,"snapshots":snapshots,"drain_rounds":drain_rounds,"pending_after_drain":policy.pending.size(),"scope":"actual production pump/dirty logic; only GPU capture/worker replaced by a deferred terminal stub; request fairness, not GPU/physics cost"}

func _run() -> void:
	preview=load(scene_path).instantiate()
	preview.playing=false
	root.add_child(preview)
	var deadline:=Time.get_ticks_msec()+60000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check("main_ready",preview.ready_for_ticks and preview.last_error.is_empty())
	await preview.get_node("Interface/PerformancePanel").stop_sampling()
	policies.append(await _policy(parent_path))
	policies.append(await _policy("res://scripts/simulation/edit_validation/frame_pipeline/async_collision.gd"))
	check("parent_pressure_starves_high_half",policies[0].requested_unique_chunks==32)
	check("candidate_covers_all_chunks",policies[1].requested_unique_chunks==64)
	var maximum:=0
	for value in policies[1].first_requested_round.values():maximum=maxi(maximum,value)
	check("candidate_bounded_request_age",maximum<=1)
	await preview.shutdown()
	check("main_released",preview.gpu_release_done)
	preview.queue_free()
	await process_frame
	var file:=FileAccess.open(output,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify({"pass":not failed,"checks":checks,"policies":policies,"scope":"request coverage/age comparison; real heights, versions, rays and lifecycle verified by separate GPU collision probe"},"\t"))
	quit(1 if failed else 0)
