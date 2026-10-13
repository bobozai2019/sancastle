extends SceneTree

func _initialize() -> void:
	var enums := {}
	for name in ClassDB.class_get_enum_constants("RenderingServer","ShadowQuality"):
		enums[name] = ClassDB.class_get_integer_constant("RenderingServer",name)
	var methods := {}
	for method in ClassDB.class_get_method_list("RenderingServer"):
		if String(method.name) in ["directional_soft_shadow_filter_set_quality","viewport_set_measure_render_time","viewport_get_measured_render_time_gpu","viewport_get_measured_render_time_cpu","set_render_loop_enabled"]:
			methods[method.name] = method
	var result := {"shadow_enum":enums,"methods":methods,
		"project_directional_quality":ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality"),
		"max_fps":Engine.max_fps,"low_processor_usage_mode":OS.low_processor_usage_mode}
	var file := FileAccess.open("res://test_output/water_material_natural/renderer_api.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"));file.close()
	print(JSON.stringify(result))
	quit(0)
