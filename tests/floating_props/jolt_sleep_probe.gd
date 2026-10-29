extends SceneTree

var output:=""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	call_deferred("_run")

func _run() -> void:
	var fixture=load("res://tests/floating_props/jolt_sleep_fixture.tscn").instantiate();root.add_child(fixture)
	var body=fixture.get_node("Body")
	var start: int=Engine.get_physics_frames()
	while not body.sleeping and Engine.get_physics_frames()-start<360:await physics_frame
	var asleep: bool=body.sleeping;var count: int=body.steps.size();var sleep_frame: int=Engine.get_physics_frames()
	for frame in 30:await physics_frame
	var stable: bool=body.sleeping and absf(body.position.y-0.1)<0.005
	var result:={"pass":asleep and stable,"engine":Engine.get_version_info(),"penetration_slop_m":ProjectSettings.get_setting("physics/jolt_physics_3d/simulation/penetration_slop"),"sleep_reached":asleep,"sleep_frame":sleep_frame,"end_frame":Engine.get_physics_frames(),"callbacks_before_sleep_window":count,"callbacks_during_sleep_window":body.steps.size()-count,"position":body.position,"steps":body.steps,"scope":"Jolt engine sleep/callback mechanism observation; no GPU-clock or dynamic-sand acceptance"}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"));print("JOLT_SLEEP ",asleep," ",stable," sleep callbacks ",body.steps.size()-count)
	root.remove_child(fixture);fixture.free();quit(0 if result.pass else 1)
