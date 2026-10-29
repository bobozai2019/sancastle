extends Node
## GodotIQ game runtime autoload — executes screenshot and performance
## snapshot requests relayed from the editor via EngineDebugger.
## Registered as "GodotIQRuntime" autoload by godotiq_plugin.gd.
## NO @tool — this runs in the game process, not the editor.

var _input_in_progress: bool = false
const SCREENSHOT_MAX_ENCODED_BYTES := 45000
const SCREENSHOT_MAX_DOWNSCALE_PASSES := 4
const SCREENSHOT_MAX_INITIAL_PIXELS := 414720  # 720x576 before the first expensive encode
const SCREENSHOT_MAX_INITIAL_DIMENSION := 720
const RUNTIME_DEFAULT_MAX_OUTPUT_NODES := 200
const RUNTIME_DEFAULT_MAX_VISITED_NODES := 5000
const RUNTIME_HARD_MAX_OUTPUT_NODES := 2000
const RUNTIME_HARD_MAX_VISITED_NODES := 20000

## Set to true by headless tests to skip EngineDebugger check in _ready().
static var test_mode: bool = false

# --- Watch system state ---
var _watches: Dictionary = {}
var _watch_events: Array = []
var _watch_sample_timer: float = 0.0
var _watch_sample_interval: float = 0.5
var _watch_active: bool = false
var _runtime_logger  # Variant — null if Logger unavailable
var _runtime_log_queue: Array = []
var _runtime_log_mutex: Mutex = Mutex.new()


func _ready() -> void:
	if test_mode:
		print("[GodotIQ] Runtime _ready() — test mode, skipping debugger check")
		return
	if not OS.has_feature("debug") and not OS.has_feature("editor"):
		queue_free()
		return
	# The editor can report a debugger session before the game-side debugger is
	# active. Give that handshake a bounded window instead of permanently
	# removing the runtime during the first autoload frame.
	for _frame in 120:
		if EngineDebugger.is_active():
			break
		await get_tree().process_frame
	print("[GodotIQ] Runtime _ready() — debugger active: ", EngineDebugger.is_active())
	if not EngineDebugger.is_active():
		print("[GodotIQ] Debugger not active, freeing runtime")
		queue_free()
		return
	EngineDebugger.register_message_capture("godotiq", _on_debugger_message)
	_install_runtime_logger()
	print("[GodotIQ] Message capture registered")


func _install_runtime_logger() -> void:
	if not ClassDB.class_exists("Logger") or not OS.has_method("add_logger"):
		return
	var logger_script = load("res://addons/godotiq/godotiq_runtime_logger.gd")
	if logger_script == null:
		return
	_runtime_logger = logger_script.new(Callable(self, "_queue_runtime_log_error"))
	OS.call("add_logger", _runtime_logger)


func _queue_runtime_log_error(entry: Dictionary) -> void:
	_runtime_log_mutex.lock()
	_runtime_log_queue.append(entry)
	if _runtime_log_queue.size() > 100:
		_runtime_log_queue = _runtime_log_queue.slice(-100)
	_runtime_log_mutex.unlock()


func _flush_runtime_log_errors() -> void:
	if not EngineDebugger.is_active():
		return
	_runtime_log_mutex.lock()
	var pending := _runtime_log_queue.duplicate(true)
	_runtime_log_queue.clear()
	_runtime_log_mutex.unlock()
	for entry in pending:
		EngineDebugger.send_message("godotiq:error", [JSON.stringify(entry)])


func _process(delta: float) -> void:
	_flush_runtime_log_errors()
	if not _watch_active or _watches.is_empty():
		return
	_watch_sample_timer += delta
	if _watch_sample_timer >= _watch_sample_interval:
		_watch_sample_timer = 0.0
		_sample_watched_nodes()


func _on_debugger_message(message: String, data: Array) -> bool:
	match message:
		"screenshot":
			var params = {}
			if data.size() > 0 and data[0] is String:
				var parsed = JSON.parse_string(data[0])
				if parsed is Dictionary:
					params = parsed
			elif data.size() > 0 and data[0] is Dictionary:
				params = data[0]
			_take_screenshot(params)
			return true
		"query_perf":
			var perf_params = {}
			if data.size() > 0 and data[0] is String:
				var parsed_perf = JSON.parse_string(data[0])
				if parsed_perf is Dictionary:
					perf_params = parsed_perf
			elif data.size() > 0 and data[0] is Dictionary:
				perf_params = data[0]
			_send_perf_snapshot(perf_params)
			return true
		"input":
			var input_params = {}
			if data.size() > 0 and data[0] is String:
				var parsed_input = JSON.parse_string(data[0])
				if parsed_input is Dictionary:
					input_params = parsed_input
			elif data.size() > 0 and data[0] is Dictionary:
				input_params = data[0]
			_simulate_input(input_params)
			return true
		"exec":
			var exec_params = {}
			if data.size() > 0 and data[0] is String:
				var parsed_exec = JSON.parse_string(data[0])
				if parsed_exec is Dictionary:
					exec_params = parsed_exec
			elif data.size() > 0 and data[0] is Dictionary:
				exec_params = data[0]
			_execute_code(exec_params)
			return true
		"query_state":
			var state_params = {}
			if data.size() > 0 and data[0] is String:
				var parsed_state = JSON.parse_string(data[0])
				if parsed_state is Dictionary:
					state_params = parsed_state
			elif data.size() > 0 and data[0] is Dictionary:
				state_params = data[0]
			_query_state(state_params)
			return true
		"query_nav":
			var nav_params = {}
			if data.size() > 0 and data[0] is String:
				var parsed_nav = JSON.parse_string(data[0])
				if parsed_nav is Dictionary:
					nav_params = parsed_nav
			elif data.size() > 0 and data[0] is Dictionary:
				nav_params = data[0]
			_handle_nav_query(nav_params)
			return true
		"watch":
			var watch_params = {}
			if data.size() > 0 and data[0] is String:
				var parsed_watch = JSON.parse_string(data[0])
				if parsed_watch is Dictionary:
					watch_params = parsed_watch
			elif data.size() > 0 and data[0] is Dictionary:
				watch_params = data[0]
			_handle_watch(watch_params)
			return true
		"query_ui_map":
			var ui_map_params = {}
			if data.size() > 0 and data[0] is String:
				var parsed_ui_map = JSON.parse_string(data[0])
				if parsed_ui_map is Dictionary:
					ui_map_params = parsed_ui_map
			elif data.size() > 0 and data[0] is Dictionary:
				ui_map_params = data[0]
			_handle_ui_map(ui_map_params)
			return true
		"explore_camera":
			var explore_params = {}
			if data.size() > 0 and data[0] is String:
				var parsed_explore = JSON.parse_string(data[0])
				if parsed_explore is Dictionary:
					explore_params = parsed_explore
			elif data.size() > 0 and data[0] is Dictionary:
				explore_params = data[0]
			_handle_explore_camera(explore_params)
			return true
		"query_scene_tree":
			var tree_params = {}
			if data.size() > 0 and data[0] is String:
				var parsed_tree = JSON.parse_string(data[0])
				if parsed_tree is Dictionary:
					tree_params = parsed_tree
			elif data.size() > 0 and data[0] is Dictionary:
				tree_params = data[0]
			_handle_query_scene_tree(tree_params)
			return true
		"press_button":
			var btn_params = {}
			if data.size() > 0 and data[0] is String:
				var parsed_btn = JSON.parse_string(data[0])
				if parsed_btn is Dictionary:
					btn_params = parsed_btn
			elif data.size() > 0 and data[0] is Dictionary:
				btn_params = data[0]
			_handle_press_button(btn_params)
			return true
		"find_node":
			var find_params = {}
			if data.size() > 0 and data[0] is String:
				var parsed_find = JSON.parse_string(data[0])
				if parsed_find is Dictionary:
					find_params = parsed_find
			elif data.size() > 0 and data[0] is Dictionary:
				find_params = data[0]
			_handle_find_node(find_params)
			return true
	return false


func _with_request_id(payload: Dictionary, params: Dictionary) -> Dictionary:
	var result: Dictionary = payload.duplicate(true)
	var request_id: String = str(params.get("_request_id", ""))
	if not request_id.is_empty():
		result["request_id"] = request_id
	return result


func _send_json_result(channel: String, payload: Dictionary, params: Dictionary = {}) -> void:
	EngineDebugger.send_message(channel, [JSON.stringify(_with_request_id(payload, params))])


func _take_screenshot(params: Dictionary):
	await get_tree().process_frame

	var viewport := get_viewport()
	if viewport == null:
		_send_json_result("godotiq:screenshot_result", {
			"error": "No viewport available",
		}, params)
		return

	var tex := viewport.get_texture()
	if tex == null:
		_send_json_result("godotiq:screenshot_result", {
			"error": "Viewport texture not available",
		}, params)
		return

	var img := tex.get_image()
	if img == null:
		_send_json_result("godotiq:screenshot_result", {
			"error": "Failed to capture viewport image",
		}, params)
		return

	var scale: float = clampf(params.get("scale", 0.5), 0.1, 1.0)
	var quality: float = clampf(params.get("quality", 0.5), 0.1, 1.0)
	var fmt: String = params.get("format", "webp")
	var region: Array = params.get("region", [])

	# Apply region crop before scaling
	if region.size() == 4:
		var rx: int = clampi(int(region[0]), 0, img.get_width() - 1)
		var ry: int = clampi(int(region[1]), 0, img.get_height() - 1)
		var rw: int = clampi(int(region[2]), 1, img.get_width() - rx)
		var rh: int = clampi(int(region[3]), 1, img.get_height() - ry)
		img = img.get_region(Rect2i(rx, ry, rw, rh))

	var source_width := img.get_width()
	var source_height := img.get_height()
	var first_encode_size := _get_screenshot_first_encode_size(source_width, source_height, scale)
	var requested_width := maxi(1, int(source_width * scale))
	var requested_height := maxi(1, int(source_height * scale))
	var first_encode_width := first_encode_size.x
	var first_encode_height := first_encode_size.y
	if first_encode_width != source_width or first_encode_height != source_height:
		img.resize(first_encode_width, first_encode_height)
	var w := img.get_width()
	var h := img.get_height()
	var pre_encode_limited := first_encode_width < requested_width or first_encode_height < requested_height

	var buffer: PackedByteArray
	match fmt:
		"png":
			buffer = img.save_png_to_buffer()
		"jpg":
			buffer = img.save_jpg_to_buffer(quality)
		_:
			fmt = "webp"
			buffer = img.save_webp_to_buffer(true, quality)

	var downscale_passes := 0
	while (
		buffer.size() > SCREENSHOT_MAX_ENCODED_BYTES
		and img.get_width() > 100
		and downscale_passes < SCREENSHOT_MAX_DOWNSCALE_PASSES
	):
		var next_width := maxi(100, int(img.get_width() * 0.7))
		var next_height := maxi(1, int(img.get_height() * 0.7))
		img.resize(next_width, next_height)
		match fmt:
			"png":
				buffer = img.save_png_to_buffer()
			"jpg":
				buffer = img.save_jpg_to_buffer(quality)
			_:
				buffer = img.save_webp_to_buffer(true, quality)
		downscale_passes += 1

	if buffer.size() > SCREENSHOT_MAX_ENCODED_BYTES:
		_send_json_result("godotiq:screenshot_result", {
			"error": "Encoded screenshot exceeds the transport budget after downscaling",
			"code": "SCREENSHOT_TOO_LARGE",
			"encoded_bytes": buffer.size(),
		}, params)
		return

	w = img.get_width()
	h = img.get_height()

	var b64 := Marshalls.raw_to_base64(buffer)
	_send_json_result("godotiq:screenshot_result", {
		"image": b64,
		"format": fmt,
		"width": w,
		"height": h,
		"encoded_bytes": buffer.size(),
		"requested_scale": scale,
		"actual_scale": float(w) / float(source_width),
		"downscaled": w < source_width or h < source_height,
		"pre_encode_limited": pre_encode_limited,
		"downscale_passes": downscale_passes,
	}, params)


func _get_screenshot_first_encode_size(source_width: int, source_height: int, scale: float) -> Vector2i:
	var requested_width := maxi(1, int(source_width * clampf(scale, 0.1, 1.0)))
	var requested_height := maxi(1, int(source_height * clampf(scale, 0.1, 1.0)))
	var pre_encode_scale := 1.0
	var requested_pixels := requested_width * requested_height
	if requested_pixels > SCREENSHOT_MAX_INITIAL_PIXELS:
		pre_encode_scale = minf(
			pre_encode_scale,
			sqrt(float(SCREENSHOT_MAX_INITIAL_PIXELS) / float(requested_pixels))
		)
	var requested_max_dimension := maxi(requested_width, requested_height)
	if requested_max_dimension > SCREENSHOT_MAX_INITIAL_DIMENSION:
		pre_encode_scale = minf(
			pre_encode_scale,
			float(SCREENSHOT_MAX_INITIAL_DIMENSION) / float(requested_max_dimension)
		)
	return Vector2i(
		maxi(1, int(requested_width * pre_encode_scale)),
		maxi(1, int(requested_height * pre_encode_scale))
	)


func _send_perf_snapshot(params: Dictionary = {}) -> void:
	var result := {
		"fps": Engine.get_frames_per_second(),
		"draw_calls": RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME
		),
		"triangles": RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME
		),
		"objects": RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME
		),
		"texture_mem": RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED
		),
		"buffer_mem": RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_BUFFER_MEM_USED
		),
		"video_mem": RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_VIDEO_MEM_USED
		),
		"total_nodes": get_tree().get_node_count(),
		"orphan_nodes": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
	}
	_send_json_result("godotiq:perf_result", result, params)


func _simulate_input(params: Dictionary):
	if _input_in_progress:
		_send_json_result("godotiq:input_result", {
			"success": false,
			"error": "Another input simulation is already in progress",
		}, params)
		return

	var commands_value = params.get("commands", [])
	if not commands_value is Array or commands_value.is_empty():
		_send_json_result("godotiq:input_result", {
			"success": false,
			"error": "commands must be a non-empty array",
		}, params)
		return
	for command in commands_value:
		if not command is Dictionary:
			_send_json_result("godotiq:input_result", {
				"success": false,
				"error": "Every input command must be an object",
			}, params)
			return
	var validation_error := _validate_input_commands(commands_value)
	if not validation_error.is_empty():
		_send_json_result("godotiq:input_result", {
			"success": false,
			"error": validation_error,
		}, params)
		return

	var commands: Array = commands_value
	var track_effects: bool = params.get("track_side_effects", false)
	_input_in_progress = true

	var state_before: Dictionary = {}
	if track_effects:
		state_before = _snapshot_scene_state()

	# Subscribe before dispatching commands so signals emitted synchronously by
	# the input handler are not missed.
	var signal_wait := _prepare_signal_wait(params)

	var results: Array = []
	var all_ok: bool = true

	for cmd in commands:
		var cmd_result := await _execute_input_command(cmd)
		results.append(cmd_result)
		if not cmd_result.get("ok", false):
			all_ok = false
			if not params.get("continue_on_error", false):
				break

	var side_effects: Array = []
	if track_effects:
		var state_after := _snapshot_scene_state()
		side_effects = _diff_states(state_before, state_after)

	var signal_data := await _finish_signal_wait(
		signal_wait,
		maxi(0, int(params.get("wait_for_timeout_ms", 5000))) / 1000.0
	)
	var signal_received: bool = signal_data.get("received", false)

	_input_in_progress = false

	_send_json_result("godotiq:input_result", {
		"success": all_ok,
		"commands_executed": results.size(),
		"commands_total": commands.size(),
		"results": results,
		"side_effects": side_effects,
		"signal_received": signal_received,
		"signal_data": signal_data,
	}, params)


func _is_json_number(value) -> bool:
	return value is int or value is float


func _validate_number_array(value, expected_size: int, field_name: String) -> String:
	if not value is Array or value.size() < expected_size:
		return "%s requires an array with %d numeric values" % [field_name, expected_size]
	for i in expected_size:
		if not _is_json_number(value[i]):
			return "%s[%d] must be numeric" % [field_name, i]
	return ""


func _validate_optional_number(data: Dictionary, field_name: String) -> String:
	if data.has(field_name) and not _is_json_number(data[field_name]):
		return "%s must be numeric" % field_name
	return ""


func _validate_drag_data(data) -> String:
	if not data is Dictionary:
		return "drag_at requires an object"
	var error := _validate_number_array(data.get("from", null), 2, "drag_at.from")
	if not error.is_empty():
		return error
	error = _validate_number_array(data.get("to", null), 2, "drag_at.to")
	if not error.is_empty():
		return error
	if _resolve_mouse_button(str(data.get("button", "left"))) < 0:
		return "Unknown drag_at button: %s" % data.get("button")
	for field_name in ["hold_before_ms", "duration_ms", "hold_after_ms", "steps"]:
		error = _validate_optional_number(data, field_name)
		if not error.is_empty():
			return error
		if data.has(field_name) and int(data[field_name]) < 0:
			return "%s must be >= 0" % field_name
	return ""


func _validate_input_commands(commands: Array) -> String:
	var command_fields := ["wait_ms", "actions", "key", "mouse_motion", "click_at", "click_at_world", "drag_at", "tap"]
	for index in commands.size():
		var cmd: Dictionary = commands[index]
		var matched_fields: Array[String] = []
		for field_name in command_fields:
			if cmd.has(field_name):
				matched_fields.append(field_name)
		if matched_fields.size() != 1:
			return "commands[%d] must contain exactly one command field" % index

		var command_type := matched_fields[0]
		var error := _validate_optional_number(cmd, "hold_ms")
		if not error.is_empty():
			return "commands[%d].%s" % [index, error]

		match command_type:
			"wait_ms":
				if not _is_json_number(cmd["wait_ms"]):
					return "commands[%d].wait_ms must be numeric" % index
			"actions":
				if not cmd["actions"] is Array or cmd["actions"].is_empty():
					return "commands[%d].actions must be a non-empty array" % index
				for action_name in cmd["actions"]:
					if not (action_name is String or action_name is StringName):
						return "commands[%d] action names must be strings" % index
					if not InputMap.has_action(action_name):
						return "commands[%d] contains unknown action: %s" % [index, action_name]
			"key":
				if not cmd["key"] is String or str(cmd["key"]).is_empty():
					return "commands[%d].key must be a non-empty string" % index
				if _key_name_to_code(str(cmd["key"])) == KEY_NONE:
					return "commands[%d] contains unknown key: %s" % [index, cmd["key"]]
				if not str(cmd.get("key_mode", "physical")).to_lower() in ["physical", "logical"]:
					return "commands[%d].key_mode must be 'physical' or 'logical'" % index
			"mouse_motion":
				if not cmd["mouse_motion"] is Dictionary:
					return "commands[%d].mouse_motion must be an object" % index
				for axis in ["relative_x", "relative_y"]:
					error = _validate_optional_number(cmd["mouse_motion"], axis)
					if not error.is_empty():
						return "commands[%d].mouse_motion.%s" % [index, error]
			"click_at":
				error = _validate_number_array(cmd["click_at"], 2, "click_at")
				if not error.is_empty():
					return "commands[%d].%s" % [index, error]
				if _resolve_mouse_button(str(cmd.get("button", "left"))) < 0:
					return "commands[%d] has unknown mouse button" % index
			"click_at_world":
				error = _validate_number_array(cmd["click_at_world"], 3, "click_at_world")
				if not error.is_empty():
					return "commands[%d].%s" % [index, error]
				if _resolve_mouse_button(str(cmd.get("button", "left"))) < 0:
					return "commands[%d] has unknown mouse button" % index
			"drag_at":
				error = _validate_drag_data(cmd["drag_at"])
				if not error.is_empty():
					return "commands[%d].%s" % [index, error]
			"tap":
				if not cmd["tap"] is String or str(cmd["tap"]).is_empty():
					return "commands[%d].tap must be a non-empty string" % index
	return ""


func _prepare_signal_wait(params: Dictionary) -> Dictionary:
	var wait_for: String = str(params.get("wait_for", ""))
	var state := {
		"configured": false,
		"received": false,
		"timed_out": false,
		"error": "",
		"target": null,
		"signal_name": "",
		"callback": Callable(),
	}
	if wait_for.is_empty():
		return state
	if not wait_for.begins_with("signal:"):
		state["error"] = "wait_for must use signal:NodeName.signal_name"
		return state

	var signal_spec := wait_for.substr(7)
	var separator := signal_spec.rfind(".")
	if separator <= 0 or separator >= signal_spec.length() - 1:
		state["error"] = "Invalid wait_for signal specification"
		return state

	var node_path := signal_spec.substr(0, separator)
	var signal_name := signal_spec.substr(separator + 1)
	var target_node := get_tree().root.get_node_or_null(node_path)
	if target_node == null:
		target_node = get_tree().root.get_node_or_null("/root/" + node_path)
	if target_node == null:
		state["error"] = "wait_for target not found: %s" % node_path
		return state
	if not target_node.has_signal(signal_name):
		state["error"] = "Signal not found: %s.%s" % [node_path, signal_name]
		return state
	for signal_info in target_node.get_signal_list():
		if str(signal_info.get("name", "")) == signal_name:
			var signal_args = signal_info.get("args", [])
			if signal_args is Array and signal_args.size() > 1:
				state["error"] = "wait_for supports signals with at most one argument: %s.%s has %d" % [
					node_path,
					signal_name,
					signal_args.size(),
				]
				return state
			break

	# Signal payload is diagnostic only; synchronization supports zero or one
	# argument and rejects wider signatures explicitly above.
	var callback := func(args = null):
		state["received"] = true
		if args != null:
			state["data"] = args
	target_node.connect(signal_name, callback, CONNECT_ONE_SHOT)
	state["configured"] = true
	state["target"] = target_node
	state["signal_name"] = signal_name
	state["callback"] = callback
	return state


func _finish_signal_wait(state: Dictionary, timeout: float) -> Dictionary:
	if not state.get("configured", false):
		return {
			"received": false,
			"timed_out": false,
			"error": state.get("error", ""),
		}

	var elapsed := 0.0
	var step := 0.05
	while not state.get("received", false) and elapsed < timeout:
		await get_tree().create_timer(minf(step, timeout - elapsed)).timeout
		elapsed += step

	var target = state.get("target")
	var signal_name: String = state.get("signal_name", "")
	var callback: Callable = state.get("callback", Callable())
	if not state.get("received", false):
		state["timed_out"] = true
		if is_instance_valid(target) and target.is_connected(signal_name, callback):
			target.disconnect(signal_name, callback)

	return {
		"received": state.get("received", false),
		"timed_out": state.get("timed_out", false),
		"error": state.get("error", ""),
		"data": state.get("data", null),
	}


func _execute_input_command(cmd: Dictionary) -> Dictionary:
	if cmd.has("wait_ms"):
		var wait_ms := clampi(int(cmd["wait_ms"]), 0, 60000)
		var wait_time: float = wait_ms / 1000.0
		await get_tree().create_timer(wait_time).timeout
		return {"type": "wait", "ms": wait_ms, "ok": true}

	if cmd.has("actions"):
		var actions: Array = cmd["actions"]
		var hold_ms: int = clampi(int(cmd.get("hold_ms", 70)), 0, 60000)
		if actions.is_empty():
			return {"type": "action", "actions": actions, "ok": false, "error": "actions must not be empty"}

		for action_name in actions:
			if not (action_name is String or action_name is StringName):
				return {"type": "action", "actions": actions, "ok": false, "error": "Action names must be strings"}
			if not InputMap.has_action(action_name):
				return {"type": "action", "actions": actions, "ok": false, "error": "Unknown action: %s" % action_name}

		for action_name in actions:
			var event_down := InputEventAction.new()
			event_down.action = action_name
			event_down.pressed = true
			event_down.strength = 1.0
			Input.parse_input_event(event_down)

		if hold_ms > 0:
			await get_tree().create_timer(hold_ms / 1000.0).timeout
		else:
			await get_tree().process_frame

		for action_name in actions:
			var event_up := InputEventAction.new()
			event_up.action = action_name
			event_up.pressed = false
			event_up.strength = 0.0
			Input.parse_input_event(event_up)

		return {"type": "action", "actions": actions, "hold_ms": hold_ms, "dispatched": true, "ok": true}

	if cmd.has("key"):
		var key_name: String = cmd["key"]
		var hold_ms: int = clampi(int(cmd.get("hold_ms", 70)), 0, 60000)
		var key_code := _key_name_to_code(key_name)
		if key_code == KEY_NONE:
			return {"type": "key", "key": key_name, "ok": false, "error": "Unknown key: %s" % key_name}

		var event_down := InputEventKey.new()
		var key_mode: String = str(cmd.get("key_mode", "physical")).to_lower()
		if key_mode == "physical":
			event_down.physical_keycode = key_code
		elif key_mode == "logical":
			event_down.keycode = key_code
		else:
			return {"type": "key", "key": key_name, "ok": false, "error": "key_mode must be 'physical' or 'logical'"}
		event_down.pressed = true
		Input.parse_input_event(event_down)

		if hold_ms > 0:
			await get_tree().create_timer(hold_ms / 1000.0).timeout
		else:
			await get_tree().process_frame

		var event_up := InputEventKey.new()
		if key_mode == "physical":
			event_up.physical_keycode = key_code
		else:
			event_up.keycode = key_code
		event_up.pressed = false
		Input.parse_input_event(event_up)

		return {"type": "key", "key": key_name, "key_mode": key_mode, "hold_ms": hold_ms, "dispatched": true, "ok": true}

	if cmd.has("mouse_motion"):
		var motion_data: Dictionary = cmd["mouse_motion"]
		var rel_x: float = float(motion_data.get("relative_x", 0))
		var rel_y: float = float(motion_data.get("relative_y", 0))
		var event := InputEventMouseMotion.new()
		event.relative = Vector2(rel_x, rel_y)
		Input.parse_input_event(event)
		return {"type": "mouse_motion", "relative_x": rel_x, "relative_y": rel_y, "ok": true}

	if cmd.has("click_at"):
		var pos_data = cmd["click_at"]
		if not (pos_data is Array) or pos_data.size() < 2:
			return {"type": "click_at", "ok": false, "error": "click_at requires [x, y] array"}
		var screen_pos := Vector2(float(pos_data[0]), float(pos_data[1]))
		var btn_idx := _resolve_mouse_button(cmd.get("button", "left"))
		if btn_idx < 0:
			return {"type": "click_at", "ok": false, "error": "Unknown button: %s" % cmd.get("button")}
		await _dispatch_click(screen_pos, btn_idx)
		return {"type": "click_at", "position": [screen_pos.x, screen_pos.y], "button": cmd.get("button", "left"), "ok": true}

	if cmd.has("click_at_world"):
		var world_data = cmd["click_at_world"]
		if not (world_data is Array) or world_data.size() < 3:
			return {"type": "click_at_world", "ok": false, "error": "click_at_world requires [x, y, z] array"}
		var world_pos := Vector3(float(world_data[0]), float(world_data[1]), float(world_data[2]))
		var camera := get_viewport().get_camera_3d()
		if camera == null:
			return {"type": "click_at_world", "ok": false, "error": "No active Camera3D found"}
		if camera.is_position_behind(world_pos):
			return {"type": "click_at_world", "ok": false, "error": "World position is behind the camera"}
		var screen_pos := camera.unproject_position(world_pos)
		var btn_idx := _resolve_mouse_button(cmd.get("button", "left"))
		if btn_idx < 0:
			return {"type": "click_at_world", "ok": false, "error": "Unknown button: %s" % cmd.get("button")}
		await _dispatch_click(screen_pos, btn_idx)
		return {"type": "click_at_world", "world_position": [world_pos.x, world_pos.y, world_pos.z], "screen_position": [screen_pos.x, screen_pos.y], "button": cmd.get("button", "left"), "ok": true}

	if cmd.has("drag_at"):
		return await _dispatch_drag_at(cmd["drag_at"])

	if cmd.has("tap"):
		var target_name: String = cmd["tap"]
		var target_node := _find_ui_node(target_name)
		if target_node == null:
			return {"type": "tap", "target": target_name, "ok": false, "error": "UI node '%s' not found" % target_name}

		var rect: Rect2 = target_node.get_global_rect()
		var center := rect.get_center()
		await _dispatch_click(center, MOUSE_BUTTON_LEFT)
		return {"type": "tap", "target": target_name, "position": [center.x, center.y], "ok": true}

	return {"type": "unknown", "ok": false, "error": "Unrecognized command format"}


func _array_to_vector2(value, field_name: String) -> Dictionary:
	if not (value is Array) or value.size() < 2:
		return {"ok": false, "error": "%s requires [x, y] array" % field_name}
	return {"ok": true, "value": Vector2(float(value[0]), float(value[1]))}


func _non_negative_int(data: Dictionary, key: String, default_value: int) -> Dictionary:
	var value: int = int(data.get(key, default_value))
	if value < 0:
		return {"ok": false, "error": "%s must be >= 0" % key}
	return {"ok": true, "value": value}


func _dispatch_mouse_motion(screen_pos: Vector2, relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = screen_pos
	event.global_position = screen_pos
	event.relative = relative
	Input.parse_input_event(event)


func _dispatch_mouse_button(screen_pos: Vector2, button_index: int, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button_index
	event.pressed = pressed
	event.position = screen_pos
	event.global_position = screen_pos
	Input.parse_input_event(event)


func _dispatch_click(screen_pos: Vector2, button_index: int) -> void:
	_dispatch_mouse_button(screen_pos, button_index, true)
	await get_tree().create_timer(0.05).timeout
	_dispatch_mouse_button(screen_pos, button_index, false)


func _dispatch_drag_at(data) -> Dictionary:
	if not (data is Dictionary):
		return {"type": "drag_at", "ok": false, "error": "drag_at requires a dictionary"}

	var from_result := _array_to_vector2(data.get("from", null), "drag_at.from")
	if not from_result.get("ok", false):
		return {"type": "drag_at", "ok": false, "error": from_result["error"]}

	var to_result := _array_to_vector2(data.get("to", null), "drag_at.to")
	if not to_result.get("ok", false):
		return {"type": "drag_at", "ok": false, "error": to_result["error"]}

	var btn_idx := _resolve_mouse_button(str(data.get("button", "left")))
	if btn_idx < 0:
		return {"type": "drag_at", "ok": false, "error": "Unknown button: %s" % data.get("button")}

	var hold_before := _non_negative_int(data, "hold_before_ms", 100)
	if not hold_before.get("ok", false):
		return {"type": "drag_at", "ok": false, "error": hold_before["error"]}
	var duration := _non_negative_int(data, "duration_ms", 500)
	if not duration.get("ok", false):
		return {"type": "drag_at", "ok": false, "error": duration["error"]}
	var hold_after := _non_negative_int(data, "hold_after_ms", 100)
	if not hold_after.get("ok", false):
		return {"type": "drag_at", "ok": false, "error": hold_after["error"]}

	var start_pos: Vector2 = from_result["value"]
	var end_pos: Vector2 = to_result["value"]
	var requested_steps: int = int(data.get("steps", max(1, int(ceil(float(duration["value"]) / 16.0)))))
	var steps: int = clampi(requested_steps, 1, 240)

	var current_pos := start_pos
	_dispatch_mouse_motion(start_pos, Vector2.ZERO)
	_dispatch_mouse_button(start_pos, btn_idx, true)

	if int(hold_before["value"]) > 0:
		await get_tree().create_timer(float(hold_before["value"]) / 1000.0).timeout

	for i in range(1, steps + 1):
		var t := float(i) / float(steps)
		var next_pos := start_pos.lerp(end_pos, t)
		_dispatch_mouse_motion(next_pos, next_pos - current_pos)
		current_pos = next_pos
		if int(duration["value"]) > 0:
			await get_tree().create_timer(float(duration["value"]) / 1000.0 / float(steps)).timeout
		else:
			await get_tree().process_frame

	if int(hold_after["value"]) > 0:
		await get_tree().create_timer(float(hold_after["value"]) / 1000.0).timeout

	_dispatch_mouse_button(end_pos, btn_idx, false)
	await get_tree().process_frame  # flush release event
	return {
		"type": "drag_at",
		"from": [start_pos.x, start_pos.y],
		"to": [end_pos.x, end_pos.y],
		"button": str(data.get("button", "left")),
		"hold_before_ms": int(hold_before["value"]),
		"duration_ms": int(duration["value"]),
		"hold_after_ms": int(hold_after["value"]),
		"steps": steps,
		"ok": true,
	}


func _resolve_mouse_button(button_name: String) -> int:
	match button_name:
		"left": return MOUSE_BUTTON_LEFT
		"right": return MOUSE_BUTTON_RIGHT
		"middle": return MOUSE_BUTTON_MIDDLE
		_: return -1


func _find_ui_node(target_name: String) -> Control:
	var queue: Array[Node] = [get_tree().root]
	var cursor := 0
	var visited := 0
	while cursor < queue.size() and visited < RUNTIME_DEFAULT_MAX_VISITED_NODES:
		var node := queue[cursor]
		cursor += 1
		if not is_instance_valid(node):
			continue
		visited += 1
		if node is Control and node.is_visible_in_tree():
			if str(node.name).to_lower() == target_name.to_lower():
				return node
			if node is BaseButton and "text" in node:
				var btn_text: String = str(node.text).strip_edges()
				if not btn_text.is_empty() and btn_text.to_lower() == target_name.to_lower():
					return node
		var remaining_capacity := RUNTIME_DEFAULT_MAX_VISITED_NODES - visited - (queue.size() - cursor)
		for child in node.get_children():
			if remaining_capacity <= 0:
				break
			if is_instance_valid(child):
				queue.append(child)
				remaining_capacity -= 1
	return null


func _key_name_to_code(key_name: String) -> Key:
	var normalized := key_name.strip_edges()
	if normalized.is_empty():
		return KEY_NONE

	match normalized.to_upper():
		"ARROWUP":
			normalized = "Up"
		"ARROWDOWN":
			normalized = "Down"
		"ARROWLEFT":
			normalized = "Left"
		"ARROWRIGHT":
			normalized = "Right"
		"SPACEBAR":
			normalized = "Space"
		"PAGE UP":
			normalized = "PageUp"
		"PAGE DOWN":
			normalized = "PageDown"
		"DEL":
			normalized = "Delete"
		"ESC":
			normalized = "Escape"
		"RETURN":
			normalized = "Enter"
		"CONTROL":
			normalized = "Ctrl"

	if OS.has_method("find_keycode_from_string"):
		var os_keycode := OS.find_keycode_from_string(normalized)
		if os_keycode != KEY_NONE:
			return os_keycode

	match normalized.to_upper():
		"SPACE": return KEY_SPACE
		"ENTER": return KEY_ENTER
		"ESCAPE": return KEY_ESCAPE
		"TAB": return KEY_TAB
		"BACKSPACE": return KEY_BACKSPACE
		"UP": return KEY_UP
		"DOWN": return KEY_DOWN
		"LEFT": return KEY_LEFT
		"RIGHT": return KEY_RIGHT
		"SHIFT": return KEY_SHIFT
		"CTRL": return KEY_CTRL
		"ALT": return KEY_ALT
		"DELETE": return KEY_DELETE
		"PAGEUP": return KEY_PAGEUP
		"PAGEDOWN": return KEY_PAGEDOWN
		"HOME": return KEY_HOME
		"END": return KEY_END
		"INSERT": return KEY_INSERT
		"F1": return KEY_F1
		"F2": return KEY_F2
		"F3": return KEY_F3
		"F4": return KEY_F4
		"F5": return KEY_F5
		_:
			if normalized.length() == 1:
				return normalized.to_upper().unicode_at(0)
	return KEY_NONE


func _snapshot_scene_state() -> Dictionary:
	var state: Dictionary = {}
	var root := get_tree().root
	for child in root.get_children():
		if child == self:
			continue
		if child.get_script() == null:
			continue
		var node_state: Dictionary = {}
		for prop in child.get_property_list():
			if prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
				var val = child.get(prop["name"])
				if val is int or val is float or val is String or val is bool:
					node_state[prop["name"]] = val
				elif val is Array:
					node_state[prop["name"]] = val.size()
				elif val is Dictionary:
					node_state[prop["name"]] = val.size()
		if not node_state.is_empty():
			state[child.name] = node_state
	return state


func _diff_states(before: Dictionary, after: Dictionary) -> Array:
	var changes: Array = []
	for node_name in after.keys():
		if not before.has(node_name):
			continue
		var before_props: Dictionary = before[node_name]
		var after_props: Dictionary = after[node_name]
		for prop_name in after_props.keys():
			if before_props.has(prop_name) and before_props[prop_name] != after_props[prop_name]:
				changes.append({
					"node": node_name,
					"property": prop_name,
					"from": before_props[prop_name],
					"to": after_props[prop_name],
				})
	return changes


func _execute_code(params: Dictionary) -> void:
	var code: String = params.get("code", "")

	if code.is_empty():
		_send_json_result("godotiq:exec_result", {
			"status": "ERROR",
			"result": "",
			"error": "No code provided",
		}, params)
		return

	var trimmed := code.strip_edges()
	if not trimmed.begins_with("func run():") and not trimmed.begins_with("func run() ->"):
		_send_json_result("godotiq:exec_result", {
			"status": "BLOCKED",
			"result": "",
			"error": "Code must start with 'func run():' or 'func run() -> Type:'",
		}, params)
		return

	# Safety: blocked patterns — keep in sync with godotiq_server.gd and Python exec_code._BLOCKED_PATTERNS
	# Note: DirAccess.remove also catches DirAccess.remove_absolute() via substring match
	var blocked_patterns: Array = [
		"DirAccess.remove",
		"DirAccess.open",
		"FileAccess.open",
		"FileAccess.get_file_as_string",
		"FileAccess.get_file_as_bytes",
		"OS.execute",
		"OS.kill",
		"OS.shell_open",
	]
	for pattern in blocked_patterns:
		if code.find(pattern) != -1:
			_send_json_result("godotiq:exec_result", {
				"status": "BLOCKED",
				"result": "",
				"error": "Blocked pattern found: %s" % pattern,
			}, params)
			return

	var script := GDScript.new()
	script.source_code = "@tool\nextends RefCounted\n\n" + code
	var err := script.reload()
	if err != OK:
		_send_json_result("godotiq:exec_result", {
			"status": "COMPILE_ERROR",
			"result": "",
			"error": "Compilation failed (error %d: %s)" % [err, error_string(err)],
		}, params)
		return

	var obj = script.new()
	if obj == null:
		_send_json_result("godotiq:exec_result", {
			"status": "ERROR",
			"result": "",
			"error": "Failed to instantiate script",
		}, params)
		return

	var result = obj.run()
	var result_str: String
	if result != null:
		result_str = str(result)
	else:
		result_str = "null"

	_send_json_result("godotiq:exec_result", {
		"status": "OK",
		"result": result_str,
		"error": "",
	}, params)


func _query_state(params: Dictionary) -> void:
	var queries: Array = params.get("queries", [])
	if queries.is_empty():
		_send_json_result("godotiq:state_result", {
			"results": [],
			"error": "No queries provided",
		}, params)
		return

	var results: Array = []
	for query in queries:
		results.append(_resolve_state_query(query))

	_send_json_result("godotiq:state_result", {
		"results": results,
	}, params)


func _resolve_state_query(query: Dictionary) -> Dictionary:
	var node: Node = null

	if query.has("autoload"):
		var autoload_name: String = query["autoload"]
		node = get_tree().root.get_node_or_null(autoload_name)
		if node == null:
			node = get_tree().root.get_node_or_null("/root/" + autoload_name)
	elif query.has("node"):
		var node_path: String = query["node"]
		node = get_tree().root.get_node_or_null(node_path)
		if node == null:
			node = _find_node_recursive(get_tree().root, node_path.get_file())

	if node == null:
		var identifier: String = query.get("autoload", query.get("node", "unknown"))
		return {
			"node": identifier,
			"found": false,
			"error": "Node not found",
		}

	var properties: Array = query.get("properties", [])
	var prop_values: Dictionary = {}

	for prop_name in properties:
		prop_values[prop_name] = _get_property_safe(node, prop_name)

	return {
		"node": node.name,
		"found": true,
		"class": node.get_class(),
		"properties": prop_values,
	}


func _get_property_safe(node: Node, prop_name: String) -> Variant:
	if prop_name.ends_with("()"):
		var parts := prop_name.split(".")
		if parts.size() == 2:
			var obj_prop: String = parts[0]
			var method: String = parts[1].replace("()", "")
			var obj = node.get(obj_prop)
			if obj != null and obj.has_method(method):
				return obj.call(method)
			elif obj is Array and method == "size":
				return obj.size()
			elif obj is Dictionary and method == "size":
				return obj.size()
			return "ERROR: cannot call %s on %s" % [method, obj_prop]

	if ":" in prop_name:
		return _serialize_value(node.get_indexed(prop_name))

	if "." in prop_name and not prop_name.ends_with("()"):
		var parts := prop_name.split(".")
		var current = node
		for part in parts:
			if current == null:
				return "ERROR: null in chain at '%s'" % part
			if current is Object:
				current = current.get(part)
			else:
				return "ERROR: cannot access '%s'" % part
		return _serialize_value(current)

	var val = node.get(prop_name)
	return _serialize_value(val)


func _serialize_value(val) -> Variant:
	if val == null:
		return null
	if val is int or val is float or val is String or val is bool:
		return val
	if val is Vector3:
		return [snapped(val.x, 0.001), snapped(val.y, 0.001), snapped(val.z, 0.001)]
	if val is Vector2:
		return [snapped(val.x, 0.01), snapped(val.y, 0.01)]
	if val is Color:
		return [val.r, val.g, val.b, val.a]
	if val is Array:
		if val.size() > 20:
			return {"type": "Array", "size": val.size(), "preview": str(val).left(200)}
		return str(val)
	if val is Dictionary:
		if val.size() > 20:
			return {"type": "Dictionary", "size": val.size(), "keys": str(val.keys()).left(200)}
		var result: Dictionary = {}
		for key in val.keys():
			result[str(key)] = _serialize_value(val[key])
		return result
	if val is NodePath:
		return str(val)
	if val is Resource:
		var res_path: String = "inline"
		if val.resource_path:
			res_path = val.resource_path
		return {"type": val.get_class(), "path": res_path}
	if val is Object:
		return {"type": val.get_class(), "id": val.get_instance_id()}
	return str(val)


func _find_node_recursive(node: Node, target_name: String) -> Node:
	if node.name == target_name:
		return node
	for child in node.get_children():
		var found := _find_node_recursive(child, target_name)
		if found:
			return found
	return null


# --- Navigation query ---

func _handle_nav_query(params: Dictionary) -> void:
	var world := get_tree().root.get_world_3d()
	if world == null:
		_send_json_result("godotiq:nav_result", {
			"error": "No World3D available",
		}, params)
		return

	var map_rid: RID = world.get_navigation_map()
	var from_pos := Vector3.ZERO
	var to_pos := Vector3.ZERO

	# Resolve from position
	if params.has("from_node"):
		var from_node := _find_node_recursive(get_tree().root, str(params["from_node"]))
		if from_node == null or not (from_node is Node3D):
			_send_json_result("godotiq:nav_result", {
				"error": "from_node '%s' not found or not Node3D" % str(params["from_node"]),
			}, params)
			return
		from_pos = (from_node as Node3D).global_position
	elif params.has("from_position"):
		var fp: Array = params["from_position"]
		if fp.size() >= 3:
			from_pos = Vector3(float(fp[0]), float(fp[1]), float(fp[2]))

	# Resolve to position
	if params.has("to_node"):
		var to_node := _find_node_recursive(get_tree().root, str(params["to_node"]))
		if to_node == null or not (to_node is Node3D):
			_send_json_result("godotiq:nav_result", {
				"error": "to_node '%s' not found or not Node3D" % str(params["to_node"]),
			}, params)
			return
		to_pos = (to_node as Node3D).global_position
	elif params.has("to_position"):
		var tp: Array = params["to_position"]
		if tp.size() >= 3:
			to_pos = Vector3(float(tp[0]), float(tp[1]), float(tp[2]))

	# Snap to navmesh
	var closest_from := NavigationServer3D.map_get_closest_point(map_rid, from_pos)
	var closest_to := NavigationServer3D.map_get_closest_point(map_rid, to_pos)
	var from_on_nav: bool = from_pos.distance_to(closest_from) < 0.5
	var to_on_nav: bool = to_pos.distance_to(closest_to) < 0.5

	# Get path
	var optimize: bool = params.get("optimize", true)
	var path: PackedVector3Array = NavigationServer3D.map_get_path(
		map_rid, closest_from, closest_to, optimize
	)

	# Calculate distance
	var total_distance: float = 0.0
	var i: int = 0
	while i < path.size() - 1:
		total_distance += path[i].distance_to(path[i + 1])
		i += 1
	var direct_distance: float = from_pos.distance_to(to_pos)

	var efficiency: float = 0.0
	if total_distance > 0.001:
		efficiency = direct_distance / total_distance
	elif direct_distance < 0.001:
		efficiency = 1.0

	# Serialize path points (cap at 50)
	var path_points: Array = []
	var step: int = 1
	if path.size() > 50:
		step = int(ceil(float(path.size()) / 50.0))
	var idx: int = 0
	while idx < path.size():
		var p: Vector3 = path[idx]
		path_points.append([snapped(p.x, 0.01), snapped(p.y, 0.01), snapped(p.z, 0.01)])
		idx += step
	# Always include last point
	if path.size() > 0:
		var last: Vector3 = path[path.size() - 1]
		var last_arr: Array = [snapped(last.x, 0.01), snapped(last.y, 0.01), snapped(last.z, 0.01)]
		if path_points.size() == 0 or path_points[path_points.size() - 1] != last_arr:
			path_points.append(last_arr)

	_send_json_result("godotiq:nav_result", {
		"reachable": path.size() > 1,
		"distance": snapped(total_distance, 0.01),
		"direct_distance": snapped(direct_distance, 0.01),
		"efficiency_ratio": snapped(efficiency, 0.01),
		"path_points": path_points,
		"waypoint_count": path.size(),
		"from_on_navmesh": from_on_nav,
		"to_on_navmesh": to_on_nav,
		"from_position": [snapped(from_pos.x, 0.01), snapped(from_pos.y, 0.01), snapped(from_pos.z, 0.01)],
		"to_position": [snapped(to_pos.x, 0.01), snapped(to_pos.y, 0.01), snapped(to_pos.z, 0.01)],
	}, params)


# --- Watch system ---

func _handle_watch(params: Dictionary) -> void:
	var action: String = params.get("action", "")

	match action:
		"start":
			var watch_list: Array = params.get("watches", [])
			var interval_ms: int = params.get("sample_interval_ms", 500)
			_watch_sample_interval = interval_ms / 1000.0
			if _watch_sample_interval < 0.05:
				_watch_sample_interval = 0.05

			for w in watch_list:
				var node_name: String = w.get("node", "")
				var properties: Array = w.get("properties", [])
				if node_name.is_empty() or properties.is_empty():
					continue

				var node: Node = _find_node_recursive(get_tree().root, node_name)
				if node == null:
					node = get_tree().root.get_node_or_null(node_name)
				if node == null:
					node = get_tree().root.get_node_or_null("/root/" + node_name)

				if node == null:
					_watch_events.append({
						"t": snapped(Time.get_ticks_msec() / 1000.0, 0.001),
						"node": node_name,
						"error": "Node not found",
					})
					continue

				var initial_values: Dictionary = {}
				for prop in properties:
					initial_values[prop] = _get_watch_value(node, prop)

				_watches[node_name] = {
					"node": node,
					"properties": properties,
					"last_values": initial_values,
				}

			_watch_active = true
			_send_json_result("godotiq:watch_result", {
				"action": "start",
				"watches_active": _watches.size(),
				"sample_interval_ms": int(_watch_sample_interval * 1000),
			}, params)

		"stop":
			_watches.clear()
			_watch_active = false
			_send_json_result("godotiq:watch_result", {
				"action": "stop",
				"watches_active": 0,
			}, params)

		"read":
			var events_copy: Array = _watch_events.duplicate()
			_send_json_result("godotiq:watch_result", {
				"action": "read",
				"events": events_copy,
				"events_total": events_copy.size(),
				"watches_active": _watches.size(),
			}, params)

		"clear":
			_watch_events.clear()
			_send_json_result("godotiq:watch_result", {
				"action": "clear",
				"events_cleared": true,
				"watches_active": _watches.size(),
			}, params)

		_:
			_send_json_result("godotiq:watch_result", {
				"error": "Unknown action: %s. Use start/stop/read/clear." % action,
			}, params)


func _sample_watched_nodes() -> void:
	var now: float = snapped(Time.get_ticks_msec() / 1000.0, 0.001)
	var to_remove: Array = []

	for node_name in _watches.keys():
		var watch: Dictionary = _watches[node_name]
		var node: Node = watch["node"]

		if not is_instance_valid(node):
			_watch_events.append({
				"t": now,
				"node": node_name,
				"error": "Node freed",
			})
			to_remove.append(node_name)
			continue

		var properties: Array = watch["properties"]
		var last_values: Dictionary = watch["last_values"]

		for prop in properties:
			var current_val = _get_watch_value(node, prop)
			var last_val = last_values.get(prop)
			if str(current_val) != str(last_val):
				_watch_events.append({
					"t": now,
					"node": node_name,
					"property": prop,
					"from": _serialize_watch_value(last_val),
					"to": _serialize_watch_value(current_val),
				})
				last_values[prop] = current_val

	for name in to_remove:
		_watches.erase(name)

	# Cap events to prevent memory issues
	if _watch_events.size() > 1000:
		_watch_events = _watch_events.slice(_watch_events.size() - 500)


func _get_watch_value(node: Node, prop_name: String) -> Variant:
	# Handle method calls like "pending_orders.size()"
	if prop_name.ends_with("()"):
		var parts: Array = prop_name.split(".")
		if parts.size() == 2:
			var obj = node.get(parts[0])
			var method_name: String = parts[1].replace("()", "")
			if obj != null:
				if obj is Array and method_name == "size":
					return obj.size()
				elif obj is Dictionary and method_name == "size":
					return obj.size()
				elif obj.has_method(method_name):
					return obj.call(method_name)
		return null
	# Sub-path like "position:x"
	if ":" in prop_name:
		return node.get_indexed(prop_name)
	return node.get(prop_name)


func _serialize_watch_value(val) -> Variant:
	if val == null:
		return null
	if val is int or val is float or val is String or val is bool:
		return val
	if val is Vector3:
		return [snapped(val.x, 0.01), snapped(val.y, 0.01), snapped(val.z, 0.01)]
	if val is Vector2:
		return [snapped(val.x, 0.01), snapped(val.y, 0.01)]
	return str(val)


# --- UI Map ---

func _handle_ui_map(params: Dictionary) -> void:
	var root_name: String = params.get("root", "")
	var include_invisible: bool = params.get("include_invisible", false)
	var max_depth: int = clampi(int(params.get("max_depth", 10)), 0, 20)
	var detail: String = params.get("detail", "normal")
	var budget := _make_traversal_budget(params)
	var root_search_visited := 0

	var root_node: Node = null
	if root_name.is_empty():
		root_node = get_tree().root
	else:
		root_node = get_tree().root.get_node_or_null(root_name)
		if root_node == null:
			root_node = get_tree().root.get_node_or_null("/root/" + root_name)
		if root_node == null:
			var root_search := _find_node_by_name_limited(
				get_tree().root,
				root_name,
				budget["max_visited"]
			)
			root_node = root_search.get("node")
			root_search_visited = root_search.get("visited", 0)

	if root_node == null:
		_send_json_result("godotiq:ui_map_result", {
			"error": "Root node '%s' not found" % root_name,
		}, params)
		return

	var layout: Array = []
	_walk_ui_tree(root_node, layout, 0, max_depth, include_invisible, detail, budget)

	var interactive_count: int = 0
	var touch_too_small: Array = []
	var total_controls: int = _count_ui_controls(layout)

	_collect_ui_stats_flat(layout, touch_too_small)
	interactive_count = _count_interactive(layout)

	_send_json_result("godotiq:ui_map_result", {
		"root": str(root_node.name),
		"total_controls": total_controls,
		"interactive_elements": interactive_count,
		"touch_targets_too_small": touch_too_small,
		"visited_nodes": budget["visited"],
		"returned_nodes": budget["output"],
		"root_search_visited": root_search_visited,
		"truncated": budget["truncated"],
		"max_visited_nodes": budget["max_visited"],
		"max_output_nodes": budget["max_output"],
		"layout": layout,
	}, params)


func _walk_ui_tree(node: Node, result: Array, depth: int, max_depth: int, include_invisible: bool, detail: String, budget: Dictionary) -> void:
	if depth > max_depth or budget["truncated"] or not is_instance_valid(node):
		return
	if budget["visited"] >= budget["max_visited"]:
		budget["truncated"] = true
		return
	budget["visited"] += 1

	if node is Control:
		var ctrl: Control = node as Control

		if not include_invisible and not ctrl.is_visible_in_tree():
			return
		if budget["output"] >= budget["max_output"]:
			budget["truncated"] = true
			return
		budget["output"] += 1

		var item: Dictionary = {
			"name": str(ctrl.name),
			"type": ctrl.get_class(),
			"visible": ctrl.is_visible_in_tree(),
		}

		var rect: Rect2 = ctrl.get_global_rect()
		item["rect"] = [
			int(rect.position.x), int(rect.position.y),
			int(rect.position.x + rect.size.x), int(rect.position.y + rect.size.y)
		]
		item["size"] = [int(rect.size.x), int(rect.size.y)]

		if ctrl is Label:
			item["text"] = (ctrl as Label).text.left(100)
		elif ctrl is BaseButton:
			item["interactive"] = true
			if ctrl is Button:
				item["text"] = (ctrl as Button).text.left(100)
			item["disabled"] = (ctrl as BaseButton).disabled
		elif ctrl is RichTextLabel:
			item["text"] = (ctrl as RichTextLabel).get_parsed_text().left(100)
		elif ctrl is LineEdit:
			item["text"] = (ctrl as LineEdit).text.left(100)
			item["interactive"] = true
			item["placeholder"] = (ctrl as LineEdit).placeholder_text.left(50)
		elif ctrl is TextEdit:
			item["text"] = (ctrl as TextEdit).text.left(100)
			item["interactive"] = true

		if ctrl is Slider:
			item["interactive"] = true
			item["value"] = (ctrl as Slider).value
		elif ctrl is SpinBox:
			item["interactive"] = true
			item["value"] = (ctrl as SpinBox).value

		if detail == "full":
			item["modulate"] = [ctrl.modulate.r, ctrl.modulate.g, ctrl.modulate.b, ctrl.modulate.a]
			item["mouse_filter"] = ctrl.mouse_filter
			if ctrl.get_script() != null:
				var script_res: Script = ctrl.get_script()
				var script_path: String = ""
				if script_res.resource_path:
					script_path = script_res.resource_path
				item["script"] = script_path

		var children: Array = []
		for child in node.get_children():
			_walk_ui_tree(child, children, depth + 1, max_depth, include_invisible, detail, budget)
			if budget["truncated"]:
				break

		if not children.is_empty():
			item["children"] = children

		result.append(item)

	elif node is CanvasLayer:
		if budget["output"] >= budget["max_output"]:
			budget["truncated"] = true
			return
		budget["output"] += 1
		var layer_item: Dictionary = {
			"name": str(node.name),
			"type": "CanvasLayer",
			"layer": (node as CanvasLayer).layer,
		}
		var children: Array = []
		for child in node.get_children():
			_walk_ui_tree(child, children, depth + 1, max_depth, include_invisible, detail, budget)
			if budget["truncated"]:
				break
		if not children.is_empty():
			layer_item["children"] = children
		result.append(layer_item)

	else:
		for child in node.get_children():
			_walk_ui_tree(child, result, depth + 1, max_depth, include_invisible, detail, budget)
			if budget["truncated"]:
				break


func _count_ui_controls(items: Array) -> int:
	var count: int = 0
	for item in items:
		if item is Dictionary:
			var item_type: String = item.get("type", "")
			if item_type != "CanvasLayer":
				count += 1
			if item.has("children"):
				count += _count_ui_controls(item["children"])
	return count


func _count_interactive(items: Array) -> int:
	var count: int = 0
	for item in items:
		if item is Dictionary:
			if item.get("interactive", false):
				count += 1
			if item.has("children"):
				count += _count_interactive(item["children"])
	return count


func _collect_ui_stats_flat(items: Array, touch_too_small: Array) -> void:
	for item in items:
		if item is Dictionary:
			if item.get("interactive", false):
				var size: Array = item.get("size", [0, 0])
				if size.size() >= 2:
					var min_px: int = 48
					if size[0] < min_px or size[1] < min_px:
						touch_too_small.append({
							"node": item.get("name", ""),
							"size": size,
							"min_recommended": [min_px, min_px],
						})
			if item.has("children"):
				_collect_ui_stats_flat(item["children"], touch_too_small)


# --- Explore camera ---

func _handle_explore_camera(params: Dictionary) -> void:
	var action: String = params.get("action", "")
	var scene_root := get_tree().root
	if scene_root == null:
		_send_json_result("godotiq:explore_camera_result", {
			"error": "No scene tree root available",
			"code": "NO_SCENE_ROOT",
		}, params)
		return

	match action:
		"create":
			# Clean up any existing drone camera first (use free() not queue_free()
			# to avoid name deduplication when the new drone is added immediately)
			var existing = scene_root.get_node_or_null("GodotIQ_DroneCam")
			if existing:
				existing.free()

			# Store reference to current camera before switching
			var original_cam: Camera3D = get_viewport().get_camera_3d()
			var original_cam_path := ""
			if original_cam:
				original_cam_path = str(scene_root.get_path_to(original_cam))

			# Create drone
			var drone := Camera3D.new()
			drone.name = "GodotIQ_DroneCam"
			drone.set_meta("original_camera_path", original_cam_path)
			drone.fov = float(params.get("fov", 70.0))
			scene_root.add_child(drone)
			drone.make_current()

			_send_json_result("godotiq:explore_camera_result", {
				"status": "created",
				"original_camera": original_cam_path,
			}, params)

		"move":
			var drone = scene_root.get_node_or_null("GodotIQ_DroneCam")
			if drone == null:
				_send_json_result("godotiq:explore_camera_result", {
					"error": "GodotIQ_DroneCam not found",
					"code": "DRONE_NOT_FOUND",
				}, params)
				return

			var pos: Array = params.get("position", [0, 0, 0])
			drone.global_position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))

			if params.has("look_at"):
				var target_arr: Array = params["look_at"]
				var target := Vector3(float(target_arr[0]), float(target_arr[1]), float(target_arr[2]))
				var dist: float = drone.global_position.distance_to(target)
				if dist > 0.001:
					var direction: Vector3 = (target - drone.global_position).normalized()
					if abs(direction.dot(Vector3.UP)) > 0.99:
						drone.look_at(target, Vector3.FORWARD)
					else:
						drone.look_at(target, Vector3.UP)
			elif params.has("rotation"):
				var rot: Array = params["rotation"]
				drone.rotation_degrees = Vector3(float(rot[0]), float(rot[1]), float(rot[2]))

			if params.has("fov"):
				drone.fov = float(params["fov"])

			_send_json_result("godotiq:explore_camera_result", {
				"status": "moved",
				"position": [drone.global_position.x, drone.global_position.y, drone.global_position.z],
				"rotation": [drone.rotation_degrees.x, drone.rotation_degrees.y, drone.rotation_degrees.z],
			}, params)

		"destroy":
			var drone = scene_root.get_node_or_null("GodotIQ_DroneCam")
			if drone == null:
				_send_json_result("godotiq:explore_camera_result", {
					"status": "destroyed",
				}, params)
				return

			var original_path: String = drone.get_meta("original_camera_path", "")
			if original_path != "":
				var original_cam = scene_root.get_node_or_null(original_path)
				if is_instance_valid(original_cam) and original_cam is Camera3D:
					original_cam.make_current()

			drone.queue_free()

			_send_json_result("godotiq:explore_camera_result", {
				"status": "destroyed",
			}, params)

		_:
			_send_json_result("godotiq:explore_camera_result", {
				"error": "Unknown action: %s" % action,
				"code": "UNKNOWN_ACTION",
			}, params)


# --- Query Scene Tree (running game) ---

func _handle_query_scene_tree(params: Dictionary) -> void:
	await get_tree().process_frame
	var root_path: String = str(params.get("root", ""))
	var max_depth: int = clampi(int(params.get("depth", 3)), 0, 20)
	var filter_type: String = str(params.get("filter_type", ""))
	var budget := _make_traversal_budget(params)

	var root_node: Node = get_tree().root
	if not root_path.is_empty():
		root_node = get_tree().root.get_node_or_null(root_path)
		if root_node == null:
			_send_json_result("godotiq:query_scene_tree_result", {
				"error": "Node not found: %s" % root_path,
				"code": "NODE_NOT_FOUND",
			}, params)
			return

	var nodes: Array = []
	_collect_scene_tree(root_node, max_depth, filter_type, 0, nodes, budget)
	_send_json_result("godotiq:query_scene_tree_result", {
		"root": str(root_node.get_path()),
		"node_count": nodes.size(),
		"visited_nodes": budget["visited"],
		"truncated": budget["truncated"],
		"max_visited_nodes": budget["max_visited"],
		"max_output_nodes": budget["max_output"],
		"nodes": nodes,
	}, params)


func _make_traversal_budget(params: Dictionary) -> Dictionary:
	return {
		"visited": 0,
		"output": 0,
		"truncated": false,
		"max_visited": clampi(
			int(params.get("max_visited_nodes", RUNTIME_DEFAULT_MAX_VISITED_NODES)),
			1,
			RUNTIME_HARD_MAX_VISITED_NODES
		),
		"max_output": clampi(
			int(params.get("max_output_nodes", RUNTIME_DEFAULT_MAX_OUTPUT_NODES)),
			1,
			RUNTIME_HARD_MAX_OUTPUT_NODES
		),
	}


func _collect_scene_tree(node: Node, max_depth: int, filter_type: String, current_depth: int, result: Array, budget: Dictionary) -> void:
	if not is_instance_valid(node) or current_depth > max_depth or budget["truncated"]:
		return
	if budget["visited"] >= budget["max_visited"]:
		budget["truncated"] = true
		return
	budget["visited"] += 1

	var node_info := _describe_game_node(node)
	if filter_type.is_empty() or node.is_class(filter_type):
		if budget["output"] >= budget["max_output"]:
			budget["truncated"] = true
			return
		result.append(node_info)
		budget["output"] += 1

	var children := node.get_children()
	for child in children:
		if is_instance_valid(child):
			_collect_scene_tree(child, max_depth, filter_type, current_depth + 1, result, budget)
			if budget["truncated"]:
				break


func _describe_game_node(node: Node) -> Dictionary:
	if not is_instance_valid(node):
		return {"name": "<freed>", "type": "Unknown", "path": "", "child_count": 0}
	var info := {
		"name": str(node.name),
		"type": node.get_class(),
		"path": str(node.get_path()) if node.is_inside_tree() else "",
		"child_count": node.get_child_count(),
	}
	if node is Control:
		info["visible"] = node.visible
		if node.is_inside_tree():
			info["position"] = [node.global_position.x, node.global_position.y]
		info["size"] = [node.size.x, node.size.y]
		if node is Button:
			info["disabled"] = node.disabled
			info["text"] = node.text
	elif node is Node2D:
		if node.is_inside_tree():
			info["position"] = [node.global_position.x, node.global_position.y]
	elif node is Node3D:
		if node.is_inside_tree():
			info["position"] = [node.global_position.x, node.global_position.y, node.global_position.z]
	return info


# --- Press Button (running game) ---

func _handle_press_button(params: Dictionary) -> void:
	await get_tree().process_frame
	var button_name: String = str(params.get("name", ""))
	if button_name.is_empty():
		_send_json_result("godotiq:press_button_result", {
			"error": "Missing required parameter: name",
			"code": "MISSING_PARAM",
		}, params)
		return

	var root_path: String = str(params.get("root", ""))
	var search_root: Node = get_tree().root
	if not root_path.is_empty():
		search_root = get_tree().root.get_node_or_null(root_path)
		if search_root == null:
			_send_json_result("godotiq:press_button_result", {
				"error": "Root node not found: %s" % root_path,
				"code": "NODE_NOT_FOUND",
			}, params)
			return

	var max_visited := clampi(
		int(params.get("max_visited_nodes", RUNTIME_DEFAULT_MAX_VISITED_NODES)),
		1,
		RUNTIME_HARD_MAX_VISITED_NODES
	)
	var button_search := _find_button_limited(search_root, button_name, max_visited)
	var button: Button = button_search.get("node")
	if button == null:
		_send_json_result("godotiq:press_button_result", {
			"error": "Button not found: %s" % button_name,
			"code": "BUTTON_NOT_FOUND",
			"visited_nodes": button_search["visited"],
			"truncated": button_search["truncated"],
		}, params)
		return

	if button.disabled:
		_send_json_result("godotiq:press_button_result", {
			"error": "Button is disabled: %s" % button_name,
			"code": "BUTTON_DISABLED",
		}, params)
		return

	# Save info before emit — pressed signal may trigger scene change, freeing button
	var btn_name := str(button.name)
	var btn_path := str(button.get_path()) if button.is_inside_tree() else ""
	var btn_text := button.text
	button.emit_signal("pressed")
	_send_json_result("godotiq:press_button_result", {
		"status": "pressed",
		"name": btn_name,
		"path": btn_path,
		"text": btn_text,
		"visited_nodes": button_search["visited"],
	}, params)


func _handle_find_node(params: Dictionary) -> void:
	await get_tree().process_frame
	var target_name: String = str(params.get("name", ""))
	if target_name.is_empty():
		_send_json_result("godotiq:find_node_result", {
			"error": "Missing required parameter: name",
			"code": "MISSING_PARAM",
		}, params)
		return

	var root_path: String = str(params.get("root", ""))
	var search_root: Node = get_tree().root
	if not root_path.is_empty():
		search_root = get_tree().root.get_node_or_null(root_path)
		if search_root == null:
			_send_json_result("godotiq:find_node_result", {
				"error": "Root node not found: %s" % root_path,
				"code": "NODE_NOT_FOUND",
			}, params)
			return

	var max_visited := clampi(
		int(params.get("max_visited_nodes", RUNTIME_DEFAULT_MAX_VISITED_NODES)),
		1,
		RUNTIME_HARD_MAX_VISITED_NODES
	)
	var search := _find_node_by_name_limited(search_root, target_name, max_visited)
	var found: Node = search.get("node")
	if found == null:
		_send_json_result("godotiq:find_node_result", {
			"found": false,
			"name": target_name,
			"visited_nodes": search["visited"],
			"truncated": search["truncated"],
		}, params)
		return

	_send_json_result("godotiq:find_node_result", {
		"found": true,
		"node": _describe_game_node(found),
		"visited_nodes": search["visited"],
		"truncated": false,
	}, params)


func _find_node_by_name_limited(root: Node, target_name: String, max_visited: int) -> Dictionary:
	var queue: Array[Node] = [root]
	var cursor := 0
	var visited := 0
	var queue_truncated := false
	while cursor < queue.size() and visited < max_visited:
		var node := queue[cursor]
		cursor += 1
		if not is_instance_valid(node):
			continue
		visited += 1
		if str(node.name) == target_name:
			return {"node": node, "visited": visited, "truncated": false}
		var remaining_capacity := max_visited - visited - (queue.size() - cursor)
		for child in node.get_children():
			if remaining_capacity <= 0:
				queue_truncated = true
				break
			if is_instance_valid(child):
				queue.append(child)
				remaining_capacity -= 1
	return {"node": null, "visited": visited, "truncated": queue_truncated or cursor < queue.size()}


func _find_button_limited(root: Node, target_name: String, max_visited: int) -> Dictionary:
	var queue: Array[Node] = [root]
	var cursor := 0
	var visited := 0
	var queue_truncated := false
	while cursor < queue.size() and visited < max_visited:
		var node := queue[cursor]
		cursor += 1
		if not is_instance_valid(node):
			continue
		visited += 1
		if node is Button:
			var button := node as Button
			var button_text := str(button.text).strip_edges()
			if str(button.name) == target_name or (not button_text.is_empty() and button_text == target_name):
				return {"node": button, "visited": visited, "truncated": false}
		var remaining_capacity := max_visited - visited - (queue.size() - cursor)
		for child in node.get_children():
			if remaining_capacity <= 0:
				queue_truncated = true
				break
			if is_instance_valid(child):
				queue.append(child)
				remaining_capacity -= 1
	return {"node": null, "visited": visited, "truncated": queue_truncated or cursor < queue.size()}
