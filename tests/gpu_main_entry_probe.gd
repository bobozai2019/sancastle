extends SceneTree

var main: Node3D
var started_ms := 0
var finished := false
var sand_readback := PackedByteArray()


func _init() -> void:
	call_deferred("_begin")


func _begin() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	if scene == null:
		_fail("main scene unavailable")
		return
	main = scene.instantiate()
	root.add_child(main)
	started_ms = Time.get_ticks_msec()
	call_deferred("_watchdog")
	call_deferred("_wait_initial_gpu")


func _wait_initial_gpu() -> void:
	if finished:
		return
	if not main.gpu_active or main.active_scene == null or \
			main.active_scene.name != "GpuProduction":
		_fail("main did not default to GPU production scene")
		return
	if not main.active_scene.last_error.is_empty():
		_fail(main.active_scene.last_error)
		return
	if main.active_scene.completed_ticks < 3:
		await process_frame
		call_deferred("_wait_initial_gpu")
		return
	main.active_scene.playing = false
	if main.active_scene.tick_pending:
		await process_frame
		call_deferred("_wait_initial_gpu")
		return
	var gpu_scene: Node3D = main.active_scene
	if gpu_scene.shadow_domain.grid_size != 256 or \
			gpu_scene.sand_texture.texture_rd_rid != gpu_scene.solver.current_texture("sand"):
		_fail("main GPU state/display not synchronized")
		return
	var frozen_hashes := [2704912432, 1484022548, 4287897902]
	var previous_generation: int = gpu_scene.shadow_domain.generation
	for preset in 3:
		var preset_event := InputEventKey.new()
		preset_event.keycode = KEY_1 + preset
		preset_event.pressed = true
		main._input(preset_event)
		if main.selected_preset != preset or main.active_scene.preset_index != preset:
			_fail("main GPU preset selection mismatch: %d" % preset)
			return
		var scene_domain: SandWaterDomain = main.active_scene.shadow_domain
		if scene_domain.generation <= previous_generation or \
				scene_domain.generation != main.active_scene.generation:
			_fail("main GPU preset rebuild did not advance generation")
			return
		var stale_command := {"domain_id": scene_domain.domain_id,
			"generation": previous_generation, "sim_tick": scene_domain.sim_tick,
			"command_id": main.active_scene.command_queue.last_command_id + 1,
			"kind": &"debug_add_sand", "shape": &"circle",
			"transform": {"position_m": Vector3.ZERO}, "radius_m": 0.25,
			"strength": 1.0, "amount_m3": 0.001, "seed": 1}
		var old_highwater: int = main.active_scene.command_queue.last_command_id
		var old_pending: int = main.active_scene.command_queue.pending.size()
		if main.active_scene.command_queue.submit(stale_command) != &"inactive_generation" or \
				main.active_scene.command_queue.last_command_id != old_highwater or \
				main.active_scene.command_queue.pending.size() != old_pending:
			_fail("stale GPU command changed a rebuilt scene")
			return
		previous_generation = scene_domain.generation
		if hash([scene_domain.rock, scene_domain.sand, scene_domain.water,
				scene_domain.wetness]) != frozen_hashes[preset]:
			_fail("main GPU preset frozen seed mismatch: %d" % preset)
			return
		while not main.active_scene.ready_for_ticks or main.active_scene.completed_ticks < 3:
			if not main.active_scene.last_error.is_empty():
				_fail(main.active_scene.last_error)
				return
			await process_frame
		main.active_scene.playing = false
		while main.active_scene.tick_pending:
			await process_frame
		sand_readback = PackedByteArray()
		RenderingServer.call_on_render_thread(_render_request_sand)
		while sand_readback.is_empty():
			await process_frame
		var actual := sand_readback.to_float32_array()
		if actual.size() != scene_domain.sand.size():
			_fail("main GPU preset sand readback size mismatch")
			return
		var max_sand_error := 0.0
		for i in actual.size():
			max_sand_error = maxf(max_sand_error,
				absf(actual[i] - scene_domain.sand[i]))
		if max_sand_error > 0.000001:
			_fail("main GPU preset %d sand mismatch: %.8f" % [preset, max_sand_error])
			return
		for frame in 2:
			await process_frame
		var preset_image := root.get_texture().get_image()
		var preset_path := "res://test_output/sandcastle_water_sand_coupling/验收/GPU_main_preset_%d_20260928.png" % (preset + 1)
		if preset_image.save_png(preset_path) != OK:
			_fail("main GPU preset screenshot save failed")
			return
	main.active_scene.playing = true
	var rapid_one := InputEventKey.new()
	rapid_one.keycode = KEY_1
	rapid_one.pressed = true
	var rapid_three := InputEventKey.new()
	rapid_three.keycode = KEY_3
	rapid_three.pressed = true
	main._input(rapid_one)
	main._input(rapid_three)
	if main.selected_preset != 2 or main.active_scene.preset_index != 2:
		_fail("rapid GPU preset switch chose wrong generation")
		return
	if main.active_scene.shadow_domain.generation <= previous_generation:
		_fail("rapid GPU preset switch reused generation")
		return
	previous_generation = main.active_scene.shadow_domain.generation
	while not main.active_scene.ready_for_ticks or main.active_scene.completed_ticks < 3:
		if not main.active_scene.last_error.is_empty():
			_fail("rapid GPU preset switch: " + main.active_scene.last_error)
			return
		await process_frame
	var event := InputEventKey.new()
	event.keycode = KEY_F9
	event.pressed = true
	main._input(event)
	if main.gpu_active or main.active_scene.name != "CpuReference" or \
			main.active_scene.domain.grid_size != 64 or \
			main.active_scene.scene_index != 2 or \
			main.active_scene.domain.generation <= previous_generation:
		_fail("F9 did not enter CPU reference")
		return
	previous_generation = main.active_scene.domain.generation
	main.active_scene._reset_domain(2)
	main.active_scene._reset_domain(2)
	if main.active_scene.domain.generation != previous_generation + 2:
		_fail("CPU reference reset did not advance generation")
		return
	previous_generation = main.active_scene.domain.generation
	for frame in 3:
		await process_frame
	if not main.active_scene.is_inside_tree():
		_fail("CPU reference was not live after switch")
		return
	main._input(event)
	if not main.gpu_active or main.active_scene.name != "GpuProduction" or \
			main.active_scene.preset_index != 2 or \
			main.active_scene.shadow_domain.generation <= previous_generation:
		_fail("F9 did not restore GPU production")
		return
	call_deferred("_wait_restored_gpu")


func _wait_restored_gpu() -> void:
	if finished:
		return
	if not main.active_scene.last_error.is_empty():
		_fail(main.active_scene.last_error)
		return
	if main.active_scene.completed_ticks < 3:
		await process_frame
		call_deferred("_wait_restored_gpu")
		return
	for frame in 3:
		await process_frame
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		_fail("main GPU screenshot unavailable")
		return
	var path := "res://test_output/sandcastle_water_sand_coupling/验收/GPU_main_entry_20260928.png"
	if image.save_png(path) != OK:
		_fail("main GPU screenshot save failed")
		return
	print("PASS: main GPU default, 3 frozen presets with GPU sand readback, rapid switch, F9 CPU reference with two resets, F9 GPU restore; stale_commands_rejected=3 final_generation=%d ticks=%d screenshot=%s" % [
		main.active_scene.shadow_domain.generation, main.active_scene.completed_ticks, path])
	finished = true
	main.queue_free()
	quit(0)


func _render_request_sand() -> void:
	var error: Error = main.active_scene.solver.request_data("sand", _on_sand)
	if error != OK:
		call_deferred("_fail", "main GPU sand readback request failed: %d" % error)


func _on_sand(data: PackedByteArray) -> void:
	call_deferred("_record_sand", data)


func _record_sand(data: PackedByteArray) -> void:
	if not finished:
		sand_readback = data


func _watchdog() -> void:
	if finished:
		return
	if Time.get_ticks_msec() - started_ms > 90000:
		_fail("main entry probe timed out")
		return
	await process_frame
	call_deferred("_watchdog")


func _fail(message: String) -> void:
	if finished:
		return
	finished = true
	printerr("FAIL: " + message)
	if main != null:
		main.queue_free()
	quit(1)
