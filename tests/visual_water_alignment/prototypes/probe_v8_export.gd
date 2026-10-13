extends Node

const FIXED_SCENE := preload("res://scenes/water_render_demo_v8_preview.tscn")
const COUPLED_SCENE := preload("res://scenes/water_render_coupled_v8_preview.tscn")
const PROFILE_PATH := "res://tests/visual_water_alignment/prototypes/water_render_staging_v8.json"
const EXPECTED_PROFILE_SHA := "12be141c4f0c9a1366b698fc79978a4bc4f884d42a34e0458d23e539ee42e04b"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var profile_path := PROFILE_PATH
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--profile="):
			profile_path = arg.trim_prefix("--profile=")
	var expected_sha := FileAccess.get_sha256(profile_path)
	if expected_sha.is_empty() or (profile_path == PROFILE_PATH and \
			expected_sha != EXPECTED_PROFILE_SHA):
		_fail("profile source mismatch")
		return
	for entry in [{"name": "fixed", "scene": FIXED_SCENE},
			{"name": "coupled", "scene": COUPLED_SCENE}]:
		var preview: Node3D = entry.scene.instantiate()
		preview.render_profile_path = profile_path
		preview.staging_wave_workload = "single_packet_v1"
		get_tree().root.add_child(preview)
		var frames := 0
		while not preview.ready_for_ticks and preview.last_error.is_empty() and frames < 1800:
			await get_tree().process_frame
			frames += 1
		if not preview.ready_for_ticks or not preview.last_error.is_empty():
			_fail("%s initialization: %s" % [entry.name, preview.last_error])
			return
		if preview.requested_render_profile_sha256 != expected_sha or \
				preview.staging_wave_workload != "single_packet_v1" or \
				preview.wave_requests.size() != 1 or \
				int(preview.wave_requests[0].start_tick) != 8 or \
				int(preview.wave_requests[0].seed) != 31:
			_fail("%s profile or wave workload mismatch" % entry.name)
			return
		var visual: Dictionary = preview.requested_render_profile.visual
		if preview.prototype_offshore_core_source_gate != visual.get("offshore_core", false) or \
				preview.water_material.get_shader_parameter("prototype_offshore_core") != \
				visual.get("offshore_core", false) or \
				preview.water_material.get_shader_parameter("prototype_offshore_core_broken") != \
				visual.get("offshore_core_broken", false):
			_fail("%s offshore core profile mismatch" % entry.name)
			return
		if preview.requested_render_profile.schema_version >= 3 and \
				preview.water_material.get_shader_parameter("prototype_offshore_core_crown") != \
				visual.get("offshore_core_crown", false):
			_fail("%s crown profile mismatch" % entry.name)
			return
		if preview.requested_render_profile.schema_version >= 4 and \
				preview.effective_render_profile.get("reference_bed", "") != \
				preview.requested_render_profile.reference_bed:
			_fail("%s reference bed profile mismatch" % entry.name)
			return
		if preview.requested_render_profile.schema_version >= 5 and \
				preview.effective_render_profile.get("shallow_preserve", false) != \
				visual.shallow_preserve:
			_fail("%s shallow preserve profile mismatch" % entry.name)
			return
		if preview.requested_render_profile.schema_version >= 8 and \
				(preview.effective_render_profile.get("planar_reflection") != true or \
				preview.effective_render_profile.get("reflection_texture_width") != 960 or \
				preview.effective_render_profile.get("reflection_texture_height") != 540 or \
				preview.get_node_or_null("ReflectionRockEnvironment") == null):
			_fail("%s reflection profile mismatch" % entry.name)
			return
		var pattern: Texture2D = preview.terrain_material.get_shader_parameter(
			"caustic_pattern")
		if pattern == null or pattern.get_width() != 1024 or \
				pattern.get_height() != 1024:
			_fail("%s caustic pattern missing" % entry.name)
			return
		frames = 0
		while preview.completed_ticks < 30 and preview.last_error.is_empty() and frames < 3600:
			await get_tree().process_frame
			frames += 1
		preview.playing = false
		while preview.tick_pending and frames < 3900:
			await get_tree().process_frame
			frames += 1
		if not preview.last_error.is_empty() or preview.completed_ticks < 30 or \
				preview.effective_render_profile.is_empty() or \
				not is_equal_approx(preview.visual_time_s,
					float(preview.completed_ticks) / 30.0):
			_fail("%s tick or effective profile mismatch" % entry.name)
			return
		print("EXPORT_CASE_PASS %s tick=%d profile=%s bed=%s workload=%s caustic=%dx%d" % [
			entry.name, preview.completed_ticks,
			preview.requested_render_profile_sha256,
			preview.effective_render_profile.get("reference_bed", "legacy"),
			preview.staging_wave_workload, pattern.get_width(), pattern.get_height()])
		if entry.name == "fixed":
			preview.queue_free()
			for settle_frame in range(12):
				await get_tree().process_frame
	print("PASS: W08 staging exported package fixed/coupled")
	get_tree().call_deferred("quit", 0)


func _fail(message: String) -> void:
	push_error("FAIL: W08 staging exported package " + message)
	get_tree().quit(1)

