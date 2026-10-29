extends "res://tests/integration/water_sides_probe.gd"

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	root.size = Vector2i(1280,720)
	service = root.get_node("BeachScenes")
	preview = load("res://scenes/main.tscn").instantiate()
	preview.playing = false
	root.add_child(preview)
	current_scene = preview
	if not await wait_ready(): await finish(); return
	for key in ["test1_capture", "test1_backwash", "test1_geometry", "main"]:
		if not await switch_to(key): break
		preview.playing = false
		check(key + "_drained", await idle())
		for frame in 3: await process_frame
		sides = preview.get_node("WaterSides")
		side_material = sides.material_override
		check(key + "_visible_configured", sides.visible and sides.configured)
		bindings(key)
		topology()
		var camera: Camera3D = preview.player_camera
		camera.fov = 50.0
		camera.position = Vector3(-22,5,-14 if key == "test1_geometry" else -21)
		camera.look_at(Vector3(-7,0.3,0))
		camera.make_current()
		await screenshot(key + "_sides")
		# Probe a visible near-face point, not just arbitrary pixels on a far wall.
		var state := await capture(key)
		var x := clampi(floori((sides.boundary_min.x + 16.0)/0.125),0,255)
		var cell := 128*256+x
		var bed: float = state.native.fields.rock.decode_float(cell*4)+state.native.fields.sand.decode_float(cell*4)
		var h: float = state.native.fields.water.decode_float(cell*4)
		var position := Vector3(sides.boundary_min.x,bed+h*0.5,0)
		side_material.set_shader_parameter("side_debug",1)
		var mask := await frame_image()
		var pixel := Vector2i(camera.unproject_position(position))
		var c := mask.get_pixelv(pixel)
		check(key+"_near_boundary_pixel", h>0.02 and c.r>0.5 and c.b>0.35 and c.g<0.4)
		side_material.set_shader_parameter("side_debug",0)
	check("no_runtime_failure",preview.last_error.is_empty())
	await finish()
