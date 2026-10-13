extends Node3D

const Domain = preload("res://scripts/simulation/sand_water_domain.gd")
const ShallowWater = preload("res://scripts/water/reference/shallow_water_solver.gd")
const CommandQueue = preload("res://scripts/sand/tool_command_queue.gd")
const AuditRecorder = preload("res://scripts/audit/audit_recorder.gd")
const Scenarios = preload("res://scripts/scenarios/standard_scenarios.gd")
const GRID_SIZE := 64
const TERRAIN_CHUNK_CELLS := 32
const CELL_SIZE_M := 0.125
const SIM_DELTA := 1.0 / 30.0

var domain: SandWaterDomain
var water_solver: ShallowWater
var command_queue: CommandQueue
var audit_recorder: AuditRecorder
var submitted_commands: Dictionary = {}
var command_history: Array[Dictionary] = []
var redo_history: Array[Dictionary] = []
var attempt_history: Array[Dictionary] = []
var scene_index := 0
var playing := true
var tide_time := 0.0
var accumulator := 0.0
var visual_timer := 0.0
var command_id := 0
var speed_multiplier := 1
var show_flow_arrows := false
var debug_view := 0
var active_brush_kind: StringName = &""
var last_brush_position := Vector3.ZERO
@onready var terrain_chunks: Array[MeshInstance3D] = [
	$SandTerrain_0_0, $SandTerrain_1_0,
	$SandTerrain_0_1, $SandTerrain_1_1,
]
@onready var terrain_mesh: MeshInstance3D = terrain_chunks[0]
@onready var water_mesh: MeshInstance3D = $WaterSurface
@onready var flow_mesh: MeshInstance3D = $FlowArrows
@onready var status_label: Label = $Interface/StatusLabel


func _ready() -> void:
	$EditorPreviewController.visible = false
	_reset_domain(0)
	_update_visuals()


func _process(delta: float) -> void:
	if playing:
		accumulator = minf(accumulator + delta * float(speed_multiplier), SIM_DELTA * 12.0)
		while accumulator >= SIM_DELTA:
			_step_simulation()
			accumulator -= SIM_DELTA
	visual_timer += delta
	if visual_timer >= 0.08:
		_update_visuals()
		visual_timer = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: _reset_domain(0)
			KEY_2: _reset_domain(1)
			KEY_3: _reset_domain(2)
			KEY_SPACE: playing = not playing
			KEY_N:
				if not playing:
					_step_simulation()
					_update_visuals()
			KEY_TAB:
				speed_multiplier = 10 if speed_multiplier == 1 else 1
				_update_visuals()
			KEY_F:
				show_flow_arrows = not show_flow_arrows
				_update_visuals()
			KEY_V:
				debug_view = (debug_view + 1) % 5
				_update_visuals()
			KEY_L:
				var path := "user://sandcastle_tool_ledger.csv"
				var error := audit_recorder.save_csv(path)
				if error == OK:
					print("Saved tool ledger: " + ProjectSettings.globalize_path(path))
				else:
					push_error("tool ledger save failed: %d" % error)
			KEY_R: _reset_domain(scene_index)
			KEY_C: _apply_brush(&"compact", 0.0)
			KEY_Z:
				if not playing and _undo_command():
					_update_visuals()
			KEY_Y:
				if not playing and _redo_command():
					_update_visuals()
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				active_brush_kind = &"remove_sand" if event.button_index == MOUSE_BUTTON_LEFT else &"place_sand"
				var hit = _brush_hit()
				if hit != null:
					last_brush_position = hit
					_submit_brush(active_brush_kind, 0.015, hit, hit, &"circle")
			else:
				active_brush_kind = &""
	if event is InputEventMouseMotion and not active_brush_kind.is_empty():
		var hit = _brush_hit()
		if hit != null:
			var distance_m: float = last_brush_position.distance_to(hit)
			if distance_m >= 0.025:
				_submit_brush(active_brush_kind, maxf(0.0005, distance_m * 0.02),
					last_brush_position, hit, &"swept_segment")
				last_brush_position = hit


func _reset_domain(preset: int) -> void:
	scene_index = preset
	var next_generation := domain.generation + 1 if domain != null else 1
	domain = Domain.new(GRID_SIZE, CELL_SIZE_M)
	domain.generation = next_generation
	water_solver = ShallowWater.new(domain)
	command_queue = CommandQueue.new(domain)
	submitted_commands.clear()
	command_history.clear()
	redo_history.clear()
	attempt_history.clear()
	tide_time = 0.0
	accumulator = 0.0
	command_id = 0
	assert(Scenarios.initialize(domain, preset))
	audit_recorder = AuditRecorder.new(domain)
	_update_visuals()


func _apply_brush(kind: StringName, amount: float) -> void:
	var hit = _brush_hit()
	if hit != null:
		_submit_brush(kind, amount, hit, hit, &"circle")


func _brush_hit():
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null
	var cursor := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(cursor)
	var ray_direction := camera.project_ray_normal(cursor)
	return Plane(Vector3.UP, 0.0).intersects_ray(ray_origin, ray_direction)


func _submit_brush(kind: StringName, amount: float, start: Vector3,
		end: Vector3, shape: StringName) -> void:
	command_id += 1
	var transform := {"position_m": start}
	if shape == &"swept_segment":
		transform["end_position_m"] = end
	var command := {
		"domain_id": domain.domain_id, "generation": domain.generation,
		"sim_tick": domain.sim_tick,
		"command_id": command_id, "kind": kind, "shape": shape,
		"transform": transform, "radius_m": 0.38,
		"strength": 1.0, "amount_m3": amount, "seed": command_id
	}
	var error: StringName = command_queue.submit(command)
	if error.is_empty():
		submitted_commands[command_id] = command
		redo_history.clear()
	if error.is_empty() and not playing:
		_apply_due_commands()
		_update_visuals()


func _step_simulation() -> void:
	_apply_due_commands()
	var tide_level := Scenarios.tide_level(tide_time)
	water_solver.set_tide_boundary(tide_level)
	water_solver.step(SIM_DELTA)
	if water_solver.overload_events > 0:
		playing = false
		push_error("shallow-water solver overloaded at tick %d" % domain.sim_tick)
		return
	domain.step_post_water(SIM_DELTA)
	domain._audit_finite()
	if domain.sim_tick % 12 == 0:
		domain.relax_slopes(0.12, 0.08)
	tide_time += SIM_DELTA


func _apply_due_commands() -> void:
	for result in command_queue.apply_due_commands(domain.sim_tick):
		var id: int = result["command_id"]
		var command: Dictionary = submitted_commands.get(id, {})
		if not command.is_empty():
			audit_recorder.record_tool(command, result, domain)
			attempt_history.append({"command": command.duplicate(true), "status": result["status"]})
			if result["status"] == &"applied":
				command_history.append(command.duplicate(true))
			submitted_commands.erase(id)


func _undo_command() -> bool:
	if command_history.is_empty() or not submitted_commands.is_empty():
		return false
	var command: Dictionary = command_history.back()
	if command["sim_tick"] == domain.sim_tick and not attempt_history.is_empty() and \
			attempt_history.back()["command"]["command_id"] == command["command_id"]:
		if not command_queue.undo_last():
			return false
		command_history.pop_back()
		attempt_history.pop_back()
		redo_history.append(command)
		if audit_recorder.rows.size() > 1:
			audit_recorder.rows.remove_at(audit_recorder.rows.size() - 1)
		return true
	var kept := attempt_history.duplicate(true)
	for i in range(kept.size() - 1, -1, -1):
		if kept[i]["command"]["command_id"] == command["command_id"]:
			kept.remove_at(i)
			break
	if not _replay_to_current_tick(kept):
		return false
	redo_history.append(command)
	return true


func _redo_command() -> bool:
	if redo_history.is_empty() or not submitted_commands.is_empty():
		return false
	var command: Dictionary = redo_history.back()
	if command["sim_tick"] == domain.sim_tick and not command_queue.redo_stack.is_empty():
		var inventory_before := domain.tool_inventory_m3
		if not command_queue.redo_last():
			return false
		redo_history.pop_back()
		command_history.append(command)
		attempt_history.append({"command": command.duplicate(true), "status": &"applied"})
		audit_recorder.record_tool(command, {"status": &"applied",
			"sand_delta_m3": domain.tool_inventory_m3 - inventory_before}, domain)
		return true
	var replayed := attempt_history.duplicate(true)
	replayed.append({"command": command.duplicate(true), "status": &"applied"})
	replayed.sort_custom(_before_attempt)
	if not _replay_to_current_tick(replayed):
		return false
	redo_history.pop_back()
	return true


func _replay_to_current_tick(events: Array[Dictionary]) -> bool:
	# Build the entire replacement off-scene. A failed replay must not mutate the
	# live water, momentum, source/sink ledger, or user-visible terrain.
	var target_tick := domain.sim_tick
	var next_generation := domain.generation + 1
	var old_command_id := command_id
	var replacement: Node3D = get_script().new()
	replacement._reset_domain(scene_index)
	for event in events:
		var command: Dictionary = event["command"]
		var replay_command := command.duplicate(true)
		replay_command["generation"] = replacement.domain.generation
		var error: StringName = replacement.command_queue.submit(replay_command)
		if not error.is_empty():
			replacement.free()
			return false
		replacement.submitted_commands[command["command_id"]] = replay_command
	for tick in target_tick:
		replacement._step_simulation()
		if replacement.domain.sim_tick != tick + 1:
			replacement.free()
			return false
	replacement._apply_due_commands()
	if replacement.attempt_history.size() != events.size() or not replacement.submitted_commands.is_empty():
		replacement.free()
		return false
	for i in events.size():
		if replacement.attempt_history[i]["status"] != events[i]["status"] or \
				replacement.attempt_history[i]["command"]["command_id"] != events[i]["command"]["command_id"]:
			replacement.free()
			return false
	domain = replacement.domain
	domain.generation = next_generation
	water_solver = replacement.water_solver
	command_queue = replacement.command_queue
	audit_recorder = replacement.audit_recorder
	submitted_commands = replacement.submitted_commands
	command_history = replacement.command_history
	attempt_history = replacement.attempt_history
	tide_time = replacement.tide_time
	command_id = old_command_id
	command_queue.last_command_id = maxi(command_queue.last_command_id, command_id)
	accumulator = 0.0
	replacement.free()
	return true


func _before_attempt(a: Dictionary, b: Dictionary) -> bool:
	var left: Dictionary = a["command"]
	var right: Dictionary = b["command"]
	if left["sim_tick"] == right["sim_tick"]:
		return left["command_id"] < right["command_id"]
	return left["sim_tick"] < right["sim_tick"]


func _update_visuals() -> void:
	if domain == null or terrain_mesh == null:
		return
	var terrain_vertices_by_chunk: Array = []
	var terrain_colors_by_chunk: Array = []
	for _chunk in 4:
		terrain_vertices_by_chunk.append(PackedVector3Array())
		terrain_colors_by_chunk.append(PackedColorArray())
	var water_vertices := PackedVector3Array()
	var water_colors := PackedColorArray()
	var half_extent := GRID_SIZE * CELL_SIZE_M * 0.5
	for y in GRID_SIZE - 1:
		for x in GRID_SIZE - 1:
			var chunk_id := (y / TERRAIN_CHUNK_CELLS) * 2 + x / TERRAIN_CHUNK_CELLS
			var terrain_vertices: PackedVector3Array = terrain_vertices_by_chunk[chunk_id]
			var terrain_colors: PackedColorArray = terrain_colors_by_chunk[chunk_id]
			var ids := [domain.index(x, y), domain.index(x + 1, y),
				domain.index(x + 1, y + 1), domain.index(x, y + 1)]
			var corners := PackedVector3Array()
			var water_corners := PackedVector3Array()
			var colors := PackedColorArray()
			var wet_values := PackedColorArray()
			for corner in 4:
				var px := x + (1 if corner == 1 or corner == 2 else 0)
				var py := y + (1 if corner >= 2 else 0)
				var i: int = ids[corner]
				var bed: float = domain.bed_at(i)
				corners.append(Vector3(px * CELL_SIZE_M - half_extent, bed, py * CELL_SIZE_M - half_extent))
				water_corners.append(Vector3(px * CELL_SIZE_M - half_extent, bed + domain.water[i] + 0.006, py * CELL_SIZE_M - half_extent))
				colors.append(_terrain_color(i, px, py))
				wet_values.append(Color(0.07, 0.47, 0.64, 0.72))
			for corner in [0, 2, 1, 0, 3, 2]:
				terrain_vertices.append(corners[corner])
				terrain_colors.append(colors[corner])
			terrain_vertices_by_chunk[chunk_id] = terrain_vertices
			terrain_colors_by_chunk[chunk_id] = terrain_colors
			var wet_count := 0
			for i in ids:
				if domain.water[i] > 0.006:
					wet_count += 1
			if wet_count >= 2:
				for corner in [0, 2, 1, 0, 3, 2]:
					water_vertices.append(water_corners[corner])
					water_colors.append(wet_values[corner])
	for chunk_id in terrain_chunks.size():
		terrain_chunks[chunk_id].mesh = _array_mesh(
			terrain_vertices_by_chunk[chunk_id], terrain_colors_by_chunk[chunk_id])
	water_mesh.mesh = _array_mesh(water_vertices, water_colors)
	_update_flow_arrows()
	var names := ["斜坡海岸", "弯沟与洼地", "沙墙与两塔"]
	var debug_names := ["常规", "高度", "坡度", "沙厚", "压实"]
	status_label.text = "水沙耦合 CPU 参考场景  |  %s  |  %s\n左键拖动挖沙  右键拖动堆沙  C 拍实  1/2/3 场景  空格暂停  N 单步  Tab 1×/10×  F 流量箭头  V 调试图  L 导出账本  Z 撤销  Y 重做  R 重置\n水 %.3f m³  沙 %.3f m³  桶 %.3f m³  Tick %d  %s  %d×" % [
		names[scene_index], debug_names[debug_view], domain.total_water_m3(), domain.total_sand_m3(false),
		domain.tool_inventory_m3, domain.sim_tick, "运行" if playing else "暂停", speed_multiplier]


func _terrain_color(i: int, x: int, y: int) -> Color:
	match debug_view:
		1:
			var height_ratio := clampf((domain.bed_at(i) + 0.3) / 1.2, 0.0, 1.0)
			return Color(0.08, 0.2, 0.75).lerp(Color(1.0, 0.9, 0.2), height_ratio)
		2:
			var left := domain.bed_at(domain.index(maxi(0, x - 1), y))
			var right := domain.bed_at(domain.index(mini(GRID_SIZE - 1, x + 1), y))
			var up := domain.bed_at(domain.index(x, maxi(0, y - 1)))
			var down := domain.bed_at(domain.index(x, mini(GRID_SIZE - 1, y + 1)))
			var slope := Vector2(right - left, down - up).length() / (2.0 * CELL_SIZE_M)
			return Color(0.1, 0.55, 0.18).lerp(Color(0.95, 0.1, 0.08), clampf(slope, 0.0, 1.0))
		3:
			return Color(0.15, 0.1, 0.05).lerp(Color(1.0, 0.86, 0.38), clampf(domain.sand[i], 0.0, 1.0))
		4:
			return Color(0.12, 0.08, 0.25).lerp(Color(0.9, 0.4, 0.98), domain.compaction[i])
		_:
			return Color(0.87, 0.72, 0.46).lerp(Color(0.48, 0.37, 0.26), domain.wetness[i] * 0.6)


func _update_flow_arrows() -> void:
	if flow_mesh == null:
		return
	if not show_flow_arrows:
		flow_mesh.mesh = ArrayMesh.new()
		return
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var half_extent := GRID_SIZE * CELL_SIZE_M * 0.5
	for y in range(2, GRID_SIZE - 2, 4):
		for x in range(2, GRID_SIZE - 2, 4):
			var i: int = domain.index(x, y)
			if domain.water[i] <= 0.002:
				continue
			var direction := Vector2(domain.flux_right[i] - domain.flux_left[i],
				domain.flux_down[i] - domain.flux_up[i])
			if direction.length() < 0.000001:
				continue
			var length_m := clampf(direction.length() * 40.0, 0.04, 0.24)
			var unit := direction.normalized()
			var start := Vector3((x + 0.5) * CELL_SIZE_M - half_extent,
				domain.surface_at(i) + 0.025, (y + 0.5) * CELL_SIZE_M - half_extent)
			var end := start + Vector3(unit.x, 0.0, unit.y) * length_m
			var wing := Vector2(-unit.y, unit.x)
			for segment in [[start, end],
					[end, end - Vector3(unit.x + wing.x, 0.0, unit.y + wing.y) * length_m * 0.25],
					[end, end - Vector3(unit.x - wing.x, 0.0, unit.y - wing.y) * length_m * 0.25]]:
				vertices.append(segment[0])
				vertices.append(segment[1])
				colors.append(Color(0.9, 0.12, 0.08))
				colors.append(Color(0.9, 0.12, 0.08))
	var result := ArrayMesh.new()
	if not vertices.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_COLOR] = colors
		result.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	flow_mesh.mesh = result


func _array_mesh(vertices: PackedVector3Array, colors: PackedColorArray) -> ArrayMesh:
	var result := ArrayMesh.new()
	if vertices.is_empty():
		return result
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result
