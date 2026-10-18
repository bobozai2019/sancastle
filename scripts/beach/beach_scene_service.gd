extends Node

signal status_changed
signal switched(key: String)
const Routes=preload("res://scripts/beach/unified_scene_routes.gd")
const SCENES=Routes.FORMAL
const ENTRY="res://scripts/beach/unified_playable_entry.gd"
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
var release_records := []

func _unified_factory(scene) -> bool:
	return scene is Node3D and scene.get_script()!=null and scene.get_script().resource_path==ENTRY and not scene.playable_scene_family().is_empty()

func _cache_key(scene, key: String) -> String:return scene.playable_scene_family()+":"+key

func _dispose_scene(scene) -> bool:
	if scene == null:
		return true
	var identity: int = scene.get_instance_id()
	var released := true
	if scene.is_inside_tree():
		var profiler: Node = scene.get_node_or_null("Interface/PerformancePanel")
		if profiler != null:
			await profiler.stop_sampling()
		await scene.shutdown()
		released=scene.unified_release_complete()
		if not released:
			release_records.append({"instance_id":identity,"gpu_released":false,"node_freed":false,"at_us":Time.get_ticks_usec()})
			if release_records.size()>12:release_records.pop_front()
			return false
		scene.set_process(false)
		scene.queue_free()
		# Flush node destruction and renderer commands before constructing the
		# replacement. Physics shapes and reflection viewports belong to nodes.
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		await get_tree().process_frame
	else:
		scene.free()
	var record := {"instance_id": identity, "gpu_released": released, "node_freed": not is_instance_id_valid(identity), "at_us": Time.get_ticks_usec()}
	release_records.append(record)
	if release_records.size() > 12: release_records.pop_front()
	return released and record.node_freed

func attach(scene: Node3D) -> void:
	if busy or not _unified_factory(scene):
		return
	active_scene = scene
	generation_highwater = maxi(generation_highwater, scene.generation)

func request_switch(key: String) -> bool:
	if busy or not SCENES.has(key) or not is_instance_valid(active_scene) or not _unified_factory(active_scene) or not active_scene.ready_for_ticks:
		return false
	if active_scene.shutdown_requested or active_scene.closing:return false
	if active_scene._booting:return false
	if not active_scene.runtime.ready_for_input():return false
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
	var settings := {"playing": scene.playing, "hide_hud": scene.hide_hud,
		"selected_sand_tool": scene.selected_sand_tool,
		"dig_amount_m3": scene.dig_amount_m3, "fill_amount_m3": scene.fill_amount_m3,
		"manual_wave_amplitude_m": scene.manual_wave_amplitude_m,
		"sampling": scene.get_node("Interface/PerformancePanel/Margin/Rows/Header/Sampling").button_pressed,
		"camera": scene.player_camera.transform, "use_player_camera": scene.use_player_camera}
	if scene.has_method("_capture_brush_selection"):
		settings["brush_selection"]=scene._capture_brush_selection()
	return settings

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
	if shared_controls.has("brush_selection") and scene.has_method("_apply_brush_selection"):
		scene._apply_brush_selection(shared_controls.brush_selection)
	scene.get_node("Interface/PerformancePanel/Margin/Rows/Header/Sampling").button_pressed = shared_controls.get("sampling", true)
	if settings.has("camera"):
		scene.player_camera.transform = settings.camera
	scene.set_player_camera(settings.get("use_player_camera", scene.use_player_camera))
	scene.playing = settings.get("playing", true)
	scene._update_status()

func _prepare(scene, key: String, settings: Dictionary) -> String:
	if not _unified_factory(scene):return "不支持的场景工厂"
	var cache_key:=_cache_key(scene,key)
	generation_highwater += 2
	scene.generation = generation_highwater
	scene.playing = false
	get_tree().root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 90000
	while (not scene.ready_for_ticks or scene._booting) and scene.last_error.is_empty() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if not scene.ready_for_ticks or scene._booting or not scene.last_error.is_empty():
		return "场景初始化失败：" + scene.last_error
	if saved.has(cache_key):
		var error: StringName = await scene.restore_gpu_checkpoint(saved[cache_key].path)
		if not error.is_empty():
			return "恢复失败：" + String(error)
	_apply_settings(scene, settings)
	return ""

func _switch(key: String) -> void:
	var old = active_scene
	var target_path: String=old.playable_scene_path(key)
	var rollback_path: String=old.playable_scene_path(old.scene_key)
	var packed: PackedScene = load(target_path)
	if packed == null:
		_finish("场景资源加载失败")
		return
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
	var path := session_directory.path_join("%s_%s_%04d.sandue" % [old.playable_scene_family(),old_key,serial])
	var save_error: StringName = await old.save_gpu_checkpoint(path)
	if not save_error.is_empty():
		old.playing = old_settings.playing
		old.player_camera.set_process(true)
		old.player_camera.set_process_input(true)
		old.player_camera.set_process_unhandled_input(true)
		_finish("保存失败，保留当前场景：" + String(save_error))
		return
	var old_cache_key:=_cache_key(old,old_key)
	var target_cache_key:=_cache_key(old,key)
	saved[old_cache_key] = {"path": path, "settings": old_settings}
	_set_message("正在切换场景…")
	generation_highwater = maxi(generation_highwater, old.generation)
	active_scene = null
	get_tree().current_scene = null
	if not await _dispose_scene(old):
		active_scene=old
		get_tree().current_scene=old
		_finish("旧场景释放未完成，已停止加载；进度保存在检查点中")
		return
	old = null
	var candidate = packed.instantiate()
	var target_settings: Dictionary = saved[target_cache_key].settings if saved.has(target_cache_key) else {"playing": old_settings.playing}
	var error := ""
	if inject_target_failure_once:
		inject_target_failure_once = false
		error = "测试注入的初始化失败"
	else:
		error = await _prepare(candidate, key, target_settings)
	if not error.is_empty():
		await _dispose_scene(candidate)
		candidate = null
		_set_message("目标加载失败，正在恢复原场景…")
		var rollback = load(rollback_path).instantiate()
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
