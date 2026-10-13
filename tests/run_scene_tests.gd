extends SceneTree

const Domain = preload("res://scripts/simulation/sand_water_domain.gd")
const Scenarios = preload("res://scripts/scenarios/standard_scenarios.gd")

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: PackedScene = load("res://scenes/cpu_reference.tscn")
	if scene == null:
		push_error("main scene failed to load")
		quit(1)
		return
	var demo: Node3D = scene.instantiate()
	root.add_child(demo)
	if Scenarios.camera_position(64, 0.125) != Vector3(0.0, 9.5, 11.0) or \
			Scenarios.camera_position(256, 0.125) != Vector3(0.0, 38.0, 44.0):
		failures.append("standard camera does not scale with physical domain")
	if absf(Scenarios.tide_level(0.0) - 0.10) > 0.000001:
		failures.append("standard tide starts at fixed mean level")
	var fixed_hashes := [
		[797845532, 2704912432],
		[3153909204, 1484022548],
		[92692016, 4287897902]
	]
	for preset in 3:
		var production_a = Domain.new(256, 0.125)
		var production_b = Domain.new(256, 0.125)
		if not Scenarios.initialize(production_a, preset) or not Scenarios.initialize(production_b, preset) or \
				hash([production_a.rock, production_a.sand, production_a.water]) != \
				hash([production_b.rock, production_b.sand, production_b.water]):
			failures.append("preset %d 256-square template is not deterministic" % preset)
		var production_hash := hash([production_a.rock, production_a.sand,
			production_a.water, production_a.wetness])
		if production_hash != fixed_hashes[preset][1]:
			failures.append("preset %d 256-square frozen input hash changed" % preset)
		demo._reset_domain(preset)
		if hash([demo.domain.rock, demo.domain.sand, demo.domain.water,
				demo.domain.wetness]) != fixed_hashes[preset][0]:
			failures.append("preset %d 64-square frozen input hash changed" % preset)
		var initial_hash := hash([demo.domain.rock, demo.domain.sand, demo.domain.water])
		var generation_before: int = demo.domain.generation
		demo._reset_domain(preset)
		if demo.domain.generation != generation_before + 1:
			failures.append("preset %d generation did not advance on rebuild" % preset)
		if hash([demo.domain.rock, demo.domain.sand, demo.domain.water]) != initial_hash:
			failures.append("preset %d fixed seed did not reproduce initial state" % preset)
		demo._update_visuals()
		if demo.domain.grid_size != 64:
			failures.append("preset %d grid size" % preset)
		if demo.terrain_mesh.mesh.get_surface_count() != 1:
			failures.append("preset %d terrain surface" % preset)
		if demo.water_mesh.mesh.get_surface_count() != 1:
			failures.append("preset %d water surface" % preset)
		var before: float = demo.domain.total_sand_m3()
		var command := {"command_id": 1, "kind": &"remove_sand", "position_m": Vector3.ZERO,
			"radius_m": 0.38, "strength": 1.0, "amount_m3": 0.015, "seed": 1}
		var result: Dictionary = demo.domain.apply_tool(command)
		if result.status != &"applied":
			failures.append("preset %d remove command" % preset)
		if absf(demo.domain.total_sand_m3() - before) > 0.00001:
			failures.append("preset %d sand inventory" % preset)
		demo.domain.step(1.0 / 30.0)
		if demo.domain.nan_events != 0:
			failures.append("preset %d nonfinite state" % preset)
	demo.playing = false
	var tick_before: int = demo.domain.sim_tick
	demo._step_simulation()
	if demo.domain.sim_tick != tick_before + 1:
		failures.append("paused single-step did not advance exactly one tick")
	var flow_index: int = demo.domain.index(2, 2)
	demo.domain.water[flow_index] = 0.1
	demo.domain.flux_right[flow_index] = 0.01
	demo.show_flow_arrows = true
	demo._update_visuals()
	if demo.flow_mesh.mesh.get_surface_count() != 1:
		failures.append("flow arrow debug mesh was not generated")
	if demo.terrain_chunks.size() != 4:
		failures.append("terrain should have four 32-cell chunks")
	else:
		var left_vertices: PackedVector3Array = demo.terrain_chunks[0].mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var right_vertices: PackedVector3Array = demo.terrain_chunks[1].mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var left_seam := {}
		var right_seam := {}
		for vertex in left_vertices:
			if absf(vertex.x) < 0.000001:
				left_seam[vertex] = true
		for vertex in right_vertices:
			if absf(vertex.x) < 0.000001:
				right_seam[vertex] = true
		if left_seam.is_empty() or left_seam != right_seam:
			failures.append("terrain chunk seam positions disagree")
	for view in range(1, 5):
		demo.debug_view = view
		demo._update_visuals()
		if demo.terrain_chunks[0].mesh.get_surface_count() != 1:
			failures.append("terrain debug view %d missing surface" % view)
	_press_key(demo, KEY_TAB)
	if demo.speed_multiplier != 10:
		failures.append("Tab did not select 10x speed")
	_press_key(demo, KEY_F)
	if demo.show_flow_arrows:
		failures.append("F did not hide flow arrows")
	_press_key(demo, KEY_V)
	if demo.debug_view != 0:
		failures.append("V did not cycle debug view")
	var tick_before_key: int = demo.domain.sim_tick
	_press_key(demo, KEY_N)
	if demo.domain.sim_tick != tick_before_key + 1:
		failures.append("N did not single-step paused scene")
	var sand_before: PackedFloat32Array = demo.domain.sand.duplicate()
	demo._submit_brush(&"remove_sand", 0.015, Vector3.ZERO, Vector3.ZERO, &"circle")
	var sand_after: PackedFloat32Array = demo.domain.sand.duplicate()
	_press_key(demo, KEY_Z)
	if demo.domain.sand != sand_before:
		failures.append("Z did not undo paused brush")
	_press_key(demo, KEY_Y)
	if demo.domain.sand != sand_after:
		failures.append("Y did not redo paused brush")
	for n in 100:
		var x := float(n % 10) * 0.6 - 2.7
		var z := float(n / 10) * 0.6 - 2.7
		var command := {"command_id": n + 100, "kind": &"remove_sand",
			"position_m": Vector3(x, 0.0, z), "radius_m": 0.32,
			"strength": 1.0, "amount_m3": 0.002, "seed": n}
		if demo.domain.apply_tool(command)["status"] != &"applied":
			failures.append("visual seam stress edit %d rejected" % n)
		demo._update_visuals()
	if _seam_vertices(demo.terrain_chunks[0], true) != _seam_vertices(demo.terrain_chunks[1], true) or \
			_seam_vertices(demo.terrain_chunks[2], true) != _seam_vertices(demo.terrain_chunks[3], true) or \
			_seam_vertices(demo.terrain_chunks[0], false) != _seam_vertices(demo.terrain_chunks[2], false) or \
			_seam_vertices(demo.terrain_chunks[1], false) != _seam_vertices(demo.terrain_chunks[3], false):
		failures.append("terrain chunks split after 100 visual edits")
	demo.queue_free()
	_test_cross_tick_history(scene)
	if failures.is_empty():
		print("PASS: 3 preset scene integration tests")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("FAIL: %d scene integration tests" % failures.size())
		quit(1)


func _test_cross_tick_history(scene: PackedScene) -> void:
	var demo = scene.instantiate()
	demo._reset_domain(0)
	demo.playing = false
	demo._submit_brush(&"remove_sand", 0.015, Vector3.ZERO, Vector3.ZERO, &"circle")
	for _tick in 3:
		demo._step_simulation()
	var original_hash := _simulation_hash(demo)
	var original_ledger: PackedStringArray = demo.audit_recorder.rows.duplicate()
	var generation_before_undo: int = demo.domain.generation
	var control = scene.instantiate()
	control._reset_domain(0)
	control.playing = false
	for _tick in 3:
		control._step_simulation()
	if not demo._undo_command():
		failures.append("cross-tick undo was rejected")
	elif _simulation_hash(demo) != _simulation_hash(control):
		failures.append("cross-tick undo did not reproduce no-edit water/momentum/tide state")
	if demo.domain.generation != generation_before_undo + 1:
		failures.append("cross-tick undo did not invalidate old generation")
	if not demo._redo_command():
		failures.append("cross-tick redo was rejected")
	elif _simulation_hash(demo) != original_hash or demo.audit_recorder.rows != original_ledger:
		failures.append("cross-tick redo did not reproduce original state and ledger")
	if demo.domain.generation != generation_before_undo + 2:
		failures.append("cross-tick redo did not advance generation")
	for n in 20:
		demo._submit_brush(&"remove_sand", 0.001, Vector3(float(n % 5) * 0.1 - 0.2, 0.0, 0.2),
			Vector3(float(n % 5) * 0.1 - 0.2, 0.0, 0.2), &"circle")
		demo._step_simulation()
	var before_stress_undo := _simulation_hash(demo)
	if not demo._undo_command() or not demo._redo_command():
		failures.append("20-tick edit history undo/redo failed")
	elif _simulation_hash(demo) != before_stress_undo:
		failures.append("20-tick edit history did not reproduce original state")
	if demo.domain.nan_events != 0 or demo.domain.clamped_sand_events != 0 or demo.domain.clamped_water_events != 0:
		failures.append("history replay produced nonfinite or clamped state")
	demo.free()
	control.free()
	var rejected_case = scene.instantiate()
	rejected_case._reset_domain(0)
	rejected_case.playing = false
	rejected_case._submit_brush(&"remove_sand", 0.015, Vector3.ZERO, Vector3.ZERO, &"circle")
	rejected_case._step_simulation()
	rejected_case._submit_brush(&"place_sand", 100.0, Vector3.ZERO, Vector3.ZERO, &"circle")
	rejected_case._step_simulation()
	var rejected_hash := _simulation_hash(rejected_case)
	var rejected_ledger: PackedStringArray = rejected_case.audit_recorder.rows.duplicate()
	if rejected_case.attempt_history.size() != 2 or rejected_case.attempt_history[1]["status"] != &"rejected":
		failures.append("rejected tool attempt was not recorded")
	if not rejected_case._undo_command() or rejected_case.attempt_history.size() != 1 or \
			rejected_case.attempt_history[0]["status"] != &"rejected":
		failures.append("undo did not preserve later rejected attempt")
	if not rejected_case._redo_command() or _simulation_hash(rejected_case) != rejected_hash or \
			rejected_case.audit_recorder.rows != rejected_ledger:
		failures.append("redo did not restore applied and rejected attempt ledger")
	rejected_case.free()


func _simulation_hash(demo: Node3D) -> int:
	return hash([demo.domain.sim_tick, demo.domain.rock, demo.domain.sand,
		demo.domain.water, demo.domain.sediment, demo.domain.wetness,
		demo.domain.compaction, demo.domain.tool_inventory_m3,
		demo.domain.water_source_m3, demo.domain.water_sink_m3,
		demo.domain.sand_source_m3, demo.domain.sand_sink_m3,
		demo.water_solver.momentum_x, demo.water_solver.momentum_y,
		demo.tide_time, demo.audit_recorder.rows])


func _press_key(demo: Node3D, key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.pressed = true
	demo._unhandled_input(event)


func _seam_vertices(chunk: MeshInstance3D, vertical: bool) -> Dictionary:
	var seam := {}
	var vertices: PackedVector3Array = chunk.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for vertex in vertices:
		if absf(vertex.x if vertical else vertex.z) < 0.000001:
			seam[vertex] = true
	return seam
