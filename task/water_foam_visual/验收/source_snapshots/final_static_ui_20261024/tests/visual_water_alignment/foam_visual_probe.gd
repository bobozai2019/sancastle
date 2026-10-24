extends "res://docs/competitor/tools/probe_foam_comparison.gd"

# Continuous fixed-completion sequence, distinct from all performance runs.
func _run() -> void:
	orphan_baseline=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	DisplayServer.window_set_size(Vector2i(1280,720))
	scene=load("res://scenes/main.tscn" if scene_key=="main" else "res://scenes/playable/test1_geometry.tscn").instantiate()
	scene.playing=false;scene.generation=1001;root.add_child(scene)
	var deadline:=Time.get_ticks_msec()+90000
	while (not scene.ready_for_ticks or scene._booting) and scene.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check("entry_ready",scene.ready_for_ticks and scene.last_error.is_empty())
	if not scene.ready_for_ticks:await _close();return
	scene.hide_hud=true;scene.get_node("Interface").hide()
	observations.configuration=scene.configuration.duplicate(true)
	observations.render={"size":var_to_str(root.size),"adapter":RenderingServer.get_video_adapter_name(),"engine":Engine.get_version_info(),"driver":RenderingServer.get_current_rendering_driver_name()}
	observations.camera={"transform":var_to_str(scene.get_viewport().get_camera_3d().global_transform),"fov":scene.get_viewport().get_camera_3d().fov}
	observations.geometry={}
	for key in ["GpuWaterSurface","GpuSandTerrain"]:
		var node: MeshInstance3D=scene.get_node(key)
		var arrays:=node.mesh.surface_get_arrays(0)
		var uv: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV]
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var lo:=Vector2(INF,INF);var hi:=Vector2(-INF,-INF)
		var errors:=0.0
		for i in vertices.size():
			lo=lo.min(uv[i]);hi=hi.max(uv[i])
			errors=max(errors,(Vector2(vertices[i].x,vertices[i].z)-(uv[i]*32.0-Vector2(16,16))).length())
		observations.geometry[key]={"mesh":node.mesh.resource_path,"mesh_source_sha256":FileAccess.get_sha256(node.mesh.resource_path.split("::")[0]),"transform":var_to_str(node.global_transform),"aabb":var_to_str(node.mesh.get_aabb()),"uv_min":var_to_str(lo),"uv_max":var_to_str(hi),"uv32_minus16_max_error_m":errors,"material":_material(node.material_override)}
	observations.frames=[]
	for index in 121:
		var target:=index*3
		while scene.runtime.current.completed_tick<target:
			var error: StringName=scene.runtime.current.request_tick(1.0/30.0)
			if not error.is_empty():check("tick_admitted",false);await _close();return
			await _wait_tick()
		check("tick_"+str(target),scene.runtime.current.completed_tick==target)
		var label:="frame_%04d"%index
		await _capture(label)
		observations.frames.append({"file":label+".png","tick":target,"time_s":scene.runtime.current.advanced_time_s,"state_seq":scene.runtime.current.completed_state_seq})
	await _close()
