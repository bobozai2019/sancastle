extends SceneTree

var scene
var output := ""
var checks := []
var readbacks := {}
const FIELDS := ["sand", "sediment"]

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	if output.is_empty() or FileAccess.file_exists(output.path_join("result.json")):
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	call_deferred("_run")

func check(name: String, ok: bool, details: Variant = null) -> void:
	checks.append({"name": name, "pass": ok, "details": details})
	print("GROWTH_CHECK ", name, " ", ok)

func _read() -> void:
	for field in FIELDS:
		scene.solver.request_data(field, func(bytes: PackedByteArray) -> void: call_deferred("_received", field, bytes))

func _received(field: String, bytes: PackedByteArray) -> void:
	readbacks[field] = bytes

func total_sand() -> float:
	readbacks.clear()
	RenderingServer.call_on_render_thread(_read)
	while readbacks.size() < FIELDS.size(): await process_frame
	var total := 0.0
	for key in FIELDS:
		for value in readbacks[key].to_float32_array(): total += float(value) * 0.015625
	return total

func _run() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	scene.playing = false
	root.add_child(scene)
	current_scene = scene
	var deadline := Time.get_ticks_msec() + 90000
	while not scene.ready_for_ticks and scene.last_error.is_empty() and Time.get_ticks_msec() < deadline: await process_frame
	check("ready", scene.ready_for_ticks and scene.last_error.is_empty())
	if not scene.ready_for_ticks:
		quit(1)
		return
	root.gui_disable_input = true
	scene.set_process_input(false)
	scene.set_process_unhandled_input(false)
	scene.player_camera.set_process(false)
	scene.player_camera.set_process_input(false)
	scene.player_camera.set_process_unhandled_input(false)
	scene.get_node("Interface/PerformancePanel/Margin/Rows/Header/Sampling").button_pressed = false
	while scene.collision_proxy.staging_texture.is_valid() or not scene.collision_proxy.pending_revisions.is_empty(): await process_frame
	await physics_frame
	await physics_frame
	var point := Vector3.ZERO
	var picked := false
	for y in range(300, 650, 30):
		for x in range(300, 900, 30):
			var hit: Dictionary = scene.pick(Vector2(x, y))
			if not hit.is_empty() and scene._pick_current(hit):
				point = hit.position
				picked = true
				break
		if picked: break
	check("physics_pick", picked)
	var initial := await total_sand()
	var applied := 0
	for index in 160:
		var kind: StringName = &"place_sand" if index % 2 == 0 else &"remove_sand"
		var admitted: bool = scene._submit_gpu_input(kind, point, point, &"circle", 0.0005)
		deadline = Time.get_ticks_msec() + 30000
		while scene.input_running and Time.get_ticks_msec() < deadline: await process_frame
		if not admitted or scene.input_running or scene.input_results.is_empty() or scene.input_results[-1].result.get("status") != 1:
			check("edit_" + str(index), false, scene.last_error)
			break
		applied += 1
		if index % 32 == 31: print("GROWTH_PROGRESS ", index + 1)
	check("160_real_gpu_edits", applied == 160)
	for pair in [["input_events", scene.input_events], ["input_results", scene.input_results], ["gpu_events", scene.gpu_events], ["scheduler_terminal", scene.input_scheduler.terminal], ["scheduler_admissions", scene.input_scheduler.admissions]]:
		check(pair[0] + "_bounded", pair[1].size() <= 128, pair[1].size())
	check("authoritative_prefix_retained", scene.gpu_prefix.size() == 160 and scene.command_queue.applied_log.size() == 160)
	check("latest_results_kept", scene.input_results[-1].command.command_id == 160 and scene.input_events[-1].command.command_id == 160)
	var final_total := await total_sand()
	var closure: float = final_total - initial - scene.domain.sand_source_m3 + scene.domain.sand_sink_m3
	check("sand_ledger_closes", absf(closure) < 0.00001, closure)
	check("empty_reservations", scene.input_scheduler.reserved_total() == 0.0 and scene.command_queue.pending.is_empty())
	var error: StringName = await scene.save_gpu_checkpoint(output.path_join("160_edits.sandcp"))
	check("save_with_bounded_diagnostics", error.is_empty(), error)
	await scene.get_node("Interface/PerformancePanel").stop_sampling()
	await scene.shutdown()
	check("clean_shutdown", scene.gpu_release_done and scene.solver.rd == null)
	var passed := true
	for item in checks: passed = passed and item.pass
	var file := FileAccess.open(output.path_join("result.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass": passed, "checks": checks, "scope": "160 native GPU alternating edits; diagnostics bounded, complete authoritative prefix and ledger retained"}, "\t"))
	quit(0 if passed else 1)
