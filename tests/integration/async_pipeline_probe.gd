extends SceneTree

const Wire = preload("res://scripts/simulation/edit_validation/frame_pipeline/async_protocol.gd")
const Slots = preload("res://scripts/simulation/edit_validation/frame_pipeline/async_slots.gd")
const Transport = preload("res://scripts/simulation/edit_validation/frame_pipeline/async_transport.gd")
var pool := Slots.new(0x10000000d)
var transport := Transport.new()
var checks := []
var failed := false
var output := ""
var phase := ""
var callbacks := []
var init_done := false
var init_ok := false
var released := false
var release_blocked := false
var work_shader := RID()
var work_pipeline := RID()
var work_sets: Array[RID] = []
var expected_sum := 0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
		if arg.begins_with("--case="): phase = arg.trim_prefix("--case=")
	call_deferred("_run")

func check(label: String, value: bool) -> void:
	checks.append({"name":label,"pass":value})
	failed = failed or not value
	print("ASYNC_GPU ",label," ",value)

func _initialize_render() -> void:
	init_ok = transport.initialize(RenderingServer.get_rendering_device(), pool.generation)
	if init_ok:
		# Start near uint32 carry to prove GPU uint64 state_seq encoding.
		transport.rd.buffer_update(transport.control,16,8,PackedInt32Array([-2,0]).to_byte_array())
		var source := RDShaderSource.new()
		source.source_compute = FileAccess.get_file_as_string("res://tests/integration/async_pipeline_transport_probe.glsl").trim_prefix("#[compute]")
		var spirv := transport.rd.shader_compile_spirv_from_source(source)
		init_ok = spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE).is_empty()
		if init_ok:
			work_shader = transport.rd.shader_create_from_spirv(spirv)
			work_pipeline = transport.rd.compute_pipeline_create(work_shader)
			for slot in transport.resources:
				var uniforms: Array[RDUniform] = []
				for pair in [[0,slot.input],[1,transport.control]]:
					var uniform := RDUniform.new()
					uniform.binding = pair[0]
					uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
					uniform.add_id(pair[1])
					uniforms.append(uniform)
				work_sets.append(transport.rd.uniform_set_create(uniforms,work_shader,0))
	call_deferred("_initialized")

func _initialized() -> void:
	init_done = true

func _record(input: RID, _control: RID, _count: int) -> void:
	var index := -1
	for slot in transport.resources:
		index += 1
		if slot.input == input: break
	var list := transport.rd.compute_list_begin()
	transport.rd.compute_list_bind_compute_pipeline(list,work_pipeline)
	transport.rd.compute_list_bind_uniform_set(list,work_sets[index],0)
	transport.rd.compute_list_dispatch(list,1,1,1)
	transport.rd.compute_list_end()

func _submit_render(id: Dictionary, commands: PackedByteArray) -> void:
	var error: String = transport.submit(id,commands,_record,_arrived)
	if not error.is_empty(): call_deferred("_submit_error", error)

func _submit_error(error: String) -> void:
	check("submit_error_"+error,false)

func _arrived(bytes: PackedByteArray, id: Dictionary) -> void:
	call_deferred("_receive",bytes,id)

func _receive(bytes: PackedByteArray, id: Dictionary) -> void:
	check("gpu_completion_%d" % id.batch_seq,pool.completed(bytes,id).is_empty())
	callbacks.append({"bytes":bytes,"identity":id})

func _retire_render(id: Dictionary) -> void:
	if not transport.retire(id): call_deferred("_submit_error","retire")

func submit() -> Dictionary:
	var acquired: Dictionary = pool.acquire()
	if not acquired.error.is_empty(): return acquired
	var id: Dictionary = acquired.identity
	var commands := PackedByteArray()
	commands.resize(2 * Wire.COMMAND_BYTES)
	commands.encode_u32(0, 100 + id.batch_seq)
	commands.encode_u32(Wire.COMMAND_BYTES, 200 + id.batch_seq)
	expected_sum += 300 + 2 * id.batch_seq
	check("queue_%d" % id.batch_seq,pool.submitted(id))
	RenderingServer.call_on_render_thread(_submit_render.bind(id,commands))
	return id

func consume_all() -> void:
	for row in callbacks:
		var id: Dictionary = row.identity
		var result: Dictionary = pool.consume(id)
		check("cpu_consume_%d" % id.batch_seq,result.error.is_empty() and result.error_flags == 0)
		check("gpu_sequence_%d" % id.batch_seq,result.state_seq == 0xfffffffe + id.batch_seq)
		var expected: int = 300 * id.batch_seq + id.batch_seq * (id.batch_seq + 1)
		check("immutable_upload_and_shared_order_%d" % id.batch_seq,result.revision == expected)
		RenderingServer.call_on_render_thread(_retire_render.bind(id))
	callbacks.clear()

func _release_attempt_render() -> void:
	release_blocked = not transport.release()

func _release_render() -> void:
	for rid in work_sets + [work_pipeline,work_shader]:
		if rid.is_valid(): transport.rd.free_rid(rid)
	work_sets.clear()
	released = transport.release()

func _run() -> void:
	if phase not in ["", "resources"]:
		check("unsupported_case_"+phase,false)
		quit(1)
		return
	check("visible_device",DisplayServer.get_name() != "headless" and RenderingServer.get_rendering_device() != null)
	RenderingServer.call_on_render_thread(_initialize_render)
	var deadline := Time.get_ticks_msec()+30000
	while not init_done and Time.get_ticks_msec()<deadline: await process_frame
	check("initialized",init_done and init_ok)
	if init_ok:
		for index in 3: submit()
		check("three_submitted_before_cpu_consume",pool.active_count()==3 and pool.events.filter(func(e):return e.event=="cpu_consume").is_empty())
		check("full_backpressure",submit().get("error", "") == "no_slot")
		RenderingServer.call_on_render_thread(_release_attempt_render)
		while callbacks.size()<3 and not failed and Time.get_ticks_msec()<deadline: await process_frame
		check("all_gpu_finished",callbacks.size()==3)
		check("gpu_complete_still_backpressures",pool.acquire().error=="no_slot")
		check("release_blocked_while_leased",release_blocked)
		consume_all()
		submit()
		while callbacks.is_empty() and not failed and Time.get_ticks_msec()<deadline: await process_frame
		check("reused_slot_completed",callbacks.size()==1)
		consume_all()
		pool.stop_admission()
		check("cpu_pool_drained",pool.can_release())
		RenderingServer.call_on_render_thread(_release_render)
		while not released and Time.get_ticks_msec()<deadline: await process_frame
		check("all_resources_released",released and transport.rd==null)
	var info := {"pass":not failed,"scope":"P01 transport only; no sand edit or simulation claim","checks":checks,"events":pool.events,
		"engine":Engine.get_version_info(),"adapter":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name(),"window":DisplayServer.window_get_size()}
	if not output.is_empty():
		var file := FileAccess.open(output,FileAccess.WRITE)
		if file != null: file.store_string(JSON.stringify(info,"\t"))
	quit(1 if failed else 0)
