extends Node3D

const GPU_SCENE := preload("res://scenes/gpu_water_preview.tscn")
const CPU_SCENE_PATH := "res://scenes/cpu_reference.tscn"
const CheckpointStore := preload("res://scripts/simulation/checkpoint_store.gd")

var active_scene: Node3D
var gpu_active := true
@export var enable_gpu_erosion := false
## T06 structure layer, forwarded to the GPU preview.
@export var enable_structures := false
## Presentation switches forwarded to the GPU preview for clean recordings.
@export var hide_hud := false
@export var show_brush_indicator := true
@export var use_player_camera := false
@export var player_camera_position := Vector3(-6.0, 3.2, 7.5)
@export var player_camera_target := Vector3(3.0, 0.2, -0.5)
var selected_preset := 0
@onready var mode_label: Label = $Interface/ModeLabel
var staging_scene: Node3D
var staging_redo: Array[Dictionary] = []
var staging_expected_ids := PackedInt32Array()
var staging_expected_tick := -1
var staging_is_load := false
var staging_started_ms := 0
var staging_ready_frames := 0
var history_replay_error := ""
var generation_counter := 0


func _next_generation() -> int:
	if is_instance_valid(active_scene):
		if gpu_active and active_scene.shadow_domain != null:
			generation_counter = maxi(generation_counter,
				active_scene.shadow_domain.generation)
		elif not gpu_active and active_scene.domain != null:
			generation_counter = maxi(generation_counter,
				active_scene.domain.generation)
	generation_counter += 1
	return generation_counter


func _ready() -> void:
	$EditorPreviewController.visible = false
	_set_backend(true)


func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if staging_scene != null:
		if event.keycode in [KEY_F9, KEY_1, KEY_2, KEY_3, KEY_Z, KEY_Y]:
			get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_F9:
		_set_backend(not gpu_active)
		get_viewport().set_input_as_handled()
	elif event.keycode in [KEY_1, KEY_2, KEY_3]:
		selected_preset = event.keycode - KEY_1
		_set_backend(gpu_active)
		get_viewport().set_input_as_handled()
	elif gpu_active and event.keycode in [KEY_Z, KEY_Y] and \
			active_scene != null and not active_scene.playing:
		if event.keycode == KEY_Z:
			if not active_scene._undo_tool_command():
				_start_gpu_history_replay(true)
		else:
			if not active_scene._redo_tool_command():
				_start_gpu_history_replay(false)
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if staging_scene == null:
		return
	if not staging_scene.last_error.is_empty():
		_abort_gpu_history_replay(staging_scene.last_error)
		return
	if Time.get_ticks_msec() - staging_started_ms > 120000:
		_abort_gpu_history_replay("GPU history replay timed out")
		return
	if not staging_scene.replay_ready:
		return
	if staging_scene.completed_ticks != staging_expected_tick or \
			not staging_scene.command_queue.pending.is_empty() or \
			staging_scene.command_queue.applied_log.size() != staging_expected_ids.size():
		_abort_gpu_history_replay("GPU history replay result mismatch")
		return
	for i in staging_expected_ids.size():
		if staging_scene.command_queue.applied_log[i]["command_id"] != staging_expected_ids[i]:
			_abort_gpu_history_replay("GPU history replay command order mismatch")
			return
	var proxy: SandcastleGpuCollisionProxy = staging_scene.collision_proxy
	if proxy.applied_revisions.size() < 64 or not proxy.pending_revisions.is_empty() or \
			not proxy.active_chunks.is_empty():
		return
	staging_ready_frames += 1
	if staging_ready_frames < 3:
		return
	var previous := active_scene
	active_scene = staging_scene
	staging_scene = null
	active_scene.command_queue.redo_stack = staging_redo.duplicate(true)
	if staging_is_load:
		selected_preset = active_scene.preset_index
		enable_gpu_erosion = active_scene.enable_erosion
		active_scene.playing = false
	staging_is_load = false
	active_scene.replay_target_tick = -1
	active_scene.replay_ready = false
	active_scene.checkpoint_interval_ticks = 60
	active_scene.visible = true
	active_scene.get_node("GpuOverviewCamera").current = true
	active_scene.set_process_unhandled_input(true)
	remove_child(previous)
	previous.queue_free()
	mode_label.text = "1/2/3 场景  F9 CPU | 256² GPU 主场景"


func _start_gpu_history_replay(undo: bool) -> bool:
	if not gpu_active or staging_scene != null or active_scene == null or \
			active_scene.playing or active_scene.tick_pending or \
			active_scene.checkpoint_capture_pending or \
			not active_scene.ready_for_ticks or \
			not active_scene.command_queue.pending.is_empty():
		return false
	var commands: Array[Dictionary] = active_scene.command_queue.applied_log.duplicate(true)
	var redo: Array[Dictionary] = active_scene.command_queue.redo_stack.duplicate(true)
	var changed_command: Dictionary
	if undo:
		if commands.is_empty():
			return false
		changed_command = commands.pop_back()
		redo.append(changed_command)
	else:
		if redo.is_empty():
			return false
		changed_command = redo.pop_back()
		commands.append(changed_command)
		commands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if a["sim_tick"] == b["sim_tick"]:
				return a["command_id"] < b["command_id"]
			return a["sim_tick"] < b["sim_tick"])
	staging_expected_ids = PackedInt32Array()
	for command in commands:
		if command["sim_tick"] > active_scene.completed_ticks:
			return false
		staging_expected_ids.append(command["command_id"])
	staging_redo = redo
	staging_expected_tick = active_scene.completed_ticks
	staging_is_load = false
	staging_ready_frames = 0
	history_replay_error = ""
	staging_started_ms = Time.get_ticks_msec()
	staging_scene = GPU_SCENE.instantiate()
	staging_scene.name = "GpuReplayCandidate"
	staging_scene.enable_erosion = active_scene.enable_erosion
	staging_scene.generation = _next_generation()
	staging_scene.preset_index = selected_preset
	var changed_tick: int = changed_command["sim_tick"]
	var chosen_checkpoint: Dictionary = {}
	var retained_checkpoints: Array[Dictionary] = []
	for checkpoint in active_scene.checkpoints:
		if checkpoint.tick >= changed_tick or checkpoint.tick > active_scene.completed_ticks or \
				checkpoint.preset_index != selected_preset:
			continue
		var prefix_valid: bool = checkpoint.command_ids.size() <= commands.size()
		if prefix_valid:
			for i in checkpoint.command_ids.size():
				if checkpoint.command_ids[i] != commands[i]["command_id"]:
					prefix_valid = false
					break
		if prefix_valid and (chosen_checkpoint.is_empty() or checkpoint.tick > chosen_checkpoint.tick):
			chosen_checkpoint = checkpoint
		if prefix_valid:
			retained_checkpoints.append(checkpoint.duplicate(true))
	staging_scene.checkpoints = retained_checkpoints
	if not chosen_checkpoint.is_empty():
		staging_scene.replay_checkpoint = chosen_checkpoint.duplicate(true)
		staging_scene.replay_prefix_commands = commands.slice(0,
			chosen_checkpoint.command_ids.size())
		var tail: Array[Dictionary] = commands.slice(chosen_checkpoint.command_ids.size())
		staging_scene.replay_commands = tail
	else:
		staging_scene.replay_commands = commands
	staging_scene.replay_target_tick = active_scene.completed_ticks
	staging_scene.replay_highwater_id = active_scene.command_id
	staging_scene.replay_wave_requests = active_scene.wave_requests.duplicate(true)
	staging_scene.visible = false
	staging_scene.set_process_unhandled_input(false)
	active_scene.set_process_unhandled_input(false)
	add_child(staging_scene)
	staging_scene.get_node("GpuOverviewCamera").current = false
	active_scene.get_node("GpuOverviewCamera").current = true
	mode_label.text = "GPU 历史重放中…旧场景保持可见"
	return true


func save_active_checkpoint(path: String) -> StringName:
	if not gpu_active or active_scene == null or staging_scene != null:
		return &"save_busy"
	return active_scene.request_checkpoint_save(path)


func load_saved_checkpoint(path: String) -> StringName:
	if not gpu_active or active_scene == null or staging_scene != null or \
			active_scene.playing or active_scene.tick_pending or \
			active_scene.checkpoint_capture_pending or \
			not active_scene.command_queue.pending.is_empty() or \
			not active_scene.ready_for_ticks:
		return &"load_busy"
	var loaded: Dictionary = CheckpointStore.load(path)
	var load_error: StringName = loaded.get("error", &"invalid_checkpoint")
	if not load_error.is_empty():
		return load_error
	var checkpoint: Dictionary = loaded.checkpoint
	staging_expected_tick = checkpoint.tick
	staging_expected_ids = checkpoint.command_ids.duplicate()
	staging_redo = []
	staging_is_load = true
	staging_ready_frames = 0
	history_replay_error = ""
	staging_started_ms = Time.get_ticks_msec()
	staging_scene = GPU_SCENE.instantiate()
	staging_scene.name = "GpuCheckpointCandidate"
	staging_scene.enable_erosion = loaded.enable_erosion
	staging_scene.generation = _next_generation()
	staging_scene.preset_index = checkpoint.preset_index
	staging_scene.replay_checkpoint = checkpoint
	staging_scene.replay_prefix_commands = loaded.prefix_commands
	staging_scene.replay_target_tick = checkpoint.tick
	staging_scene.replay_highwater_id = checkpoint.highwater_id
	staging_scene.visible = false
	staging_scene.set_process_unhandled_input(false)
	active_scene.set_process_unhandled_input(false)
	add_child(staging_scene)
	staging_scene.get_node("GpuOverviewCamera").current = false
	active_scene.get_node("GpuOverviewCamera").current = true
	mode_label.text = "GPU 存档载入中…旧场景保持可见"
	return StringName()


func _abort_gpu_history_replay(message: String) -> void:
	history_replay_error = message
	staging_is_load = false
	remove_child(staging_scene)
	staging_scene.queue_free()
	staging_scene = null
	active_scene.set_process_unhandled_input(true)
	active_scene.get_node("GpuOverviewCamera").current = true
	mode_label.text = "GPU 重放失败，旧状态保留：" + message


func _set_backend(use_gpu: bool) -> void:
	if staging_scene != null:
		return
	# The legacy CPU scene was retired during cleanup. Keep the current GPU
	# scene alive if an old shortcut still requests the removed backend.
	if not use_gpu and not ResourceLoader.exists(CPU_SCENE_PATH):
		mode_label.text = "旧 CPU 参考场景已清理，继续使用 GPU 场景"
		return
	var next_scene: PackedScene = GPU_SCENE if use_gpu else load(CPU_SCENE_PATH)
	if next_scene == null:
		mode_label.text = "目标场景加载失败，当前场景保留"
		return
	var new_generation := _next_generation()
	if active_scene != null:
		remove_child(active_scene)
		active_scene.queue_free()
	gpu_active = use_gpu
	active_scene = next_scene.instantiate()
	active_scene.name = "GpuProduction" if gpu_active else "CpuReference"
	if gpu_active:
		active_scene.preset_index = selected_preset
		active_scene.enable_erosion = enable_gpu_erosion
		active_scene.checkpoint_interval_ticks = 60
		active_scene.generation = new_generation
		active_scene.hide_hud = hide_hud
		active_scene.show_brush_indicator = show_brush_indicator
		active_scene.enable_structures = enable_structures
		active_scene.use_player_camera = use_player_camera
		active_scene.player_camera_position = player_camera_position
		active_scene.player_camera_target = player_camera_target
	add_child(active_scene)
	if not gpu_active and selected_preset != 0:
		active_scene._reset_domain(selected_preset)
	if not gpu_active:
		active_scene.domain.generation = new_generation
	mode_label.visible = not hide_hud
	mode_label.text = "1/2/3 场景  F9 CPU | 256² GPU 主场景" if gpu_active else \
		"1/2/3 场景  F9 GPU | 64² CPU 参考场景"
