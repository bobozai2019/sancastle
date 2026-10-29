extends SceneTree

const PingPong = preload("res://scripts/simulation/gpu_scalar_pingpong.gd")
const SIZE := 256
const STEPS := 30

var state: SandcastleGpuScalarPingPong
var spirv: RDShaderSPIRV
var finished := false
var frames_waited := 0


func _init() -> void:
	call_deferred("_begin")


func _begin() -> void:
	var shader_file: RDShaderFile = load("res://shaders/simulation/scalar_pingpong.glsl")
	if shader_file == null:
		_fail("scalar ping-pong shader missing")
		return
	spirv = shader_file.get_spirv()
	if spirv == null:
		_fail("scalar ping-pong SPIR-V missing")
		return
	RenderingServer.call_on_render_thread(_render_probe)
	call_deferred("_watchdog")


func _render_probe() -> void:
	var rd := RenderingServer.get_rendering_device()
	state = PingPong.new()
	if not state.initialize(rd, spirv, SIZE, 0.25):
		call_deferred("_fail", "256-square main-RD state initialization failed")
		return
	for step in STEPS:
		if not state.dispatch_step():
			call_deferred("_fail", "ping-pong dispatch failed at step %d" % step)
			return
	if state.current_index != STEPS % 2:
		call_deferred("_fail", "ping-pong index mismatch")
		return
	var error := state.request_current_data(_on_data)
	if error != OK:
		call_deferred("_fail", "async readback request failed: %d" % error)


func _on_data(data: PackedByteArray) -> void:
	call_deferred("_verify", data)


func _verify(data: PackedByteArray) -> void:
	if finished:
		return
	if data.size() != SIZE * SIZE * 4:
		_fail("wrong readback byte count %d" % data.size())
		return
	var values := data.to_float32_array()
	var minimum := INF
	var maximum := -INF
	for value in values:
		minimum = minf(minimum, value)
		maximum = maxf(maximum, value)
	if absf(minimum - 0.28) > 0.00002 or absf(maximum - 0.28) > 0.00002:
		_fail("30-step scalar result mismatch min=%f max=%f" % [minimum, maximum])
		return
	print("PASS: 256-square main-RD R32F ping-pong, 30 dispatches, async readback min=%.6f max=%.6f" % [minimum, maximum])
	finished = true
	RenderingServer.call_on_render_thread(_release)


func _release() -> void:
	if state != null:
		state.release()
	call_deferred("_finish")


func _finish() -> void:
	quit(0)


func _watchdog() -> void:
	if finished:
		return
	frames_waited += 1
	if frames_waited > 300:
		_fail("ping-pong callback timed out")
		return
	await process_frame
	call_deferred("_watchdog")


func _fail(message: String) -> void:
	if finished:
		return
	finished = true
	printerr("FAIL: " + message)
	RenderingServer.call_on_render_thread(_release_failure)


func _release_failure() -> void:
	if state != null:
		state.release()
	call_deferred("_finish_failure")


func _finish_failure() -> void:
	quit(1)
