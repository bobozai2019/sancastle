extends Node

signal status_changed
signal switched(key: String)
const SCENES := {
	"main": "res://scenes/main.tscn",
	"test1_capture": "res://scenes/playable/test1_capture.tscn",
	"test1_backwash": "res://scenes/playable/test1_backwash.tscn",
}
var active_scene: Node3D
var busy := false
var message := "切换保留各场景进度"
var last_error := ""
var saved := {}
var shared_controls := {}
var generation_highwater := 1
var serial := 0
var session_directory := ""
var inject_target_failure_once := false

func attach(scene: Node3D) -> void:
	if busy:
		return
	active_scene = scene
	generation_highwater = maxi(generation_highwater, scene.generation)

func request_switch(key: String) -> bool:
	if busy or not SCENES.has(key) or not is_instance_valid(active_scene) or not active_scene.ready_for_ticks:
		return false
	if active_scene.scene_key == key:
		return true
	busy = true
	last_error = ""
	_set_message("正在保存当前场景…")
	call_deferred("_switch", key)
	return true

func _set_message(value: String) -> void:
	message = value
	status_changed.emit()

func _settings(scene) -> Dictionary:
	return {"playing": scene.playing, "hide_hud": scene.hide_hud,
		"selected_sand_tool": scene.selected_sand_tool,
		"dig_amount_m3": scene.dig_amount_m3, "fill_amount_m3": scene.fill_amount_m3,
		"manual_wave_amplitude_m": scene.manual_wave_amplitude_m,
		"sampling": scene.get_node("Interface/PerformancePanel/Margin/Rows/Header/Sampling").button_pressed,
		"camera": scene.player_camera.transform, "use_player_camera": scene.use_player_camera}

func _apply_settings(scene, settings: Dictionary) -> void:
	for key in ["dig_amount_m3", "fill_amount_m3", "manual_wave_amplitude_m", "selected_sand_tool", "hide_hud"]:
		if shared_controls.has(key):
			scene.set(key, shared_controls[key])
	var controls: Node = scene.get_node("Interface/EditPanel/Margin/Controls")
	controls.get_node("DigAmount").value = scene.dig_amount_m3
	controls.get_node("FillAmount").value = scene.fill_amount_m3
	controls.get_node("WaveAmount").value = scene.manual_wave_amplitude_m
	controls.get_node("Tools/DigTool").button_pressed = scene.selected_sand_tool == &"remove_sand"
	controls.get_node("Tools/FillTool").button_pressed = scene.selected_sand_tool == &"place_sand"
	scene.get_node("Interface/PerformancePanel/Margin/Rows/Header/Sampling").button_pressed = shared_controls.get("sampling", true)
	if settings.has("camera"):
		scene.player_camera.transform = settings.camera
	scene.set_player_camera(settings.get("use_player_camera", true))
	scene.playing = settings.get("playing", true)
	scene._update_status()

func _prepare(scene, key: String, settings: Dictionary) -> String:
	generation_highwater += 2
	scene.generation = generation_highwater
	scene.playing = false
	get_tree().root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 90000
	while not scene.ready_for_ticks and scene.last_error.is_empty() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if not scene.ready_for_ticks or not scene.last_error.is_empty():
		return "场景初始化失败：" + scene.last_error
	if saved.has(key):
		var error: StringName = await scene.restore_gpu_checkpoint(saved[key].path)
		if not error.is_empty():
			return "恢复失败：" + String(error)
	_apply_settings(scene, settings)
	return ""

func _switch(key: String) -> void:
	var packed: PackedScene = load(SCENES[key])
	if packed == null:
		_finish("场景资源加载失败")
		return
	var candidate = packed.instantiate()
	var old = active_scene
	var old_key: String = old.scene_key
	var old_settings := _settings(old)
	shared_controls = old_settings.duplicate()
	old.gpu_brush = &""
	old.player_camera._release_mouse()
	old.player_camera.set_process(false)
	old.player_camera.set_process_input(false)
	old.player_camera.set_process_unhandled_input(false)
	old.playing = false
	if session_directory.is_empty():
		session_directory = "user://scene_sessions/" + str(Time.get_unix_time_from_system()) + "_" + str(Time.get_ticks_usec())
		DirAccess.make_dir_recursive_absolute(session_directory)
	serial += 1
	var path := session_directory.path_join("%s_%04d.sandcp" % [old_key, serial])
	var save_error: StringName = await old.save_gpu_checkpoint(path)
	if not save_error.is_empty():
		candidate.free()
		old.playing = old_settings.playing
		old.player_camera.set_process(true)
		old.player_camera.set_process_input(true)
		old.player_camera.set_process_unhandled_input(true)
		_finish("保存失败，保留当前场景：" + String(save_error))
		return
	saved[old_key] = {"path": path, "settings": old_settings}
	_set_message("正在切换场景…")
	await old.shutdown()
	generation_highwater = maxi(generation_highwater, old.generation)
	active_scene = null
	old.queue_free()
	await get_tree().process_frame
	var target_settings: Dictionary = saved[key].settings if saved.has(key) else {"playing": old_settings.playing}
	var error := ""
	if inject_target_failure_once:
		inject_target_failure_once = false
		error = "测试注入的初始化失败"
	else:
		error = await _prepare(candidate, key, target_settings)
	if not error.is_empty():
		if candidate.is_inside_tree():
			await candidate.shutdown()
		candidate.queue_free()
		await get_tree().process_frame
		_set_message("目标加载失败，正在恢复原场景…")
		var rollback = load(SCENES[old_key]).instantiate()
		var rollback_error := await _prepare(rollback, old_key, old_settings)
		active_scene = rollback
		get_tree().current_scene = rollback
		_finish(error if rollback_error.is_empty() else error + "；" + rollback_error)
		return
	active_scene = candidate
	get_tree().current_scene = candidate
	generation_highwater = maxi(generation_highwater, candidate.generation)
	_finish("")
	switched.emit(key)

func _finish(error: String) -> void:
	last_error = error
	busy = false
	_set_message("切换完成 · 已保留进度" if error.is_empty() else error)
