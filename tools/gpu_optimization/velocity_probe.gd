extends "res://tests/integration/async_pipeline_main_probe.gd"

const Protocol=preload("res://scripts/simulation/edit_validation/edit_protocol.gd")
var parent_source:=""
var device: RenderingDevice
var pipelines:=[]
var shaders:=[]
var resources:=[]
var results:={}
var ready_render:=false
var released:=false
var rows:=[]
var timestamp_frames:=[]
var timestamp_seen:=-1
var timestamp_pending:=false
var pair_serial:=0
var active_pair:=0
var timestamp_prefix:="velocity_pair_"

func _observe_gpu() -> void:
	if not timestamp_pending:
		timestamp_pending=true
		RenderingServer.call_on_render_thread(_timestamps_render)

func _timestamps_render() -> void:
	var frame:=device.get_captured_timestamps_frame()
	if frame!=timestamp_seen:
		timestamp_seen=frame
		var starts:={}
		var spans:=[]
		for index in device.get_captured_timestamps_count():
			var label:=device.get_captured_timestamp_name(index)
			if not label.begins_with(timestamp_prefix):continue
			if label.ends_with("_start"):starts[label.trim_suffix("_start")]=device.get_captured_timestamp_gpu_time(index)
			elif label.ends_with("_end"):
				var key:=label.trim_suffix("_end")
				if starts.has(key):spans.append({"label":key,"ns":device.get_captured_timestamp_gpu_time(index)-int(starts[key])})
		if not spans.is_empty():timestamp_frames.append({"frame":frame,"spans":spans})
	call_deferred("_timestamps_collected")

func _timestamps_collected() -> void:
	timestamp_pending=false

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):output=argument.trim_prefix("--output=")
		if argument.begins_with("--parent="):parent_source=argument.trim_prefix("--parent=")
	call_deferred("_run")

func _initialize_render() -> void:
	device=RenderingServer.get_rendering_device()
	for path in [parent_source,"res://shaders/simulation/edit_validation/water_velocity_prefetch.glsl"]:
		var source:=RDShaderSource.new()
		source.source_compute=FileAccess.get_file_as_string(path).trim_prefix("#[compute]")
		var spirv:=device.shader_compile_spirv_from_source(source)
		var error:=spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
		if not error.is_empty():push_error(error);failed=true;break
		var shader:=device.shader_create_from_spirv(spirv)
		shaders.append(shader)
		pipelines.append(device.compute_pipeline_create(shader))
	call_deferred("_initialized")

func _initialized() -> void:
	ready_render=true

func _submit_render(command: PackedByteArray, values: PackedByteArray, scratch: PackedByteArray) -> void:
	for variant in ([0,1] if active_pair%2==0 else [1,0]):
		var receipt:=PackedByteArray()
		receipt.resize(128)
		receipt.encode_u32(0,1)
		var buffers:=[device.storage_buffer_create(command.size(),command),device.storage_buffer_create(values.size(),values),device.storage_buffer_create(scratch.size(),scratch),device.storage_buffer_create(128,receipt)]
		var uniforms: Array[RDUniform]=[]
		for binding in 4:
			var uniform:=RDUniform.new()
			uniform.binding=binding
			uniform.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
			uniform.add_id(buffers[binding])
			uniforms.append(uniform)
		var binding:=device.uniform_set_create(uniforms,shaders[variant],0)
		resources.append_array(buffers)
		resources.append(binding)
		var label:="velocity_pair_%d_%d"%[active_pair,variant]
		device.capture_timestamp(label+"_start")
		var list:=device.compute_list_begin()
		device.compute_list_bind_compute_pipeline(list,pipelines[variant])
		device.compute_list_bind_uniform_set(list,binding,0)
		device.compute_list_dispatch(list,1,1,1)
		device.compute_list_end()
		device.capture_timestamp(label+"_end")
		device.buffer_get_data_async(buffers[3],_arrived.bind(variant))

func _arrived(bytes: PackedByteArray, variant: int) -> void:
	call_deferred("_received",bytes,variant)

func _received(bytes: PackedByteArray, variant: int) -> void:
	results[variant]=bytes

func _clear_render(final: bool=false) -> void:
	for index in range(resources.size()-1,-1,-1):device.free_rid(resources[index])
	resources.clear()
	if final:
		for resource in pipelines+shaders:device.free_rid(resource)
	call_deferred("_cleared")

func _cleared() -> void:
	released=true

func _case(size: int, kind: String) -> void:
	var count:=size*size
	var command:=PackedByteArray()
	command.resize(128)
	command.encode_float(76,0.125)
	command.encode_u32(80,size)
	var values:=PackedFloat32Array()
	values.resize(count*4)
	var scratch:=PackedFloat32Array()
	scratch.resize(count*5)
	var rng:=RandomNumberGenerator.new()
	rng.seed=8107
	for index in count:
		var depth:=float(rng.randf_range(0.002,1.2))
		var before_x:=float(rng.randf_range(-0.3,0.3))*depth
		var before_z:=float(rng.randf_range(-0.3,0.3))*depth
		if kind=="dry":depth=0.0;before_x=0.0;before_z=0.0
		if kind.begins_with("cfl_"):
			depth=0.12
			before_x=(float(kind.trim_prefix("cfl_"))-sqrt(9.81*depth))*depth
			before_z=0.0
		values[index*4]=depth
		values[index*4+1]=0.0
		scratch[index]=before_x
		scratch[count+index]=before_z
		values[index*4+2]=scratch[index]+(0.0001*float(1 if index%2==0 else -1) if kind=="cancellation" else 0.0)
		values[index*4+3]=scratch[count+index]
		scratch[2*count+index]=values[index*4+2]+(0.00002 if kind=="mixed" else 0.0)
		scratch[3*count+index]=values[index*4+3]
	if kind=="nan63":values[63*4]=NAN
	if kind=="inf64":values[64*4+2]=INF
	if kind=="negative_last":values[(count-1)*4]=-1.0
	if kind=="negative_sediment":values[1]=-1.0
	if kind=="invalid_scratch":scratch[2*count]=NAN
	var oracle:=PackedFloat64Array([0,0,0,0,0,0])
	var magnitudes:=PackedFloat64Array([0,0,0,0,0,0])
	var energy_magnitude:=0.0
	for index in count:
		var depth: float=values[index*4]
		var before_x: float=scratch[index]
		var before_z: float=scratch[count+index]
		var raw_x: float=scratch[2*count+index]
		var raw_z: float=scratch[3*count+index]
		var after_x: float=values[index*4+2]
		var after_z: float=values[index*4+3]
		var contributions:=[(after_x-before_x)*0.015625,(after_z-before_z)*0.015625,(raw_x-after_x)*0.015625,(raw_z-after_z)*0.015625,0.0,0.0]
		if depth>0.001:
			contributions[4]=0.5*(raw_x*raw_x+raw_z*raw_z-before_x*before_x-before_z*before_z)/depth*0.015625
			contributions[5]=0.5*(raw_x*raw_x+raw_z*raw_z-after_x*after_x-after_z*after_z)/depth*0.015625
			energy_magnitude+=0.5*(raw_x*raw_x+raw_z*raw_z+before_x*before_x+before_z*before_z+after_x*after_x+after_z*after_z)/depth*0.015625
		for field in 6:
			oracle[field]+=contributions[field]
			magnitudes[field]+=absf(contributions[field])
	results.clear()
	pair_serial+=1
	active_pair=pair_serial
	RenderingServer.call_on_render_thread(_submit_render.bind(command,values.to_byte_array(),scratch.to_byte_array()))
	while results.size()<2:await process_frame
	var parent: PackedByteArray=results[0]
	var candidate: PackedByteArray=results[1]
	var status_equal:=parent.slice(0,8)==candidate.slice(0,8)
	var metadata_equal:=parent.slice(120,128)==candidate.slice(120,128)
	var numeric_ok:=true
	var differences:=[]
	var offsets:=[68,72,76,80,88,92]
	if candidate.decode_u32(0)==1:
		for field in 6:
			var tolerance:=Protocol.reduction_budget(count,magnitudes[field])
			if field>=4:tolerance=maxf(1e-7,32.0*Protocol.UNIT_ROUNDOFF*energy_magnitude+tolerance)
			var value:=candidate.decode_float(offsets[field])
			numeric_ok=numeric_ok and is_finite(value) and absf(value-oracle[field])<=tolerance
			differences.append({"offset":offsets[field],"parent":parent.decode_float(offsets[field]),"candidate":value,"oracle":oracle[field],"tolerance":tolerance})
	else:
		if candidate.decode_u32(4)==4:numeric_ok=parent.slice(8)==candidate.slice(8)
	var passed:=status_equal and metadata_equal and numeric_ok
	rows.append({"pair_serial":active_pair,"size":size,"case":kind,"pass":passed,"status_equal":status_equal,"cfl_equal":metadata_equal,"numeric_ok":numeric_ok,"differences":differences,"parent_hex":parent.hex_encode(),"candidate_hex":candidate.hex_encode()})
	failed=failed or not passed
	print("VELOCITY_OPT ",size," ",kind," ",passed)
	released=false
	RenderingServer.call_on_render_thread(_clear_render)
	while not released:await process_frame

func _run() -> void:
	preview=load(scene_path).instantiate()
	preview.playing=false
	root.add_child(preview)
	var deadline:=Time.get_ticks_msec()+60000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check("main_full_load_ready",preview.ready_for_ticks and preview.async_backend_ready and preview.last_error.is_empty())
	await preview.get_node("Interface/PerformancePanel").stop_sampling()
	hardware={"engine":Engine.get_version_info(),"adapter":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name(),"window":DisplayServer.window_get_size(),"viewport":root.get_visible_rect().size,"vsync":DisplayServer.window_get_vsync_mode(),"profile":preview._runtime_configuration_signature(),"effective_profile":preview._effective_profile_request()}
	RenderingServer.call_on_render_thread(_initialize_render)
	while not ready_render:await process_frame
	process_frame.connect(_observe_gpu)
	if not failed:
		for size in [64,256]:
			for kind in ["dry","mixed","cancellation","nan63","inf64","negative_last","negative_sediment","invalid_scratch","cfl_83.99998","cfl_84.0","cfl_84.00002","cfl_1000.0"]:await _case(size,kind)
		for repeat in 16:await _case(256,"mixed")
	for frame in 6:await process_frame
	process_frame.disconnect(_observe_gpu)
	while timestamp_pending:await process_frame
	released=false
	RenderingServer.call_on_render_thread(_clear_render.bind(true))
	while not released:await process_frame
	await preview.shutdown()
	check("main_released",preview.gpu_release_done)
	preview.queue_free()
	await process_frame
	var file:=FileAccess.open(output,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify({"pass":not failed,"checks":checks,"rows":rows,"runtime":hardware,"timestamp_frames":timestamp_frames,"parent_sha256":FileAccess.get_sha256(parent_source),"candidate_sha256":FileAccess.get_sha256("res://shaders/simulation/edit_validation/water_velocity_prefetch.glsl"),"scope":"direct GPU receipt with existing numeric budgets; paired stage timestamps in the same capture frame under visible paused main full rendering load; alternating order"},"\t"))
	quit(1 if failed else 0)
