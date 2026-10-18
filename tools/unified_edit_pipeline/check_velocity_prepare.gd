extends "res://tools/unified_edit_pipeline/check_packed_parallel.gd"

# Compare only velocity-only initialization against the untouched serial kernel.
# The inherited harness compares all candidate/receipt bytes and repeatability.
func run() -> void:
	pins[get_script().resource_path]=FileAccess.get_sha256(get_script().resource_path)
	await super.run()

func setup_render() -> void:
	old.rd=RenderingServer.get_rendering_device();candidate.rd=old.rd
	for pair in [["input",65536*32],["candidate",65536*16],["scratch",65536*20],["receipt",128],["velocity_checks",256*8],["decision",128],["control",128]]:
		var data:=PackedByteArray();data.resize(pair[1])
		candidate.buffers[pair[0]]=candidate.own(candidate.rd.storage_buffer_create(data.size(),data))
		if pair[0] in ["input","candidate","scratch","receipt"]:old_buffers[pair[0]]=old.own(old.rd.storage_buffer_create(data.size(),data))
	var ok: bool=candidate.compile("velocity_prepare",Response.SOURCES[7]) and old.compile("displace",Response.SOURCES[2])
	if ok:ok=candidate._initialize_velocity_prepare_phases()
	if ok:
		candidate.sets.velocity_prepare=candidate.binding("velocity_prepare",{0:candidate.buffers.input,1:candidate.buffers.candidate,2:candidate.buffers.scratch,3:candidate.buffers.receipt,4:candidate.buffers.velocity_checks,5:candidate.buffers.decision,6:candidate.buffers.control})
		old_sets.displace=old.binding("displace",{0:old_buffers.input,1:old_buffers.candidate,2:old_buffers.scratch,3:old_buffers.receipt})
	call_deferred("setup_done",ok,old.last_error+candidate.last_error)

func setup_done(ok: bool, error: String) -> void:
	check("compile_and_initialize",ok)
	if not error.is_empty():print(error)
	if ok:
		for guard in ["decision","control"]:
			results.clear();RenderingServer.call_on_render_thread(guard_render.bind(guard))
			var deadline:=Time.get_ticks_msec()+30000
			while results.size()<4 and Time.get_ticks_msec()<deadline:await process_frame
			check(guard+"_guard_readbacks",results.size()==4)
			for key in results:
				var expected:=PackedByteArray();expected.resize(results[key].size());expected.fill(90)
				check(guard+"_guard_preserves_"+key,results[key]==expected)
	ready=true

func guard_render(guard: String) -> void:
	var blocked:=PackedByteArray();blocked.resize(128);blocked.encode_u32(32 if guard=="decision" else 4,1)
	candidate.rd.buffer_update(candidate.buffers[guard],0,blocked.size(),blocked)
	for pair in [["candidate",65536*16],["receipt",128],["scratch",65536*20],["velocity_checks",256*8]]:
		var sentinel:=PackedByteArray();sentinel.resize(pair[1]);sentinel.fill(90)
		candidate.rd.buffer_update(candidate.buffers[pair[0]],0,sentinel.size(),sentinel)
	candidate._velocity_only()
	for key in ["candidate","receipt","scratch","velocity_checks"]:
		var error: int=candidate.rd.buffer_get_data_async(candidate.buffers[key],receive_render.bind(key))
		if error!=OK:call_deferred("read_error",error)
	blocked.fill(0);candidate.rd.buffer_update(candidate.buffers[guard],0,blocked.size(),blocked)

func record_render(bytes: PackedByteArray, repeat_only: bool) -> void:
	var push:=PackedFloat32Array([0,0.125,0,0]).to_byte_array();push.encode_u32(0,256);push.encode_u32(12,1)
	candidate.rd.buffer_update(candidate.buffers.input,0,bytes.size(),bytes)
	if not repeat_only:
		old.rd.buffer_update(old_buffers.input,0,bytes.size(),bytes)
		old.dispatch("displace",old_sets.displace,Vector3i.ONE,push)
	candidate._velocity_only()
	for key in ["candidate","receipt"]:
		if not repeat_only:
			var error: int=old.rd.buffer_get_data_async(old_buffers[key],receive_render.bind("old_"+key))
			if error!=OK:call_deferred("read_error",error)
		var error: int=candidate.rd.buffer_get_data_async(candidate.buffers[key],receive_render.bind(("repeat_" if repeat_only else "new_")+key))
		if error!=OK:call_deferred("read_error",error)
