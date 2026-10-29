extends SceneTree


func _init() -> void:
	call_deferred("_probe")


func _probe() -> void:
	await process_frame
	print("PROFILE viewport=%s window=%s renderer=%s vsync=%s" % [
		str(root.size), str(DisplayServer.window_get_size()),
		str(ProjectSettings.get_setting("rendering/renderer/rendering_method")),
		str(DisplayServer.window_get_vsync_mode())])
	if root.size != Vector2i(1920, 1080) or DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED:
		printerr("FAIL: target resolution or VSync mismatch")
		quit(1)
		return
	print("PASS: target 1080p VSync-off profile")
	quit(0)
