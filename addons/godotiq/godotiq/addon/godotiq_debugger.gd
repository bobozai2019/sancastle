@tool
extends EditorDebuggerPlugin
## GodotIQ editor-side debugger plugin — bridges EngineDebugger messages
## between the running game and the WebSocket server.

var server  # untyped to avoid circular dependency — set by godotiq_plugin.gd
var _connected_sessions: Dictionary = {}
var _active_sessions: Dictionary = {}


func _has_capture(prefix: String) -> bool:
	return prefix == "godotiq"


func _capture(message: String, data: Array, session_id: int) -> bool:
	if server == null:
		push_warning("GodotIQ debugger: received message but server is null")
		return false
	match message:
		"godotiq:screenshot_result":
			server.handle_game_response("godotiq:screenshot", data, session_id)
			return true
		"godotiq:perf_result":
			server.handle_game_response("godotiq:query_perf", data, session_id)
			return true
		"godotiq:state_result":
			server.handle_game_response("godotiq:query_state", data, session_id)
			return true
		"godotiq:input_result":
			server.handle_game_response("godotiq:input", data, session_id)
			return true
		"godotiq:exec_result":
			server.handle_game_response("godotiq:exec", data, session_id)
			return true
		"godotiq:nav_result":
			server.handle_game_response("godotiq:query_nav", data, session_id)
			return true
		"godotiq:watch_result":
			server.handle_game_response("godotiq:watch", data, session_id)
			return true
		"godotiq:ui_map_result":
			server.handle_game_response("godotiq:query_ui_map", data, session_id)
			return true
		"godotiq:explore_camera_result":
			server.handle_game_response("godotiq:explore_camera", data, session_id)
			return true
		"godotiq:query_scene_tree_result":
			server.handle_game_response("godotiq:query_scene_tree", data, session_id)
			return true
		"godotiq:press_button_result":
			server.handle_game_response("godotiq:press_button", data, session_id)
			return true
		"godotiq:find_node_result":
			server.handle_game_response("godotiq:find_node", data, session_id)
			return true
		"godotiq:error":
			if data.size() >= 1:
				server._record_error(str(data[0]))
			server.send_event("runtime_error", {"data": data, "session_id": session_id})
			return true
		"godotiq:watch_update":
			server.send_event("watch_update", {"data": data, "session_id": session_id})
			return true
		_:
			push_warning("GodotIQ debugger: unknown message '%s'" % message)
			return false


func _setup_session(session_id: int) -> void:
	if _connected_sessions.has(session_id):
		return

	var session := get_session(session_id)
	if session == null:
		push_warning("GodotIQ debugger: could not get session %d" % session_id)
		return

	session.started.connect(_on_game_started.bind(session_id))
	session.stopped.connect(_on_game_stopped.bind(session_id))
	_connected_sessions[session_id] = true


func _on_game_started(session_id: int) -> void:
	_active_sessions[session_id] = true
	if server:
		server.on_game_started(session_id)


func _on_game_stopped(session_id: int) -> void:
	_active_sessions.erase(session_id)
	if server:
		server.on_game_stopped(session_id)


func get_active_session_ids() -> Array:
	var ids: Array = _active_sessions.keys()
	ids.sort()
	return ids


func has_active_session(session_id: int) -> bool:
	return _active_sessions.has(session_id)


func get_default_session_id() -> int:
	var ids := get_active_session_ids()
	if ids.is_empty():
		return -1
	return int(ids[0])


func get_session_count() -> int:
	return _active_sessions.size()


func get_last_send_error() -> String:
	return ""


func send_to_game(message: String, data: Array, session_id: int = -1) -> bool:
	var target_session_id := session_id
	if target_session_id < 0:
		var active_ids := get_active_session_ids()
		if active_ids.size() != 1:
			push_warning("GodotIQ debugger: session_id required for '%s'" % message)
			return false
		target_session_id = int(active_ids[0])

	if not _active_sessions.has(target_session_id):
		push_warning("GodotIQ debugger: session %d not active for '%s'" % [target_session_id, message])
		return false

	var session := get_session(target_session_id)
	if session == null:
		push_warning("GodotIQ debugger: session %d not found" % target_session_id)
		_active_sessions.erase(target_session_id)
		return false

	session.send_message(message, data)
	return true
