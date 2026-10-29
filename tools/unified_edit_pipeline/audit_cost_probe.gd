extends "res://tests/integration/async_pipeline_main_probe.gd"

# Paired stage-only replay. The visible paused main scene supplies rendering
# load; both auditors consume the same immutable, previously verified buffers.
# No authority writer, transaction, or runtime fallback is exercised here.
const GPU=preload("res://scripts/simulation/unified_edit/gpu.gd")
const Response=preload("res://scripts/simulation/unified_edit/water_response.gd")
const L=preload("res://scripts/simulation/unified_edit/layout.gd")
var fixture_paths:=PackedStringArray()
var device: RenderingDevice
var helper:=GPU.new()
var response:=Response.new()
var buffers: Dictionary={}
var old_set: RID
var ready_render:=false
var pending:=false
var completed:=false
var timestamp_seen:=-1
var timestamp_frames:=[]
var record_times:=[]
var current_serial:=0
var rows:=[]
var fixture_hashes: Dictionary={}
var verification: Dictionary={}

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		if arg.begins_with("--fixture="):fixture_paths.append(arg.trim_prefix("--fixture="))
	call_deferred("_run")

func _observe() -> void:
	if not pending:
		pending=true
		RenderingServer.call_on_render_thread(_timestamps_render)

func _timestamps_render() -> void:
	var frame:=device.get_captured_timestamps_frame()
	if frame!=timestamp_seen:
		timestamp_seen=frame
		var starts:={};var spans:=[]
		for index in device.get_captured_timestamps_count():
			var label:=device.get_captured_timestamp_name(index)
			if not label.begins_with("audit_cost_"):continue
			if label.ends_with("_start"):starts[label.trim_suffix("_start")]=device.get_captured_timestamp_gpu_time(index)
			elif label.ends_with("_end"):
				var key:=label.trim_suffix("_end")
				if starts.has(key):spans.append({"label":key,"gpu_ns":device.get_captured_timestamp_gpu_time(index)-int(starts[key])})
		if not spans.is_empty():timestamp_frames.append({"frame":frame,"spans":spans})
	call_deferred("_observed")

func _observed() -> void:pending=false

func _texture(format: int) -> RID:
	var spec:=RDTextureFormat.new();spec.width=256;spec.height=256;spec.format=format
	spec.usage_bits=RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
	return helper.own(device.texture_create(spec,RDTextureView.new()))

func _initialize_render() -> void:
	device=RenderingServer.get_rendering_device();helper.rd=device
	for pair in [["command",512],["cells",65536*64],["summary",L.SUMMARY_BUFFER_BYTES],["decision",128],["control",128],["old_receipt",256]]:
		var zero:=PackedByteArray();zero.resize(pair[1]);buffers[pair[0]]=helper.own(device.storage_buffer_create(pair[1],zero))
	var scalar:=_texture(RenderingDevice.DATA_FORMAT_R32_SFLOAT)
	var obstacle:=_texture(RenderingDevice.DATA_FORMAT_R8_UNORM)
	var state:={"rd":device,"textures":{"rock":scalar,"sand":[scalar],"water":[scalar,scalar],"sediment":[scalar,scalar],"momentum_x":[scalar,scalar],"momentum_z":[scalar,scalar],"obstacle":obstacle}}
	var ok:=response.initialize({"rd":device,"state":state,"transport":{"control":buffers.control},"buffers":buffers})
	ok=ok and helper.compile("old","res://shaders/simulation/brushes/water_merge.glsl")
	if ok:old_set=helper.binding("old",{0:buffers.old_receipt,1:response.buffers.receipt,2:response.buffers.input,3:response.buffers.candidate,4:buffers.cells})
	call_deferred("_initialized",ok)

func _initialized(ok: bool) -> void:
	check("auditors_initialized",ok);ready_render=true

func _load_render(case: Dictionary) -> void:
	var wire: Dictionary=case.wire
	var command:=PackedByteArray();command.resize(512)
	for key in L.COMMAND_U32:command.encode_u32(L.COMMAND_U32[key],int(wire.get(key,0)))
	for key in L.COMMAND_F32:command.encode_float(L.COMMAND_F32[key],float(wire.get(key,0)))
	device.buffer_update(buffers.command,0,512,command)
	for key in ["cells","summary","decision"]:
		var data:=FileAccess.get_file_as_bytes(case.after[key].path)
		device.buffer_update(buffers[key],0,data.size(),data)
	for key in ["input","candidate","receipt"]:
		var data:=FileAccess.get_file_as_bytes(case.after["water_"+key].path)
		device.buffer_update(response.buffers[key],0,data.size(),data)
	var receipt:=PackedByteArray();receipt.resize(256);receipt.encode_u32(12,1);receipt.encode_u32(56,1)
	device.buffer_update(buffers.old_receipt,0,256,receipt)
	call_deferred("_submitted")

func _submitted() -> void:completed=true

func _pair_render(serial: int, policy: int) -> void:
	for variant in ([0,1] if serial%2==0 else [1,0]):
		var label:="audit_cost_%d_%d"%[serial,variant]
		device.capture_timestamp(label+"_start")
		var start:=Time.get_ticks_usec()
		if variant==0:
			helper.dispatch("old",old_set,Vector3i.ONE,PackedInt32Array([256,0,0,policy,0,0,0,0]).to_byte_array())
		else:
			response.dispatch("response",response.sets.response,Vector3i(256,1,1),PackedInt32Array([2,0,0,0]).to_byte_array())
			response.dispatch("response",response.sets.response,Vector3i.ONE,PackedInt32Array([3,0,0,0]).to_byte_array())
		record_times.append({"serial":serial,"variant":variant,"cpu_record_us":Time.get_ticks_usec()-start})
		device.capture_timestamp(label+"_end")
	call_deferred("_submitted")

func _verify_render() -> void:
	device.buffer_get_data_async(buffers.old_receipt,_verified.bind("old"))
	device.buffer_get_data_async(buffers.decision,_verified.bind("new"))

func _verified(bytes: PackedByteArray, key: String) -> void:call_deferred("_store",key,bytes)
func _store(key: String, bytes: PackedByteArray) -> void:verification[key]=bytes

func _release_render() -> void:
	# This set borrows response buffers. Destroy the cross-owner reference
	# before releasing those buffers, which would invalidate it implicitly.
	helper.owned.erase(old_set);device.free_rid(old_set)
	response.release();helper.release();call_deferred("_submitted")

func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1280,720))
	preview=load(scene_path).instantiate();preview.playing=false;root.add_child(preview)
	var deadline:=Time.get_ticks_msec()+60000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check("visible_main_ready",preview.ready_for_ticks and preview.async_backend_ready and preview.last_error.is_empty())
	await preview.get_node("Interface/PerformancePanel").stop_sampling()
	hardware={"engine":Engine.get_version_info(),"adapter":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name(),"window":DisplayServer.window_get_size(),"viewport":root.get_visible_rect().size,"vsync":DisplayServer.window_get_vsync_mode(),"profile":preview._runtime_configuration_signature(),"effective_profile":preview._effective_profile_request(),"main_sources":loaded_code()}
	RenderingServer.call_on_render_thread(_initialize_render)
	while not ready_render:await process_frame
	process_frame.connect(_observe)
	if not failed:
		for path in fixture_paths:
			var evidence: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
			fixture_hashes[path]=FileAccess.get_sha256(path)
			var case: Dictionary={}
			for candidate in evidence.cases:
				if candidate.label=="response":case=candidate;break
			check("fixture_valid_"+evidence.case,evidence.pass and not case.is_empty() and case.result.outcome==1)
			if case.is_empty():continue
			var identities:={}
			for key in ["cells","summary","decision","water_input","water_candidate","water_receipt"]:
				identities[key]=case.after[key]
				check("fixture_digest_"+evidence.case+"_"+key,FileAccess.get_sha256(case.after[key].path)==case.after[key].sha256)
			completed=false;RenderingServer.call_on_render_thread(_load_render.bind(case))
			while not completed:await process_frame
			var first:=current_serial+1
			for repeat in 28:
				current_serial+=1
				completed=false;RenderingServer.call_on_render_thread(_pair_render.bind(current_serial,int(case.wire.water_policy)))
				while not completed:await process_frame
				# Permit timestamp delivery; no per-stage readback or CPU authorization.
				await process_frame
			verification.clear();RenderingServer.call_on_render_thread(_verify_render)
			while verification.size()<2:await process_frame
			var old: PackedByteArray=verification.old;var next: PackedByteArray=verification.new
			check("paired_acceptance_"+evidence.case,old.decode_u32(12)==1 and old.decode_u32(80)==0 and next.decode_u32(32)==0)
			var row:={"case":evidence.case,"first_serial":first,"last_serial":current_serial,"warmup_pairs":4,"sample_pairs":24,"fixtures":identities,"old_receipt_hex":old.hex_encode(),"new_decision_hex":next.hex_encode(),"original_result":case.result}
			rows.append(row)
	for frame in 8:await process_frame
	process_frame.disconnect(_observe)
	while pending:await process_frame
	completed=false;RenderingServer.call_on_render_thread(_release_render)
	while not completed:await process_frame
	await preview.shutdown();check("main_released",preview.gpu_release_done)
	preview.queue_free();await process_frame
	var sources:={}
	for path in [get_script().resource_path,"res://scripts/simulation/unified_edit/gpu.gd","res://scripts/simulation/unified_edit/layout.gd","res://scripts/simulation/unified_edit/water_response.gd","res://scripts/simulation/unified_edit/water_response.glsl","res://shaders/simulation/brushes/water_merge.glsl"]:sources[path]=FileAccess.get_sha256(path)
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"checks":checks,"runtime":hardware,"rows":rows,"timestamp_frames":timestamp_frames,"record_times":record_times,"sources":sources,"fixture_hashes":fixture_hashes,"scope":"Stage-only immutable replay on main RenderingDevice under visible paused main rendering load. 4 warmup+24 alternating pairs per fixture. Stock single-thread water_merge versus unmodified common mode2/3 including union metadata. No per-stage readback or RD sync in measured spans. Neither auditor writes authority; this is not end-to-end FPS or final T08 cost."},"\t"))
	quit(1 if failed else 0)
