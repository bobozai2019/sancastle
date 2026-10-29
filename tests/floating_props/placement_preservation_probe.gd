extends "res://tests/floating_props/lifecycle_probe.gd"

func _run() -> void:
	orphan_baseline=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	scene=load("res://scenes/main.tscn").instantiate();root.add_child(scene);props=scene.get_node("FloatingProps/Service")
	var deadline:=Time.get_ticks_msec()+90000
	while scene._booting and Time.get_ticks_msec()<deadline:await process_frame
	check("main_ready",scene.ready_for_ticks and props.last_error.is_empty())
	await _run_for(1.0)
	var retained:={}
	for id in [2,3]:retained[id]={"pose":props.body_for_id(id).global_transform,"motion":props.saved[id].duplicate(true),"time":props.actual_time[id]}
	var result: Dictionary=await props.manipulate_body(1,Vector2(4,-4))
	check("paused_reposition",result.error.is_empty())
	for id in [2,3]:check("unselected_motion_and_pose_"+str(id),props.body_for_id(id).global_transform==retained[id].pose and props.saved[id]==retained[id].motion and props.actual_time[id]==retained[id].time)
	result=await props.manipulate_body(1,Vector2.ZERO,0.0,true)
	check("paused_pickup",result.error.is_empty())
	for id in [2,3]:check("pickup_preserves_unselected_"+str(id),props.body_for_id(id).global_transform==retained[id].pose and props.saved[id]==retained[id].motion)
	await _run_for(0.5)
	check("remaining_bodies_keep_real_steps",props.world_registry().size()==2 and props.last_error.is_empty() and props.actual_time[2]>retained[2].time and props.actual_time[3]>retained[3].time)
	await _close()
