extends "res://tests/floating_props/lifecycle_probe.gd"

func _run() -> void:
	orphan_baseline=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	scene=load("res://scenes/main.tscn").instantiate();root.add_child(scene);props=scene.get_node("FloatingProps/Service")
	var deadline:=Time.get_ticks_msec()+90000
	while scene._booting and Time.get_ticks_msec()<deadline:await process_frame
	check("running_main_ready",scene.ready_for_ticks and props.active)
	var ui=scene.get_node("Interface/FloatingPropsPanel")
	ui.select_body(1)
	ui.perform_action(1,Vector2(3,-4),false)
	check("interaction_accepted_before_close",ui.working and props.busy)
	await scene.shutdown()
	deadline=Time.get_ticks_msec()+5000
	while ui.working and Time.get_ticks_msec()<deadline:await process_frame
	check("interaction_terminal_during_close",not ui.working and ui.last_result.get("error")==&"closing")
	check("close_releases_readers_and_bodies",props.closed and not props.pending and not props.busy and props.registry.all(func(row):return row.body.service==null))
	check("common_domain_closed",scene.unified_release_complete())
	await _close()
