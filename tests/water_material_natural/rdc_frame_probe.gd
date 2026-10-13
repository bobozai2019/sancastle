extends "res://tests/water_material_natural/common_checkpoint_cost.gd"

func _lighting_sweep(_before: Dictionary) -> void:
	preview.playing=false;preview.replay_target_tick=-1;preview.set_fixture_camera(&"close")
	for i in range(60):await process_frame;await RenderingServer.frame_post_draw
	var nodes:={}
	for name in ["GpuWaterSurface","GpuSandTerrain","ShoreContactOverlay","PrototypeFrontFoamDense"]:
		var node:MeshInstance3D=preview.get_node(name)
		nodes[name]={"cast_shadow":node.cast_shadow,"layers":node.layers,"visible":node.visible,"shader":node.material_override.shader.resource_path}
	var file:=FileAccess.open(output+"/capture_ready.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"pid":OS.get_process_id(),"tick":preview.completed_ticks,"generation":preview.generation,"visual_time_s":preview.visual_time_s,"window_size":root.size,"nodes":nodes},"\t"));file.close()
	var deadline:=Time.get_ticks_msec()+60000
	while not FileAccess.file_exists(output+"/capture_go.json"):
		await process_frame
		if Time.get_ticks_msec()>deadline:_fail("capture coordination timeout");return
	for i in range(60):await process_frame;await RenderingServer.frame_post_draw
	file=FileAccess.open(output+"/capture_complete.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"pid":OS.get_process_id(),"tick":preview.completed_ticks,"visual_time_s":preview.visual_time_s}));file.close()
