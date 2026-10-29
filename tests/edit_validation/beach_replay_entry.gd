extends "res://tests/edit_validation/beach_undo_entry.gd"

var full_replay_anchor := {}
var anchor_bootstrap_pending := false
var anchor_bootstrap_complete := false
var initial_playing := false
var branch_running := false
var branch_worker
var branch_events := []
var branch_disposals := []
var sand_copy_trace=preload("res://scripts/simulation/edit_validation/beach_sand_copy_trace.gd").new()

func _tick_finished(substeps: int, source_m3: float, sink_m3: float, token: int) -> void:
	super._tick_finished(substeps,source_m3,sink_m3,token)
	if "--beach-copy-sand-trace" in OS.get_cmdline_user_args(): RenderingServer.call_on_render_thread(_copy_sand_tick.bind(completed_ticks))

func _copy_sand_tick(tick: int) -> void:
	sand_copy_trace.capture(solver,tick)
	if ("--beach-copy-native-boundary" in OS.get_cmdline_user_args() and tick in [7,8]) or ("--beach-copy-native-early" in OS.get_cmdline_user_args() and tick<=8): sand_copy_trace.capture_native(self,tick)
func _sand_trace_record(bytes: PackedByteArray, key: Variant) -> void: sand_copy_trace.record_data(bytes,key)
func _read_sand_trace() -> void: sand_copy_trace.read(self,solver)

func collect_sand_trace() -> Dictionary:
	RenderingServer.call_on_render_thread(_read_sand_trace)
	await get_tree().process_frame
	while sand_copy_trace.pending>0 or sand_copy_trace.data.size()<sand_copy_trace.records.size(): await get_tree().process_frame
	return sand_copy_trace.data.duplicate(true)

func _render_release() -> void:
	if solver!=null and solver.rd!=null and sand_copy_trace.pending==0: sand_copy_trace.release(solver)
	super._render_release()

func _ready() -> void:
	initial_playing=playing;playing=false
	super._ready()

func _mark_ready(token: int) -> void:
	super._mark_ready(token)
	if not ready_for_ticks or anchor_bootstrap_complete: return
	ready_for_ticks=false
	if not anchor_bootstrap_pending:
		anchor_bootstrap_pending=true;call_deferred("_bootstrap_anchor")

func _bootstrap_anchor() -> void:
	input_scheduler.accepting=false
	full_replay_anchor=await _capture_complete_data()
	anchor_bootstrap_pending=false
	if full_replay_anchor.is_empty() or shutdown_requested: return
	if "--beach-copy-native-early" in OS.get_cmdline_user_args(): RenderingServer.call_on_render_thread(_copy_initial_native)
	anchor_bootstrap_complete=true;ready_for_ticks=true;input_scheduler.accepting=true;playing=initial_playing

func _copy_initial_native() -> void: sand_copy_trace.capture_native(self,0)

func _start_tick() -> void:
	if not anchor_bootstrap_complete or branch_running: return
	super._start_tick()

func apply_gpu_command(command: Dictionary) -> Dictionary:
	if not anchor_bootstrap_complete or branch_running: return {"error":"replay_busy"}
	return await super.apply_gpu_command(command)

func _advance_worker(tick: int) -> String:
	if tick<branch_worker.completed_ticks: return "replay_tick_order"
	while branch_worker.completed_ticks<tick:
		if branch_worker.completed_ticks==replay_capture_tick() and "--beach-replay-capture" in OS.get_cmdline_user_args():
			if not await capture_replay_gate("worker"): return "capture_gate_failed"
		if shutdown_requested: return "closed"
		branch_worker._start_tick()
		while branch_worker.tick_pending and branch_worker.last_error.is_empty(): await get_tree().process_frame
		if not branch_worker.last_error.is_empty(): return branch_worker.last_error
	return ""

func capture_replay_gate(label: String) -> bool:
	var output_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output_path=arg.get_slice("=",1)
	if output_path.is_empty(): return false
	var ready:=FileAccess.open(output_path.path_join("capture_ready_%s.json"%label),FileAccess.WRITE)
	ready.store_string(JSON.stringify({"pid":OS.get_process_id(),"tick":replay_capture_tick(),"branch":label,"process_frame":Engine.get_process_frames()}));ready.close()
	var deadline:=Time.get_ticks_msec()+75000
	while not FileAccess.file_exists(output_path.path_join("capture_go_%s.json"%label)):
		if Time.get_ticks_msec()>deadline or shutdown_requested: return false
		await get_tree().process_frame
	var file:=FileAccess.open(output_path.path_join("capture_go_%s.json"%label),FileAccess.READ)
	var marker: Variant=JSON.parse_string(file.get_as_text());file.close()
	return typeof(marker)==TYPE_DICTIONARY and marker.get("target_pid")==OS.get_process_id()

func _run_full_branch(prefix: Array, target_tick: int) -> Dictionary:
	if full_replay_anchor.is_empty() or target_tick<full_replay_anchor.tick: return {"error":"missing_replay_anchor"}
	var anchor_size: int=full_replay_anchor.gpu_beach_edit.prefix.size()
	if prefix.size()<anchor_size or prefix.slice(0,anchor_size)!=full_replay_anchor.gpu_beach_edit.prefix: return {"error":"replay_anchor_prefix_mismatch"}
	branch_worker=load("res://tests/edit_validation/edit_beach_replay_worker.tscn").instantiate()
	branch_worker.playing=false;branch_worker.visible=false
	branch_worker.observe_coupled_parameters="--beach-parameter-trace" in OS.get_cmdline_user_args()
	branch_worker.replay_checkpoint=full_replay_anchor.duplicate(true);branch_worker.replay_target_tick=full_replay_anchor.tick
	$ReplayViewport.add_child(branch_worker)
	while not branch_worker.ready_for_ticks and branch_worker.last_error.is_empty(): await get_tree().process_frame
	while not branch_worker.replay_ready and branch_worker.last_error.is_empty(): await get_tree().process_frame
	if not branch_worker.last_error.is_empty() or shutdown_requested: return {"error":"closed" if shutdown_requested else branch_worker.last_error}
	branch_worker.replay_target_tick=-1;branch_worker.set_process_unhandled_input(false);branch_worker.input_scheduler.accepting=false
	for item in prefix.slice(anchor_size):
		var error:=await _advance_worker(item.execution_tick)
		if not error.is_empty(): return {"error":error}
		var executed: Dictionary=await branch_worker.replay_item(item)
		if not executed.error.is_empty(): return executed
	var error:=await _advance_worker(target_tick)
	if not error.is_empty(): return {"error":error}
	var captured: Dictionary=await branch_worker.capture_complete_data()
	if captured.is_empty(): return {"error":"replay_capture_failed"}
	var trace: Dictionary=await branch_worker.collect_sand_trace() if "--beach-copy-sand-trace" in OS.get_cmdline_user_args() else {}
	var parameters: Dictionary=branch_worker.replay_parameter_evidence() if branch_worker.observe_coupled_parameters else {}
	var material_trace: Dictionary=await branch_worker.collect_material_trace() if "--beach-material-stage-trace" in OS.get_cmdline_user_args() else {}
	return {"error":"","checkpoint":captured,"sand_trace":trace,"parameters":parameters,"material_trace":material_trace,"isolated_materials":branch_worker.terrain_material!=terrain_material and branch_worker.water_material!=water_material,"history_bytes":0}

func _dispose_branch() -> void:
	if branch_worker==null: return
	var worker=branch_worker;branch_worker=null
	await worker.shutdown()
	branch_disposals.append({"released":worker.solver.rd==null and worker.collision_proxy.rd==null,"pending_native":worker.pending_beach_native_readbacks,"release_us":worker.gpu_release_us,"last_callback_us":worker.beach_native_callback_us})
	worker.queue_free();await get_tree().process_frame

func prove_replay_current() -> Dictionary:
	var error:=_undo_error()
	if not error.is_empty() or branch_running: return {"error":error if not error.is_empty() else "replay_busy"}
	var accepting: bool=input_scheduler.accepting
	branch_running=true;input_scheduler.accepting=false
	var current: Dictionary=await _capture_complete_data()
	var replayed: Dictionary=await _run_full_branch(gpu_prefix,completed_ticks)
	await _dispose_branch()
	var exact: bool=replayed.get("error")=="" and not current.is_empty() and _fingerprint(current)==_fingerprint(replayed.checkpoint) and current.gpu_beach_edit.prefix==replayed.checkpoint.gpu_beach_edit.prefix
	branch_events.append({"kind":"prove_original","tick":completed_ticks,"exact":exact,"error":replayed.get("error")})
	branch_running=false;input_scheduler.accepting=accepting and not shutdown_requested and last_error.is_empty()
	return {"ok":exact,"error":"" if exact else "replay_current_mismatch","detail":replayed.get("error"),"sand_trace":replayed.get("sand_trace",{}),"parameters":replayed.get("parameters",{}),"material_trace":replayed.get("material_trace",{}),"isolated_materials":replayed.get("isolated_materials",false),"replayed":replayed.get("checkpoint",{})}

func shutdown() -> void:
	shutdown_requested=true;input_scheduler.accepting=false
	while branch_running or anchor_bootstrap_pending: await get_tree().process_frame
	await _dispose_branch()
	await super.shutdown()
