extends "res://tests/gravel/gravel_transport_probe.gd"

func _render_action(operation: String, args: Array) -> void:
	if operation != "drop":
		super._render_action(operation, args)
		return
	_complete.call_deferred(gravel.add_at(solver, args[0], args[1], 1, gravel.completed_tick, gravel.revision))

func _run() -> void:
	output = "res://test_output/gravel_drop_transport_20261016"
	DirAccess.make_dir_recursive_absolute(output)
	await _action("setup")
	current_profile = Gravel.default_profile("main", 0)
	current_profile.spawn_bounds_xz = [-0.1,-0.1,0.1,0.1]
	current_profile.response_min = 0.5
	current_profile.response_max = 0.5
	await _action("inputs", [{"rock":0.5,"sand":0.2,"water":0.1,"momentum_x":0.1}])
	_check("empty_pool_initializes", await _action("new", [current_profile]))
	_check("drop_into_empty_pool", (await _action("drop", [Vector2.ZERO, 16])).is_empty())
	var before := await _snapshot("drop")
	await _action("advance", [1,0,1,1.0/30.0])
	var after := await _snapshot("flow")
	var a: PackedFloat32Array = before["state_%d" % before.current_index].to_float32_array()
	var b: PackedFloat32Array = after["state_%d" % after.current_index].to_float32_array()
	var correct := true
	for id in 16:
		correct = correct and absf(b[id*4]-a[id*4]-0.5/30.0)<0.00001 and absf(b[id*4+1]-0.7)<0.00001 and b[id*4+2]==a[id*4+2] and b[id*4+3]==1.0
	_check("all_new_stones_follow_known_flow", correct)
	await _action("inputs", [{"rock":0.5,"sand":0.2,"water":0.0,"momentum_x":0.1}])
	await _action("advance", [2,0,1,1.0/30.0])
	var dry := await _snapshot("dry")
	var c: PackedFloat32Array = dry["state_%d" % dry.current_index].to_float32_array()
	correct = true
	for id in 16: correct = correct and c[id*4]==b[id*4] and c[id*4+2]==b[id*4+2] and c[id*4+3]==0.0
	_check("all_new_stones_stop_when_dry", correct)
	await _action("inputs", [{"rock":0.5,"sand":0.2,"water":0.1,"momentum_x":-0.1}])
	await _action("advance", [3,0,1,1.0/30.0])
	var reverse := await _snapshot("reverse")
	var d: PackedFloat32Array = reverse["state_%d" % reverse.current_index].to_float32_array()
	correct = true
	for id in 16: correct = correct and absf(d[id*4]-c[id*4]+0.5/30.0)<0.00001 and d[id*4+3]==1.0
	_check("all_new_stones_restart_with_reverse_flow", correct)
	await _action("release")
	var passed := true
	for row in checks: passed = passed and row.pass
	FileAccess.open(output.path_join("result.json"), FileAccess.WRITE).store_string(JSON.stringify({"pass":passed,"checks":checks,"traces":traces}, "\t"))
	quit(0 if passed else 1)
