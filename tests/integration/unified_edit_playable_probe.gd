extends SceneTree

const L=preload("res://scripts/simulation/unified_edit/layout.gd")
const Codec=preload("res://scripts/simulation/unified_edit/checkpoint_codec.gd")
var scene
var output:=""
var scene_key:="main"
var checks: Array=[]
var failed:=false
var observations: Dictionary={}
var orphan_baseline:=0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		if arg.begins_with("--scene="):scene_key=arg.trim_prefix("--scene=")
	call_deferred("_run")

func check(name: String, passed: bool) -> void:
	checks.append({"name":name,"pass":passed});failed=failed or not passed;print("PLAYABLE_PROBE ",name," ",passed)

func _entry_path(key: String) -> String:return "res://scenes/unified_edit/playable/"+key+".tscn"
func _ready_timeout_ms() -> int:return 90000

func _run() -> void:
	orphan_baseline=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	DisplayServer.window_set_size(Vector2i(1280,720))
	scene=load(_entry_path(scene_key)).instantiate();scene.playing=false;scene.generation=1001;root.add_child(scene)
	var start:=Time.get_ticks_msec()
	while not scene.ready_for_ticks and scene.last_error.is_empty() and Time.get_ticks_msec()-start<90000:await process_frame
	check("actual_entry_ready",scene.ready_for_ticks and scene.last_error.is_empty())
	if not scene.ready_for_ticks:await _close();return
	check("new_root_has_no_legacy_base",scene.get_script().get_base_script()==null and not "solver" in scene and not scene.has_node("GpuCollisionProxy"))
	observations.sources=scene.configuration.sources.duplicate(true)
	var panel=scene.panel
	panel.get_node("Margin/Controls/Tools/Fill").pressed.emit()
	check("fixed_tool_button_connected",scene.selected_sand_tool==&"place_sand")
	var owner=scene.runtime.current
	owner.hold_completions=true
	check("fill_click_admitted",scene.input.begin(scene.selected_sand_tool,Vector2(3,0),{},0.1,3,0.25).accepted)
	check("sub_minimum_drag_volume_admitted",scene.input.move(Vector2(3.05,0)).accepted)
	scene.input.finish()
	var shapes:={&"castle_v1":{"scale_xz":1.0,"height_m":0.7,"yaw_rad":0.0},&"wall_v1":{"height_m":0.3,"bottom_width_m":1.0,"top_width_m":0.5},&"shovel_v1":{"trench_width_m":0.5,"depth_m":0.15,"shoulder_width_m":0.5}}
	var index:=0
	for tool in shapes:
		var point:=Vector2(3.0,float(index)*3.0-4.0)
		check(String(tool)+"_begin_sample",scene.input.begin(tool,point,shapes[tool],0.1,3,0.25).accepted)
		if tool!=&"castle_v1":check(String(tool)+"_sweep",scene.input.move(point+Vector2(0.4,0)).accepted)
		check(String(tool)+"_end_queued",scene.input.finish().accepted)
		index+=1
	check("all_tools_queued_without_cpu_receipts",scene.input.waiting.size()==13 and scene.input.terminal.is_empty())
	owner.hold_completions=false
	await _idle()
	check("all_tool_receipts_consumed",scene.input.waiting.is_empty() and scene.input.terminal.size()==13)
	var valid:=true;var applied:=0
	for row in scene.input.terminal:
		valid=valid and row.outcome in [L.Outcome.APPLIED,L.Outcome.NO_CHANGE]
		if row.outcome==L.Outcome.APPLIED:applied+=1
	check("common_results_no_tool_rejection",valid and applied>0)
	observations.tool_results=scene.input.terminal.duplicate(true)
	var controls=scene.get_node("Interface/EditPanel/Margin/Controls")
	controls.get_node("WaveAmount").value=0.07
	controls.get_node("TriggerWave").pressed.emit()
	observations.wave={"amplitude":scene.manual_wave_amplitude_m,"highwater":owner.boundary.highwater,"message":scene.action_message}
	check("fixed_wave_button_connected",is_equal_approx(scene.manual_wave_amplitude_m,0.07) and owner.boundary.highwater==1)
	var paused_time: float=owner.advanced_time_s
	for frame in 6:await process_frame
	check("pause_does_not_advance_clock",owner.advanced_time_s==paused_time)
	scene.playing=true
	start=Time.get_ticks_msec()
	while owner.completed_tick<3 and Time.get_ticks_msec()-start<15000:await process_frame
	scene.playing=false;await _idle()
	check("real_time_play_advances_common_ticks",owner.completed_tick>=3 and owner.advanced_time_s>paused_time)
	panel.get_node("Margin/Controls/Tools/Wall").pressed.emit()
	check("open_wall_before_save",scene.input.begin(&"wall_v1",Vector2(5,4),shapes[&"wall_v1"],0.1,3,0.25).accepted)
	var path:=output+"/playable.sandue"
	check("save_closes_live_stroke",(await scene.save_gpu_checkpoint(path)).is_empty() and scene.input.gesture.is_empty())
	await process_frame
	var saved:=Codec.load(path,scene.configuration);check("saved_native_valid",saved.error.is_empty())
	var saved_seq: int=saved.checkpoint.state_seq if saved.error.is_empty() else -1
	check("edit_after_save",scene.input.begin(&"remove_sand",Vector2(3,0),{},0.1,3,0.25).accepted);scene.input.finish();await _idle()
	check("restore_public_entry",(await scene.restore_gpu_checkpoint(path)).is_empty())
	start=Time.get_ticks_msec()
	while not scene.runtime.retired.is_empty() and Time.get_ticks_msec()-start<30000:await process_frame
	await process_frame
	check("restored_generation_and_native_sequence",scene.generation==1002 and scene.runtime.current.completed_state_seq==saved_seq and owner.released and scene.selected_sand_tool==&"wall_v1")
	var bound:=true
	for binding in scene.material_bindings:
		for parameter in binding.parameters:
			var value: Variant=binding.material.get_shader_parameter(parameter)
			bound=bound and value is Texture2DRD and value.texture_rd_rid==scene.runtime.current.views.textures[binding.parameters[parameter]]
	check("actual_entry_materials_rebound",bound)
	var sampling=scene.get_node("Interface/PerformancePanel/Margin/Rows/Header/Sampling")
	sampling.button_pressed=not sampling.button_pressed
	check("fixed_readonly_hud_toggle",scene.get_node("Interface/PerformancePanel").sampling==sampling.button_pressed)
	await RenderingServer.frame_post_draw;await RenderingServer.frame_post_draw
	check("interactive_entry_render_saved",root.get_texture().get_image().save_png(output+"/playable.png")==OK)
	observations.runtime_events=scene.runtime.events.duplicate(true)
	check("close_with_queued_input",scene.input.begin(&"wall_v1",Vector2(5,6),shapes[&"wall_v1"],0.1,3,0.25).accepted)
	await _close()

func _idle() -> void:
	var start:=Time.get_ticks_msec()
	while (scene.runtime.current.pending_count()!=0 or scene.runtime.current.active_count()!=0 or not scene.input.waiting.is_empty()) and Time.get_ticks_msec()-start<30000:await process_frame
	check("common_queue_idle_"+str(checks.size()),scene.runtime.current.pending_count()==0 and scene.runtime.current.active_count()==0 and scene.input.waiting.is_empty())

func _close() -> void:
	await scene.shutdown();check("entry_released",scene.unified_release_complete())
	var service=root.get_node("BeachScenes")
	if service.active_scene==scene:service.active_scene=null
	root.remove_child(scene);scene.free();scene=null
	await process_frame;await process_frame
	check("no_orphan_nodes",int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))<=orphan_baseline)
	call_deferred("finish")

func finish() -> void:
	FileAccess.open(output+"/probe.json",FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"checks":checks,"observations":observations,"scope":"Unified playable entry; executed checks and consumed sources define family and coverage. No performance acceptance is implied."},"\t"))
	quit(1 if failed else 0)
