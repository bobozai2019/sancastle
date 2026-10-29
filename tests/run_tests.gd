extends SceneTree

const Domain = preload("res://scripts/simulation/sand_water_domain.gd")
const ShallowWater = preload("res://scripts/water/reference/shallow_water_solver.gd")
const CommandQueue = preload("res://scripts/sand/tool_command_queue.gd")
const AuditRecorder = preload("res://scripts/audit/audit_recorder.gd")

var failures: Array[String] = []


func _init() -> void:
	_test_tool_conservation()
	_test_closed_water_conservation()
	_test_uneven_bed_still_water()
	_test_erosion_conservation()
	_test_sediment_advection()
	_test_slope_relaxation()
	_test_snapshot_roundtrip()
	_test_shallow_water_still_lake()
	_test_shallow_water_dam_break()
	_test_shallow_water_wall()
	_test_ordered_tool_commands_and_undo()
	_test_hundred_digs_and_cubic_metre_transfer()
	_test_three_seed_replays()
	_test_swept_segment_continuity_and_volume()
	_test_tool_audit_ledger()
	_test_smooth_and_compact_commands()
	_test_replay_file_roundtrip()
	if failures.is_empty():
		print("PASS: 17 simulation contract tests")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("FAIL: %d test(s)" % failures.size())
		quit(1)


func _assert_close(actual: float, expected: float, tolerance: float, label: String) -> void:
	if absf(actual - expected) > tolerance:
		failures.append("%s: expected %.8f, got %.8f (tol %.8f)" % [label, expected, actual, tolerance])


func _assert_true(value: bool, label: String) -> void:
	if not value:
		failures.append(label)


func _command(kind: StringName, amount: float = 0.0) -> Dictionary:
	return {"command_id": 1, "kind": kind, "position_m": Vector3.ZERO,
		"radius_m": 0.5, "strength": 1.0, "amount_m3": amount, "seed": 7}


func _test_tool_conservation() -> void:
	var domain = Domain.new(16, 0.125)
	domain.sand.fill(1.0)
	var before: float = domain.total_sand_m3()
	var removed: Dictionary = domain.apply_tool(_command(&"remove_sand", 0.1))
	_assert_true(removed.status == &"applied", "remove command should apply")
	_assert_close(domain.total_sand_m3(), before, 0.00001, "sand conserved into tool inventory")
	var placed_command := _command(&"place_sand", 0.1)
	placed_command.command_id = 2
	var placed: Dictionary = domain.apply_tool(placed_command)
	_assert_true(placed.status == &"applied", "place command should apply")
	_assert_close(domain.total_sand_m3(), before, 0.00001, "sand conserved after place")


func _test_closed_water_conservation() -> void:
	var domain = Domain.new(20, 0.125)
	domain.rock.fill(0.0)
	domain.sand.fill(0.1)
	domain.water.fill(0.0)
	domain.water[domain.index(10, 10)] = 1.0
	var before: float = domain.total_water_m3()
	for _step in 300:
		domain.step_water(1.0 / 60.0)
	_assert_close(domain.total_water_m3(), before, 0.00001, "closed water conservation")
	var minimum := INF
	for value in domain.water:
		minimum = minf(minimum, value)
	_assert_true(minimum >= 0.0, "water must stay non-negative")


func _test_uneven_bed_still_water() -> void:
	var domain = Domain.new(12, 0.125)
	for y in domain.grid_size:
		for x in domain.grid_size:
			var i: int = domain.index(x, y)
			domain.rock[i] = float(x) * 0.01
			domain.sand[i] = 0.2
			domain.water[i] = 0.5 - domain.bed_at(i)
	var before: PackedFloat32Array = domain.water.duplicate()
	for _step in 60:
		domain.step_water(1.0 / 60.0)
	var max_difference := 0.0
	for i in domain.water.size():
		max_difference = maxf(max_difference, absf(domain.water[i] - before[i]))
	_assert_true(max_difference < 0.00001, "uneven-bed still water drifted: %f" % max_difference)


func _test_erosion_conservation() -> void:
	var domain = Domain.new(10, 0.125)
	domain.sand.fill(0.5)
	domain.water.fill(0.1)
	domain.flux_right.fill(0.3)
	var before: float = domain.total_sand_m3(false)
	for _step in 120:
		domain.step_erosion(1.0 / 60.0)
	_assert_close(domain.total_sand_m3(false), before, 0.00001, "erosion phase conservation")


func _test_sediment_advection() -> void:
	var domain = Domain.new(10, 0.125)
	domain.water.fill(0.1)
	domain.sediment[domain.index(3, 5)] = 0.05
	domain.water[domain.index(3, 5)] = 0.4
	var before: float = domain.total_sand_m3(false)
	for _step in 20:
		domain.step_water(1.0 / 60.0)
	_assert_close(domain.total_sand_m3(false), before, 0.00001, "advected sediment conservation")
	_assert_true(domain.sediment[domain.index(4, 5)] > 0.0,
		"sediment must move downstream with the water flux")
	var minimum := INF
	for value in domain.sediment:
		minimum = minf(minimum, value)
	_assert_true(minimum >= 0.0, "sediment must stay non-negative")


func _test_slope_relaxation() -> void:
	var domain = Domain.new(8, 0.125)
	domain.sand.fill(0.0)
	domain.sand[domain.index(4, 4)] = 2.0
	var before: float = domain.total_sand_m3(false)
	for _step in 20:
		domain.relax_slopes()
	_assert_close(domain.total_sand_m3(false), before, 0.00001, "slope relaxation conservation")
	_assert_true(domain.sand[domain.index(4, 4)] < 2.0, "slope peak should relax")


func _test_snapshot_roundtrip() -> void:
	var domain = Domain.new(8, 0.125)
	domain.initialize_beach(99)
	domain.tool_inventory_m3 = 0.25
	var expected: float = domain.total_sand_m3()
	var data: Dictionary = domain.snapshot()
	domain.sand.fill(0.0)
	_assert_true(domain.restore(data), "snapshot should restore")
	_assert_close(domain.total_sand_m3(), expected, 0.00001, "snapshot sand total")
	_assert_true(domain.generation == 2, "restore should advance generation")


func _test_shallow_water_still_lake() -> void:
	var domain = Domain.new(12, 0.125)
	for y in domain.grid_size:
		for x in domain.grid_size:
			var i: int = domain.index(x, y)
			domain.rock[i] = 0.02 * float(x) + 0.004 * float(y)
			domain.water[i] = 0.5 - domain.bed_at(i)
	var solver = ShallowWater.new(domain)
	var before: float = domain.total_water_m3()
	var initial: PackedFloat32Array = domain.water.duplicate()
	for _step in 120:
		solver.step(1.0 / 60.0)
	_assert_close(domain.total_water_m3(), before, 0.00001, "shallow lake mass")
	var max_difference := 0.0
	for i in domain.water.size():
		max_difference = maxf(max_difference, absf(domain.water[i] - initial[i]))
	_assert_true(max_difference < 0.0001, "shallow uneven-bed lake drift: %f" % max_difference)
	_assert_true(solver.negative_depth_events == 0, "shallow lake negative depth")


func _test_shallow_water_dam_break() -> void:
	var domain = Domain.new(20, 0.125)
	for y in domain.grid_size:
		for x in domain.grid_size:
			domain.water[domain.index(x, y)] = 0.4 if x < 10 else 0.0
	var solver = ShallowWater.new(domain)
	var before: float = domain.total_water_m3()
	for _step in 90:
		solver.step(1.0 / 120.0)
	_assert_close(domain.total_water_m3(), before, 0.00001, "shallow dam-break mass")
	_assert_true(domain.water[domain.index(13, 10)] > 0.0, "dam front should propagate")
	_assert_true(solver.negative_depth_events == 0, "dam break negative depth")


func _test_shallow_water_wall() -> void:
	var domain = Domain.new(20, 0.125)
	for y in domain.grid_size:
		for x in domain.grid_size:
			var i: int = domain.index(x, y)
			if x < 9:
				domain.water[i] = 0.35
			if x == 9:
				domain.obstacle[i] = 1.0
	var solver = ShallowWater.new(domain)
	var before: float = domain.total_water_m3()
	for _step in 90:
		solver.step(1.0 / 120.0)
	_assert_close(domain.total_water_m3(), before, 0.00001, "shallow wall mass")
	_assert_close(domain.water[domain.index(12, 10)], 0.0, 0.00001, "wall must block water")
	_assert_true(solver.negative_depth_events == 0, "wall negative depth")
	var coast = Domain.new(8, 0.125)
	coast.water.fill(0.1)
	var coast_solver = ShallowWater.new(coast)
	coast_solver.momentum_x[coast.index(0, 3)] = 0.7
	coast_solver.momentum_x[coast.index(7, 3)] = 0.4
	coast_solver.set_tide_boundary(0.2)
	_assert_close(coast.water[coast.index(0, 3)], 0.2, 0.000001,
		"x=0 open sea uses prescribed level")
	_assert_close(coast.water[coast.index(7, 3)], 0.1, 0.000001,
		"opposite coast remains closed")
	_assert_close(coast_solver.momentum_x[coast.index(0, 3)], 0.0, 0.000001,
		"open-sea reservoir resets momentum")
	_assert_close(coast_solver.momentum_x[coast.index(7, 3)], 0.4, 0.000001,
		"closed coast momentum is not reset as reservoir")


func _test_ordered_tool_commands_and_undo() -> void:
	var domain = Domain.new(16, 0.125)
	domain.sand.fill(0.8)
	var queue = CommandQueue.new(domain)
	var initial: float = domain.total_sand_m3()
	var remove_command := {"domain_id": &"main_beach", "sim_tick": 0,
		"command_id": 1, "kind": &"remove_sand", "shape": &"circle",
		"transform": {"position_m": Vector3.ZERO}, "radius_m": 0.4,
		"strength": 1.0, "amount_m3": 0.04, "seed": 17}
	var place_command: Dictionary = remove_command.duplicate(true)
	place_command.command_id = 2
	place_command.kind = &"place_sand"
	place_command.sim_tick = 1
	var invalid_kind: Dictionary = remove_command.duplicate(true)
	invalid_kind.kind = &"unknown_tool"
	_assert_true(queue.submit(invalid_kind) == &"invalid_command", "queue rejects unknown kind before apply")
	var stale_generation: Dictionary = remove_command.duplicate(true)
	stale_generation.generation = domain.generation + 1
	_assert_true(queue.submit(stale_generation) == &"inactive_generation", "queue rejects stale generation")
	_assert_true(queue.submit(remove_command).is_empty(), "queue accepts removal")
	_assert_true(queue.submit(place_command).is_empty(), "queue accepts placement")
	var first_results: Array[Dictionary] = queue.apply_due_commands(0)
	_assert_true(first_results.size() == 1, "tick 0 applies one command")
	if first_results.size() == 1:
		_assert_true(first_results[0]["status"] == &"applied" and first_results[0]["applied_tick"] == 0,
			"command result reports applied tick")
		_assert_true(first_results[0].has("dirty_chunks") and first_results[0]["dirty_chunks"].size() > 0,
			"command result reports dirty chunks")
	var removed_state: PackedFloat32Array = domain.sand.duplicate()
	domain.sim_tick = 1
	_assert_true(queue.submit(remove_command) == &"stale_tick", "queue rejects a past tick")
	_assert_true(queue.apply_due_commands(1).size() == 1, "tick 1 applies one command")
	var placed_state: PackedFloat32Array = domain.sand.duplicate()
	_assert_close(domain.total_sand_m3(), initial, 0.00001, "queued tool conservation")
	_assert_true(queue.undo_last(), "last tool command can be undone")
	for i in domain.sand.size():
		if absf(domain.sand[i] - removed_state[i]) > 0.00001:
			failures.append("undo did not restore sand state")
			break
	_assert_close(domain.total_sand_m3(), initial, 0.00001, "undo tool conservation")
	_assert_true(queue.redo_last(), "last tool command can be redone")
	for i in domain.sand.size():
		if absf(domain.sand[i] - placed_state[i]) > 0.00001:
			failures.append("redo did not restore applied sand state")
			break
	_assert_close(domain.total_sand_m3(), initial, 0.00001, "redo tool conservation")


func _test_hundred_digs_and_cubic_metre_transfer() -> void:
	var domain = Domain.new(32, 0.125)
	domain.rock.fill(-0.4)
	domain.sand.fill(1.2)
	var initial: float = domain.total_sand_m3()
	for n in 100:
		var x := float(n % 10) * 0.3 - 1.35
		var z := float(n / 10) * 0.3 - 1.35
		var command := _command(&"remove_sand", 0.01)
		command.command_id = n + 1
		command.position_m = Vector3(x, 0.0, z)
		var result: Dictionary = domain.apply_tool(command)
		_assert_true(result.status == &"applied", "dig %d should apply" % n)
		for i in domain.sand.size():
			if domain.sand[i] < -0.000001 or domain.bed_at(i) < domain.rock[i] - 0.000001:
				failures.append("dig %d penetrated rock or produced negative sand" % n)
				return
	_assert_close(domain.tool_inventory_m3, 1.0, 0.005, "100 digs move 1 m³ within 0.5%")
	_assert_close(domain.total_sand_m3(), initial, 0.0001, "100 digs conserve total sand")
	var place := _command(&"place_sand", 1.0)
	place.command_id = 101
	place.radius_m = 1.0
	var placed: Dictionary = domain.apply_tool(place)
	_assert_true(placed.status == &"applied", "1 m³ placement applies")
	_assert_close(domain.tool_inventory_m3, 0.0, 0.005, "1 m³ placement drains bucket within 0.5%")
	_assert_close(domain.total_sand_m3(), initial, 0.0001, "1 m³ transfer conserves sand")
	_assert_true(domain.nan_events == 0, "100 digs have no NaN")


func _test_three_seed_replays() -> void:
	for replay_seed in [11, 29, 47]:
		var expected := 0
		for repetition in 2:
			var domain = Domain.new(24, 0.125)
			domain.initialize_beach(replay_seed)
			var queue = CommandQueue.new(domain)
			for n in 20:
				var command := {"domain_id": &"main_beach", "sim_tick": n,
					"command_id": n + 1, "kind": &"remove_sand" if n % 2 == 0 else &"place_sand",
					"shape": &"circle", "transform": {"position_m": Vector3(float(n % 4) * 0.3 - 0.45, 0.0, float(n % 5) * 0.25 - 0.5)},
					"radius_m": 0.35, "strength": 1.0, "amount_m3": 0.003,
					"seed": replay_seed + n}
				_assert_true(queue.submit(command).is_empty(), "replay command %d accepted" % n)
				queue.apply_due_commands(n)
				domain.step(1.0 / 30.0)
			var state_hash := hash([domain.rock, domain.sand, domain.water,
				domain.sediment, domain.wetness, domain.compaction, domain.tool_inventory_m3])
			if repetition == 0:
				expected = state_hash
			else:
				_assert_true(state_hash == expected, "seed %d replay must match" % replay_seed)


func _test_swept_segment_continuity_and_volume() -> void:
	var domain = Domain.new(32, 0.125)
	domain.sand.fill(1.0)
	var queue = CommandQueue.new(domain)
	var initial: float = domain.total_sand_m3()
	var stroke := {"domain_id": &"main_beach", "sim_tick": 0,
		"command_id": 1, "kind": &"remove_sand", "shape": &"swept_segment",
		"transform": {"position_m": Vector3(-1.0, 0.0, 0.0),
			"end_position_m": Vector3(1.0, 0.0, 0.0)},
		"radius_m": 0.18, "strength": 1.0, "amount_m3": 0.2, "seed": 23}
	_assert_true(queue.submit(stroke).is_empty(), "swept segment accepted")
	var results: Array[Dictionary] = queue.apply_due_commands(0)
	_assert_true(results.size() == 1 and results[0].status == &"applied", "swept segment applies")
	for x in range(8, 24):
		if domain.sand[domain.index(x, 15)] >= 1.0 and domain.sand[domain.index(x, 16)] >= 1.0:
			failures.append("swept segment skipped cell column %d" % x)
	_assert_close(domain.tool_inventory_m3, 0.2, 0.00001, "swept amount charged once")
	_assert_close(domain.total_sand_m3(), initial, 0.00001, "swept segment sand conservation")


func _test_tool_audit_ledger() -> void:
	var domain = Domain.new(16, 0.125)
	domain.sand.fill(1.0)
	var initial: float = domain.total_sand_m3()
	var recorder = AuditRecorder.new(domain)
	var commands := [
		_command(&"remove_sand", 0.1),
		_command(&"place_sand", 0.1),
		_command(&"debug_add_sand", 0.05)]
	for n in commands.size():
		var command: Dictionary = commands[n]
		command.command_id = n + 1
		var result: Dictionary = domain.apply_tool(command)
		_assert_true(result.status == &"applied", "ledger command %d applies" % n)
		_assert_true(result.has("dirty_chunks"), "command result includes dirty chunks")
		recorder.record_tool(command, result, domain)
	_assert_close(domain.total_sand_m3(), initial + 0.05, 0.00001, "ledger external source closure")
	var path := "res://test_output/sandcastle_water_sand_coupling/验收/T01_tool_ledger.csv"
	_assert_true(recorder.save_csv(path) == OK, "tool ledger CSV saves")
	var contents := FileAccess.get_file_as_string(path)
	_assert_true(contents.contains("terrain_and_sediment_m3") and contents.split("\n").size() >= 4,
		"tool ledger CSV contains header and commands")


func _test_smooth_and_compact_commands() -> void:
	var domain = Domain.new(16, 0.125)
	domain.sand.fill(0.5)
	domain.sand[domain.index(8, 8)] = 1.0
	var initial: float = domain.total_sand_m3()
	var peak_before: float = domain.sand[domain.index(8, 8)]
	var smooth := _command(&"smooth")
	var smoothed: Dictionary = domain.apply_tool(smooth)
	_assert_true(smoothed.status == &"applied", "smooth command applies")
	_assert_true(domain.sand[domain.index(8, 8)] < peak_before, "smooth lowers local peak")
	_assert_close(domain.total_sand_m3(), initial, 0.00001, "smooth preserves reference sand volume")
	var compact := _command(&"compact")
	compact.command_id = 2
	var bed_before: float = domain.bed_at(domain.index(8, 8))
	var compacted: Dictionary = domain.apply_tool(compact)
	_assert_true(compacted.status == &"applied", "compact command applies")
	_assert_true(domain.compaction[domain.index(8, 8)] > 0.0, "compact raises compaction")
	_assert_close(domain.bed_at(domain.index(8, 8)), bed_before, 0.000001,
		"S1-S4 compaction does not change bed without volume remapping")
	_assert_close(domain.total_sand_m3(), initial, 0.00001, "compact preserves reference sand volume")


func _test_replay_file_roundtrip() -> void:
	var source = Domain.new(24, 0.125)
	source.initialize_beach(123)
	var queue = CommandQueue.new(source)
	var commands := [
		{"domain_id": &"main_beach", "sim_tick": 0, "command_id": 1,
			"kind": &"remove_sand", "shape": &"swept_segment",
			"transform": {"position_m": Vector3(-0.8, 0.0, 0.0),
				"end_position_m": Vector3(0.8, 0.0, 0.0)},
			"radius_m": 0.2, "strength": 1.0, "amount_m3": 0.02, "seed": 123},
		{"domain_id": &"main_beach", "sim_tick": 2, "command_id": 2,
			"kind": &"place_sand", "shape": &"circle",
			"transform": {"position_m": Vector3(0.0, 0.0, 0.4)},
			"radius_m": 0.3, "strength": 1.0, "amount_m3": 0.01, "seed": 124}]
	for command in commands:
		_assert_true(queue.submit(command).is_empty(), "replay source command accepted")
	for _tick in 5:
		queue.apply_due_commands(source.sim_tick)
		source.step(1.0 / 30.0)
	var path := "res://test_output/sandcastle_water_sand_coupling/验收/T01_replay_fixture.json"
	_assert_true(queue.save_replay(path) == OK, "replay JSON saves")
	var target = Domain.new(24, 0.125)
	target.initialize_beach(123)
	var restored = CommandQueue.new(target)
	_assert_true(restored.load_replay(path).is_empty(), "replay JSON loads")
	for _tick in 5:
		restored.apply_due_commands(target.sim_tick)
		target.step(1.0 / 30.0)
	_assert_true(hash([source.sand, source.water, source.sediment, source.wetness,
		source.compaction, source.tool_inventory_m3]) ==
		hash([target.sand, target.water, target.sediment, target.wetness,
		target.compaction, target.tool_inventory_m3]), "replay file reproduces CPU state")
	var wrong_domain = Domain.new(32, 0.125)
	var wrong_queue = CommandQueue.new(wrong_domain)
	_assert_true(wrong_queue.load_replay(path) == &"out_of_domain", "replay rejects wrong grid")
