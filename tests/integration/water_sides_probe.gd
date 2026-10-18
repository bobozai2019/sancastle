extends "res://tests/integration/test1_geometry_probe.gd"

var sides: MeshInstance3D
var side_material: ShaderMaterial

func screenshot(name: String) -> void:
	await super.screenshot(name)
	var current_camera := root.get_camera_3d()
	evidence[name + "_camera"] = {"node":str(current_camera.get_path()), "position":current_camera.global_position, "fov":current_camera.fov}

func bindings(label: String) -> void:
	for key in ["rock_state", "sand_state", "water_state", "local_front_state", "async_clock"]:
		check(label + "_shared_" + key, side_material.get_shader_parameter(key) == preview.water_material.get_shader_parameter(key))
	check(label + "_gpu_clock", side_material.get_shader_parameter("use_async_clock") == true)
	check(label + "_published_water", preview.water_texture.texture_rd_rid == preview.solver.published_water)
	check(label + "_published_sand", preview.sand_texture.texture_rd_rid == preview.solver.published_sand)
	check(label + "_generation", sides.bound_generation == preview.generation)

func topology() -> void:
	var water: MeshInstance3D = preview.get_node("GpuWaterSurface")
	var top_arrays := water.mesh.surface_get_arrays(0)
	var side_arrays := sides.mesh.surface_get_arrays(0)
	var top_vertices: PackedVector3Array = top_arrays[Mesh.ARRAY_VERTEX]
	var top_uvs: PackedVector2Array = top_arrays[Mesh.ARRAY_TEX_UV]
	var positions := {}
	for i in top_vertices.size(): positions[top_vertices[i]] = top_uvs[i]
	var vertices: PackedVector3Array = side_arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = side_arrays[Mesh.ARRAY_TEX_UV]
	var colors: PackedColorArray = side_arrays[Mesh.ARRAY_COLOR]
	var matched := true
	for i in vertices.size():
		if colors[i].r == 1.0:
			if not positions.has(vertices[i]) or positions[vertices[i]] != uvs[i]: matched = false
	check("every_side_top_vertex_has_identical_water_position_and_uv", matched)
	var triangles: PackedInt32Array = side_arrays[Mesh.ARRAY_INDEX]
	check("all_four_faces_outward_winding", _outward(vertices, triangles, side_arrays[Mesh.ARRAY_NORMAL]))
	evidence.mesh = {"side_vertices":vertices.size(), "side_triangles":triangles.size()/3, "top_vertices":top_vertices.size(), "min":sides.boundary_min, "max":sides.boundary_max}

func _outward(vertices: PackedVector3Array, indices: PackedInt32Array, normals: PackedVector3Array) -> bool:
	# Bind-pose vertices are degenerate vertically. Expand the upper row first.
	for i in vertices.size(): vertices[i].y = float(i % 2)
	for i in range(0, indices.size(), 3):
		var a := vertices[indices[i]]
		var b := vertices[indices[i+1]]
		var c := vertices[indices[i+2]]
		# Godot front faces have clockwise winding.
		if (b-a).cross(c-a).dot(normals[indices[i]]) >= 0: return false
	return true

func frame_image() -> Image:
	preview.hide_hud = true
	preview.get_node("UIVisibility").visible = false
	preview._update_status()
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func magenta_count(image: Image) -> int:
	var count := 0
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x,y)
			if c.r > 0.5 and c.b > 0.35 and c.g < 0.4: count += 1
	return count

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	root.size = Vector2i(1280,720)
	service = root.get_node("BeachScenes")
	preview = load(scene_path).instantiate()
	preview.playing = false
	root.add_child(preview)
	current_scene = preview
	if not await wait_ready(): await finish(); return
	preview.get_node("Interface").visible = false
	preview.get_node("Interface/PerformancePanel/Margin/Rows/Header/Sampling").button_pressed = false
	for frame in 3: await process_frame
	sides = preview.get_node("WaterSides")
	side_material = sides.material_override
	check("sides_ready_visible", sides.configured and sides.visible)
	bindings("initial")
	topology()
	var geometry: bool = preview.scene_key == "test1_geometry"
	# Both playable layouts map the original ocean to negative world X.
	var ocean_sign := -1.0
	var camera: Camera3D = preview.player_camera
	preview.set_player_camera(true)
	camera.fov = 50.0
	camera.position = Vector3(ocean_sign * 22.0, 5.0, -21.0 if not geometry else -14.0)
	camera.look_at(Vector3(ocean_sign * 7.0, 0.3, 0.0))
	camera.make_current()
	check("side_camera_is_current", root.get_camera_3d() == camera)
	evidence.side_camera = {"position":camera.global_position, "target":Vector3(ocean_sign*7.0,0.3,0.0), "fov":camera.fov}
	await screenshot("01_sides_on")
	var initial := await capture("initial")
	sides.set_process(false)
	sides.visible = false
	await screenshot("02_sides_off")
	sides.visible = true
	sides.set_process(true)
	var unmodified := await capture("visual_toggle")
	for key in initial.native.fields:
		check("visibility_preserves_" + key, initial.native.fields[key] == unmodified.native.fields[key])
	side_material.set_shader_parameter("side_debug", 1)
	var mask := await frame_image()
	mask.save_png(output.get_base_dir().path_join("03_side_mask.png"))
	check("actual_side_pixels_visible", magenta_count(mask) > 100)
	var edge_x: int = clampi(floori((sides.boundary_min.x + 16.0) / 0.125), 0, 255)
	var cell := 128 * 256 + edge_x
	var bed_y: float = initial.native.fields.rock.decode_float(cell*4) + initial.native.fields.sand.decode_float(cell*4)
	var water_h: float = initial.native.fields.water.decode_float(cell*4)
	var near_point := Vector3(sides.boundary_min.x, bed_y + water_h*0.5, 0.0)
	var pixel := Vector2i(camera.unproject_position(near_point))
	var near_color := mask.get_pixelv(pixel)
	check("near_water_boundary_is_closed", water_h > 0.02 and near_color.r > 0.5 and near_color.b > 0.35 and near_color.g < 0.4)
	evidence.near_side = {"world":near_point, "pixel":pixel, "color":near_color, "water_depth":water_h}
	var dry_image := Image.create(256,256,false,Image.FORMAT_RF)
	dry_image.fill(Color(0,0,0,1))
	var dry := ImageTexture.create_from_image(dry_image)
	sides.set_process(false)
	side_material.set_shader_parameter("water_state", dry)
	var dry_mask := await frame_image()
	dry_mask.save_png(output.get_base_dir().path_join("04_dry_negative.png"))
	check("dry_side_discards_pixels", magenta_count(dry_mask) == 0)
	side_material.set_shader_parameter("water_state", preview.water_texture)
	side_material.set_shader_parameter("side_debug", 0)
	sides.set_process(true)
	var edge := Vector3(ocean_sign * (14.85 if geometry else 15.8), 0, -3)
	var dig := command(0, edge, false)
	dig.radius_m = 0.7
	dig.amount_m3 = 0.08
	check("edge_dig_submitted", preview.input_scheduler.submit(dig).is_empty())
	check("edge_dig_drained", await idle())
	check("edge_dig_changed_bed", initial.native.fields.sand != await read("sand"))
	var fill := command(1, edge, true)
	fill.radius_m = 0.7
	fill.amount_m3 = 0.12
	check("edge_fill_submitted", preview.input_scheduler.submit(fill).is_empty())
	check("edge_fill_drained", await idle())
	preview._on_trigger_wave_pressed()
	preview.playing = true
	var deadline := Time.get_ticks_msec() + 60000
	while preview.completed_ticks < 80 and preview.last_error.is_empty() and Time.get_ticks_msec() < deadline: await process_frame
	preview.playing = false
	check("wave_and_simulation_advanced", preview.completed_ticks >= 80 and preview.last_error.is_empty())
	check("wave_drained", await idle())
	bindings("after_wave")
	await screenshot("05_after_wave_and_edge_edits")
	if geometry and "--cycle" in OS.get_cmdline_user_args():
		var samples := []
		var period: float = preview.GeometryLayout.water_cycle().period_s
		for seconds in [period * 0.22, period * 0.35, period * 0.55, period * 0.8]:
			preview.playing = true
			deadline = Time.get_ticks_msec() + 90000
			while preview.async_controller.actual_time < seconds and preview.last_error.is_empty() and Time.get_ticks_msec() < deadline: await process_frame
			preview.playing = false
			check("cycle_time_" + str(seconds), preview.async_controller.actual_time >= seconds and await idle())
			var h: PackedFloat32Array = (await read("water")).to_float32_array()
			var edge_water := 0.0
			for z in range(68,188): edge_water += h[z*256+8]
			samples.append({"time":preview.async_controller.actual_time, "offshore_depth_sum":edge_water})
			await screenshot("cycle_%02d" % int(seconds))
		evidence.cycle = samples
		check("boundary_recedes_after_high_water", samples[3].offshore_depth_sum < samples[0].offshore_depth_sum)
	var clock_before := await read("clock")
	for frame in 10: await process_frame
	check("paused_clock_frozen", clock_before == await read("clock"))
	var save_path := output.get_base_dir().path_join("water_sides.sandcp")
	check("save_with_sidewalls", (await preview.save_gpu_checkpoint(save_path)).is_empty())
	var old_generation: int = preview.generation
	check("restore_with_sidewalls", (await preview.restore_gpu_checkpoint(save_path)).is_empty())
	for frame in 3: await process_frame
	check("restore_new_generation", preview.generation > old_generation)
	bindings("restored")
	await screenshot("06_restored")
	check("no_runtime_failure", preview.last_error.is_empty())
	await finish()
