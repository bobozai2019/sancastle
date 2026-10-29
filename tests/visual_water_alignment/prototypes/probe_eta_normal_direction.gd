extends SceneTree

const WATER_SHADER := preload("res://tests/visual_water_alignment/prototypes/reference_water_local_front.gdshader")
const GRID := 64
const STATE_GRID := 256
const DOMAIN_M := 32.0

var output_dir := ""
var run_id := ""
var shore_mode := false
var field_dir := ""
var grid_size := GRID


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			output_dir = arg.trim_prefix("--output=")
		elif arg.begins_with("--run-id="):
			run_id = arg.trim_prefix("--run-id=")
		elif arg == "--shore":
			shore_mode = true
			grid_size = STATE_GRID
		elif arg.begins_with("--field-dir="):
			field_dir = arg.trim_prefix("--field-dir=")
			grid_size = STATE_GRID
	call_deferred("_run")


func _run() -> void:
	if output_dir.is_empty() or run_id.is_empty() or \
			not DirAccess.dir_exists_absolute(output_dir):
		_fail("output/run-id invalid")
		return
	root.size = Vector2i(512, 512)
	var host := Node3D.new()
	root.add_child(host)
	var mesh := MeshInstance3D.new()
	mesh.mesh = _make_grid()
	host.add_child(mesh)
	var zero := _make_water_texture(0.0, 0.0, 0.0)
	var material := ShaderMaterial.new()
	material.shader = WATER_SHADER
	material.set_shader_parameter("rock_state", zero)
	material.set_shader_parameter("sand_state", zero)
	material.set_shader_parameter("display_reconstruction", true)
	material.set_shader_parameter("prototype_eta_normals", true)
	material.set_shader_parameter("prototype_eta_normal_debug", true)
	mesh.material_override = material
	var camera := Camera3D.new()
	camera.current = true
	camera.fov = 50.0
	host.add_child(camera)
	if not field_dir.is_empty():
		await _run_real_fields(material, camera)
		return
	var results := {}
	var cases := [
		{"name": "flat", "sx": 0.0, "sz": 0.0, "oblique": false},
		{"name": "x_up", "sx": 0.02, "sz": 0.0, "oblique": false},
		{"name": "x_down", "sx": -0.02, "sz": 0.0, "oblique": false},
		{"name": "z_up", "sx": 0.0, "sz": 0.02, "oblique": false},
		{"name": "z_down", "sx": 0.0, "sz": -0.02, "oblique": false},
		{"name": "x_up_oblique", "sx": 0.02, "sz": 0.0, "oblique": true},
		{"name": "x_up_space_top", "sx": 0.02, "sz": 0.0,
			"oblique": false, "space": true},
		{"name": "x_up_space_oblique", "sx": 0.02, "sz": 0.0,
			"oblique": true, "space": true},
		{"name": "x_up_light_top", "sx": 0.02, "sz": 0.0,
			"oblique": false, "light_space": true},
		{"name": "x_up_light_oblique", "sx": 0.02, "sz": 0.0,
			"oblique": true, "light_space": true},
		{"name": "x_up_light_rotated", "sx": 0.02, "sz": 0.0,
			"oblique": true, "light_space": true,
			"light": Vector3(0.30, 0.90, -0.20)},
	]
	if shore_mode:
		cases = [
			{"name": "shore_flat", "sx": 0.0, "sz": 0.0, "oblique": false},
			{"name": "shore_up", "sx": 0.02, "sz": 0.0, "oblique": false},
			{"name": "shore_down", "sx": -0.02, "sz": 0.0, "oblique": false},
		]
	for item in cases:
		material.set_shader_parameter("water_state", _make_water_texture(
			0.5, item.sx, item.sz))
		material.set_shader_parameter("prototype_eta_normal_space_debug",
			item.get("space", false))
		material.set_shader_parameter("prototype_eta_light_space_debug",
			item.get("light_space", false))
		material.set_shader_parameter("prototype_light_direction_world",
			item.get("light", Vector3(-0.10, 0.10, 0.99)))
		if item.oblique:
			camera.position = Vector3(8.0, 22.0, 5.0)
		else:
			camera.position = Vector3(0.0, 25.0, 0.0)
		camera.look_at(Vector3(0.0, 0.5, 0.0), Vector3(0.0, 0.0, -1.0))
		for frame in 20:
			await RenderingServer.frame_post_draw
		var image: Image = root.get_texture().get_image()
		var path := output_dir.path_join("%s_%s.png" % [run_id, item.name])
		if image.save_png(path) != OK:
			_fail("image save " + item.name)
			return
		results[item.name] = {
			"rgb_center": _mean_center(image),
			"image": path, "slope_x": item.sx, "slope_z": item.sz,
			"camera": "oblique" if item.oblique else "top",
		}
		if shore_mode:
			results[item.name]["rgb_background"] = _mean_patch(image, 100, 100, 2)
			results[item.name]["rgb_dry"] = _mean_patch(image, 230, 256, 2)
			results[item.name]["rgb_edge"] = _mean_patch(image, 260, 256, 1)
			results[item.name]["rgb_interior"] = _mean_patch(image, 300, 256, 2)
	if shore_mode:
		var dry: Array = results.shore_flat.rgb_dry
		var background: Array = results.shore_flat.rgb_background
		var edge: Array = results.shore_flat.rgb_edge
		var interior: Array = results.shore_flat.rgb_interior
		if not (absf(dry[0] - background[0]) < 0.01 and \
				absf(dry[1] - background[1]) < 0.01 and \
				absf(dry[2] - background[2]) < 0.01 and \
				absf(edge[0] - interior[0]) < 0.05 and \
				results.shore_up.rgb_edge[0] < edge[0] and \
				results.shore_down.rgb_edge[0] > edge[0]):
			_fail("shore wet/dry normal or mask incorrect: " + str(results))
			return
		_write_manifest(results)
		return
	var flat: Array = results.flat.rgb_center
	if not (results.x_up.rgb_center[0] < flat[0] - 0.02 and \
			results.x_down.rgb_center[0] > flat[0] + 0.02 and \
			results.z_up.rgb_center[2] < flat[2] - 0.02 and \
			results.z_down.rgb_center[2] > flat[2] + 0.02 and \
			absf(results.x_up_oblique.rgb_center[0] - results.x_up.rgb_center[0]) < 0.04 and \
			maxf(results.x_up_space_top.rgb_center[0],
				results.x_up_space_top.rgb_center[2]) < 0.04 and \
			maxf(results.x_up_space_oblique.rgb_center[0],
				results.x_up_space_oblique.rgb_center[2]) < 0.04 and \
			maxf(results.x_up_light_top.rgb_center[0],
				results.x_up_light_top.rgb_center[2]) < 0.04 and \
			maxf(results.x_up_light_oblique.rgb_center[0],
				results.x_up_light_oblique.rgb_center[2]) < 0.04 and \
			maxf(results.x_up_light_rotated.rgb_center[0],
				results.x_up_light_rotated.rgb_center[2]) < 0.04):
		_fail("GPU normal directions or camera invariance incorrect: " + str(results))
		return
	_write_manifest(results)


func _run_real_fields(material: ShaderMaterial, camera: Camera3D) -> void:
	var results := {}
	var source_fields := {}
	for tick in [180, 240, 300]:
		var prefix := field_dir.path_join("shore%d_coupled_" % tick)
		source_fields[str(tick)] = {
			"rock": FileAccess.get_sha256(prefix + "rock_f32.bin"),
			"sand": FileAccess.get_sha256(prefix + "sand_f32.bin"),
			"water": FileAccess.get_sha256(prefix + "water_f32.bin"),
		}
		var rock := _load_rf(prefix + "rock_f32.bin")
		var sand := _load_rf(prefix + "sand_f32.bin")
		var water := _load_rf(prefix + "water_f32.bin")
		if rock == null or sand == null or water == null:
			_fail("real field load tick " + str(tick))
			return
		material.set_shader_parameter("rock_state", rock)
		material.set_shader_parameter("sand_state", sand)
		material.set_shader_parameter("water_state", water)
		for item in [
			{"name": "normal_top", "mode": "normal", "oblique": false},
			{"name": "normal_oblique", "mode": "normal", "oblique": true},
			{"name": "space_top", "mode": "space", "oblique": false},
			{"name": "space_oblique", "mode": "space", "oblique": true},
			{"name": "light_top", "mode": "light", "oblique": false},
			{"name": "light_oblique", "mode": "light", "oblique": true},
			{"name": "light_rotated", "mode": "light", "oblique": true,
				"light": Vector3(0.30, 0.90, -0.20)},
		]:
			material.set_shader_parameter("prototype_eta_normal_debug",
				item.mode == "normal")
			material.set_shader_parameter("prototype_eta_normal_space_debug",
				item.mode == "space")
			material.set_shader_parameter("prototype_eta_light_space_debug",
				item.mode == "light")
			material.set_shader_parameter("prototype_light_direction_world",
				item.get("light", Vector3(-0.10, 0.10, 0.99)))
			camera.position = Vector3(8.0, 22.0, 5.0) if item.oblique else \
				Vector3(0.0, 25.0, 0.0)
			camera.look_at(Vector3(0.0, 0.5, 0.0), Vector3(0.0, 0.0, -1.0))
			for frame in 8:
				await RenderingServer.frame_post_draw
			var image: Image = root.get_texture().get_image()
			var name := "tick%d_%s" % [tick, item.name]
			var path := output_dir.path_join("%s_%s.png" % [run_id, name])
			if image.save_png(path) != OK:
				_fail("real field image save " + name)
				return
			results[name] = {"image": path, "rgb_center": _mean_center(image),
				"camera": "oblique" if item.oblique else "top",
				"mode": item.mode,
				"light": str(item.get("light", Vector3(-0.10, 0.10, 0.99)))}
	_write_manifest(results, source_fields)


func _load_rf(path: String) -> ImageTexture:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() != STATE_GRID * STATE_GRID * 4:
		return null
	return ImageTexture.create_from_image(Image.create_from_data(
		STATE_GRID, STATE_GRID, false, Image.FORMAT_RF, bytes))


func _write_manifest(results: Dictionary, source_fields: Dictionary = {}) -> void:
	var path := output_dir.path_join(run_id + "_manifest.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("manifest open")
		return
	file.store_string(JSON.stringify({"run_id": run_id,
		"shader_sha256": FileAccess.get_sha256(WATER_SHADER.resource_path),
		"grid": grid_size, "state_grid": STATE_GRID, "domain_m": DOMAIN_M,
		"shore_mode": shore_mode,
		"field_dir": field_dir,
		"source_fields_sha256": source_fields,
		"viewport_px": [root.size.x, root.size.y],
		"rendering_driver": RenderingServer.get_current_rendering_driver_name(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"cases": results}, "\t"))
	file.close()
	print("PASS: W09 eta normal real fields captured" if not field_dir.is_empty() else \
		("PASS: W09 eta normal shore" if shore_mode else \
		"PASS: W09 eta normal flat/positive/negative slopes and camera"))
	quit(0)


func _make_grid() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for z in grid_size:
		for x in grid_size:
			var u := (float(x) + 0.5) / float(grid_size)
			var v := (float(z) + 0.5) / float(grid_size)
			vertices.append(Vector3((u - 0.5) * DOMAIN_M, 0.0,
				(v - 0.5) * DOMAIN_M))
			uvs.append(Vector2(u, v))
	for z in grid_size - 1:
		for x in grid_size - 1:
			var i := z * grid_size + x
			indices.append_array(PackedInt32Array([i, i + grid_size + 1, i + 1,
				i, i + grid_size, i + grid_size + 1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result


func _make_water_texture(base_depth: float, slope_x: float,
		slope_z: float) -> ImageTexture:
	var image := Image.create(STATE_GRID, STATE_GRID, false, Image.FORMAT_RF)
	for z in STATE_GRID:
		for x in STATE_GRID:
			var wx := (float(x) + 0.5) * DOMAIN_M / float(STATE_GRID) - DOMAIN_M * 0.5
			var wz := (float(z) + 0.5) * DOMAIN_M / float(STATE_GRID) - DOMAIN_M * 0.5
			var depth := base_depth + slope_x * wx + slope_z * wz
			if shore_mode and x < STATE_GRID / 2:
				depth = 0.0
			image.set_pixel(x, z, Color(depth,
				0.0, 0.0))
	return ImageTexture.create_from_image(image)


func _mean_center(image: Image) -> Array:
	return _mean_patch(image, 256, 256, 5)


func _mean_patch(image: Image, center_x: int, center_y: int,
		radius: int) -> Array:
	var sum := Vector3.ZERO
	var count := float((radius * 2 + 1) * (radius * 2 + 1))
	for y in range(center_y - radius, center_y + radius + 1):
		for x in range(center_x - radius, center_x + radius + 1):
			var pixel: Color = image.get_pixel(x, y)
			sum += Vector3(pixel.r, pixel.g, pixel.b)
	return [sum.x / count, sum.y / count, sum.z / count]


func _fail(message: String) -> void:
	push_error("FAIL: W09 eta normal " + message)
	quit(1)
