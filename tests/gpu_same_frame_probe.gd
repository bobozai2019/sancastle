extends SceneTree

const Effect = preload("res://tests/same_frame_effect.gd")

var effect: CompositorEffect
var camera: Camera3D
var plane: MeshInstance3D
var texture: Texture2DRD
var finished := false


func _init() -> void:
	call_deferred("_begin")


func _begin() -> void:
	texture = Texture2DRD.new()
	effect = Effect.new()
	effect.target_texture = texture
	RenderingServer.call_on_render_thread(_prepare_effect)


func _prepare_effect() -> void:
	effect._setup()
	if not effect.set_rid.is_valid():
		call_deferred("_fail", "pre-opaque RD resources unavailable")
		return
	call_deferred("_attach_scene")


func _attach_scene() -> void:
	var compositor := Compositor.new()
	compositor.compositor_effects = [effect]
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/benchmarks/checker_display.gdshader")
	material.set_shader_parameter("state_texture", texture)
	plane = MeshInstance3D.new()
	plane.mesh = PlaneMesh.new()
	plane.scale = Vector3(4, 1, 4)
	plane.material_override = material
	root.add_child(plane)
	camera = Camera3D.new()
	camera.position = Vector3(0, 5, 0)
	camera.compositor = compositor
	root.add_child(camera)
	camera.look_at(Vector3.ZERO, Vector3(0, 0, -1))
	camera.current = true
	for _warmup in 8:
		await RenderingServer.frame_post_draw
	var matched := 0
	for sample in 12:
		var requested := 0.05 if sample % 2 == 0 else 1.0
		effect.request_value(requested)
		await RenderingServer.frame_post_draw
		var dispatch: Dictionary = effect.last_dispatch()
		var image := root.get_texture().get_image()
		if image == null or image.is_empty():
			_fail("viewport image unavailable")
			return
		var red: float = image.get_pixel(image.get_width() / 2, image.get_height() / 2).r
		var expected_high: bool = requested > 0.5
		var actual_high: bool = red > 0.60
		print("SAME_FRAME sample=%d request=%.2f dispatch=%.2f red=%.3f count=%d match=%s" % [
			sample, requested, dispatch.value, red, dispatch.count, expected_high == actual_high])
		if is_equal_approx(dispatch.value, requested) and expected_high == actual_high:
			matched += 1
		if sample == 11:
			var path := "res://test_output/sandcastle_water_sand_coupling/验收/T00_same_frame_20260928.png"
			image.save_png(path)
	if matched < 10:
		_fail("only %d/12 alternating frames matched their pre-opaque compute value" % matched)
		return
	finished = true
	print("PASS: pre-opaque main-RD compute value reached opaque material in %d/12 same frames" % matched)
	_cleanup_and_quit(0)


func _cleanup_and_quit(exit_code: int) -> void:
	if plane != null:
		plane.queue_free()
	if camera != null:
		camera.compositor = null
	for _frame in 6:
		await RenderingServer.frame_post_draw
	RenderingServer.call_on_render_thread(effect.release)
	for _frame in 3:
		await RenderingServer.frame_post_draw
	quit(exit_code)


func _fail(message: String) -> void:
	if finished:
		return
	finished = true
	printerr("FAIL: same-frame probe: " + message)
	_cleanup_and_quit(1)
