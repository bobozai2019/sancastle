extends "res://tests/integration/free_tools_camera_probe.gd"

func _run() -> void:
	root.size=Vector2i(1280,720)
	service=root.get_node("BeachScenes")
	scene=load("res://scenes/main.tscn").instantiate()
	scene.gravel_enabled=not "--gravel-disabled" in OS.get_cmdline_user_args()
	scene.playing=false
	root.add_child(scene)
	current_scene=scene
	if not await _ready_scene(): _finish(1);return
	if not "--skip-camera" in OS.get_cmdline_user_args(): await _camera()
	var fill := await _click("FillTool",0.1)
	check("gravel_fill_receipt",absf(float(fill.get("actual_sand_m3",0.0))-0.1)<0.00001)
	await _click("DigTool",0.1)
	var revision_ok: bool=scene.gravel_field.revision==scene.solver.state_revision if scene.gravel_enabled else scene.gravel_field==null
	check("gravel_presentation_matches_collision_revision",revision_ok and scene.last_error.is_empty())
	await scene.shutdown()
	check("clean_shutdown",scene.gpu_release_done and scene.gravel_field==null)
	_finish(0)
