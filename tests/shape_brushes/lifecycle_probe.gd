extends "res://tests/shape_brushes/formal_scene_probe.gd"
func _run() -> void:
	root.size=Vector2i(1280,720);pair_fields=27;service=root.get_node("BeachScenes")
	preview=load("res://scenes/main.tscn").instantiate();preview.playing=false;root.add_child(preview);current_scene=preview
	if not await wait_ready():_finish();quit(1);return
	preview.get_node("Interface/PerformancePanel/Margin/Rows/Header/Sampling").button_pressed=false
	preview._apply_brush_selection({"tool":"wall_v1","parameters":{"height_m":0.2,"bottom_width_m":1.0,"top_width_m":0.5},"dig_amount_m3":0.02,"fill_amount_m3":0.01})
	for i in 12:
		var key:String=["test1_capture","test1_backwash","main"][i%3]
		if not await switch_to(key):_finish();quit(1);return
		_check("lifecycle_fixed_resources",preview.shape_gpu.statistics().rid_count==69 and preview.preview_query.owned.size()==4 and preview.collision_proxy.shapes.size()<=64)
		print("LIFECYCLE_PROGRESS ",i+1)
	for i in 2:
		var query=preview.preview_query;var water=preview.shape_gpu.water_transaction
		await preview.get_node("Interface/PerformancePanel").stop_sampling();await preview.shutdown();preview.queue_free();current_scene=null;await process_frame;await RenderingServer.frame_post_draw;await process_frame
		_check("reopen_old_resources_released",query.rd==null and query.owned.is_empty() and water.rd==null and water.owned.is_empty())
		preview=load("res://scenes/main.tscn").instantiate();preview.playing=false;root.add_child(preview);current_scene=preview
		if not await wait_ready():_finish();quit(1);return
		_check("reopen_resources_fixed",preview.shape_gpu.statistics().rid_count==69 and preview.preview_query.owned.size()==4)
	await preview.get_node("Interface/PerformancePanel").stop_sampling();await preview.shutdown();preview.queue_free();await process_frame
	_finish();var passed:=true
	for row in checks:passed=passed and row.pass
	quit(0 if passed else 1)
