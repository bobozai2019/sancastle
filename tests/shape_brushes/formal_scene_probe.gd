extends "res://tests/shape_brushes/material_edit_probe.gd"

var service
var anchors:={}
var retained:=[]

func wait_ready() -> bool:
	var deadline:=Time.get_ticks_msec()+90000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	_check(preview.scene_key+"_ready",preview.ready_for_ticks and preview.last_error.is_empty(),preview.last_error)
	return preview.ready_for_ticks and preview.last_error.is_empty()

func switch_to(key:String,fail:bool=false) -> bool:
	var old=preview;var generation:int=old.generation
	retained.append({"water":old.shape_gpu.water_transaction,"query":old.preview_query})
	service.inject_target_failure_once=fail
	_check("switch_admitted_"+key,service.request_switch(key))
	var deadline:=Time.get_ticks_msec()+150000
	while service.busy and Time.get_ticks_msec()<deadline:await process_frame
	preview=service.active_scene
	_check("switch_settled_"+key,not service.busy and preview!=null and preview.generation>generation,service.last_error)
	if preview==null:return false
	_check("switch_route_"+key,preview.scene_key==key if not fail else preview.scene_key!=key,service.last_error)
	_check("switch_shared_brush_"+key,preview.ui_tool==&"wall_v1" and preview.brush_panel.parameters().height_m==0.2)
	_check("switch_full_release_"+key,retained[-1].water.rd==null and retained[-1].query.rd==null and service.release_records[-1].node_freed)
	return not service.busy

func _run() -> void:
	root.size=Vector2i(1280,720);pair_fields=27;service=root.get_node("BeachScenes")
	preview=load("res://scenes/main.tscn").instantiate();preview.playing=false;root.add_child(preview);current_scene=preview
	if not await wait_ready():_finish();quit(1);return
	preview.get_node("Interface/PerformancePanel/Margin/Rows/Header/Sampling").button_pressed=false
	preview._apply_brush_selection({"tool":"wall_v1","parameters":{"height_m":0.2,"bottom_width_m":1.0,"top_width_m":0.5},"dig_amount_m3":0.02,"fill_amount_m3":0.01})
	for key in ["main","test1_capture","test1_backwash"]:
		if key!="main" and not await switch_to(key):_finish();quit(1);return
		_check(key+"_complete_binding",preview.enable_brush_water and preview.enable_brush_checkpoint_v4 and preview.enable_brush_native_material and preview.brush_panel!=null and preview.brush_preview!=null)
		_check(key+"_full_workload",preview.staging_wave_workload==("continuous_packets_v1" if key=="main" else "none"))
		_check(key+"_begin",(await preview.begin_shape_stroke(2000)).is_empty())
		var command:=BrushProtocol.make_command(&"wall_v1",{"height_m":0.2,"bottom_width_m":1.0,"top_width_m":0.5},Vector2(-0.25,0),Vector2(0.25,0),preview.domain.domain_id,preview.generation,1,2000,0,preview.completed_ticks,preview.shape_baseline_token)
		command.material_profile_id=&"molded_v1"
		var result:=await submit(command);_check(key+"_wall_applied",result.get("status")==1,result)
		await preview.end_shape_stroke()
		var deadline:=Time.get_ticks_msec()+30000
		while (not preview.collision_proxy.pending_revisions.is_empty() or preview.collision_proxy.staging_texture.is_valid()) and Time.get_ticks_msec()<deadline:await process_frame
		await physics_frame;await physics_frame
		_check(key+"_collision_settled",preview.collision_proxy.pending_revisions.is_empty() and not preview.collision_proxy.staging_texture.is_valid())
		anchors[key]=await snapshot(key+"_anchor")
	for key in ["main","test1_capture","test1_backwash"]:
		if not await switch_to(key):_finish();quit(1);return
		_check(key+"_27_raw_restore",exact(anchors[key],await snapshot(key+"_restored")))
	var before:=await snapshot("rollback_before")
	await switch_to("test1_capture",true)
	_check("target_failure_atomic",exact(before,await snapshot("rollback_after")))
	await preview.shutdown();preview.queue_free();await process_frame
	_finish();var passed:=true
	for row in checks:passed=passed and row.pass
	quit(0 if passed else 1)
