extends "res://tools/gpu_optimization/velocity_probe.gd"
var repeat_case:="lower_all"

func _initialize() -> void:
	super._initialize()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--repeat-case="):repeat_case=argument.trim_prefix("--repeat-case=")

func _initialize_render() -> void:
	device=RenderingServer.get_rendering_device()
	timestamp_prefix="displacement_pair_"
	var paths:=[parent_source+"packed.glsl.source",parent_source+"displace.glsl.source","res://shaders/simulation/edit_validation/water_packed_cached.glsl","res://shaders/simulation/edit_validation/water_displace_compensated.glsl"]
	paths.append_array(paths.slice(2,4))
	for index in paths.size():
		var source:=RDShaderSource.new()
		source.source_compute=FileAccess.get_file_as_string(paths[index]).trim_prefix("#[compute]")
		if index==4:source.source_compute=source.source_compute.replace("if(has_demand==0u) { if(lane==0u) receipt[0]=1u;return; }","if(has_demand==0u) { if(lane==0u) { receipt[0]=1u;receipt[28]=1u; }return; }")
		if index==5:source.source_compute=source.source_compute.replace("if(!has_demand) { receipt[0]=1u;receipt[2]=components;return; }","if(!has_demand) { receipt[0]=1u;receipt[2]=components;receipt[28]=2u;return; }")
		var spirv:=device.shader_compile_spirv_from_source(source)
		var error:=spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
		if not error.is_empty():push_error(error);failed=true;break
		var shader:=device.shader_create_from_spirv(spirv)
		shaders.append(shader)
		pipelines.append(device.compute_pipeline_create(shader))
	call_deferred("_initialized")

func _submit_render(push: PackedByteArray, input: PackedByteArray, scratch: PackedByteArray) -> void:
	for variant in ([0,1,2] if active_pair%2==0 else [1,0,2]):
		var buffers:=[device.storage_buffer_create(input.size(),input),device.storage_buffer_create(input.size()/2),device.storage_buffer_create(scratch.size(),scratch),device.storage_buffer_create(128)]
		resources.append_array(buffers)
		var label:="displacement_pair_%d_%d"%[active_pair,variant]
		var bindings:=[]
		for phase in 2:
			var uniforms: Array[RDUniform]=[]
			for binding in 4:
				var uniform:=RDUniform.new()
				uniform.binding=binding
				uniform.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
				uniform.add_id(buffers[binding])
				uniforms.append(uniform)
			var shader_index: int=variant*2+phase
			var binding:=device.uniform_set_create(uniforms,shaders[shader_index],0)
			resources.append(binding)
			bindings.append(binding)
		device.capture_timestamp(label+"_start")
		for phase in 2:
			var shader_index: int=variant*2+phase
			var list:=device.compute_list_begin()
			device.compute_list_bind_compute_pipeline(list,pipelines[shader_index])
			device.compute_list_bind_uniform_set(list,bindings[phase],0)
			device.compute_list_set_push_constant(list,push,16)
			device.compute_list_dispatch(list,1,1,1)
			device.compute_list_end()
		device.capture_timestamp(label+"_end")
		device.buffer_get_data_async(buffers[3],_arrived.bind(variant))
		device.buffer_get_data_async(buffers[1],_arrived.bind(variant+3))

func _case(size: int, kind: String) -> void:
	var count:=size*size
	var input:=PackedFloat32Array()
	input.resize(count*8)
	var scratch:=PackedFloat32Array()
	scratch.resize(count*5)
	var push:=PackedByteArray()
	push.resize(16)
	push.encode_u32(0,size)
	push.encode_float(4,0.125)
	push.encode_u32(8,1 if kind=="loss_inject_mixed" else 0)
	push.encode_u32(12,2)
	for index in count:
		var column:=index%size
		var row:=index/size
		var depth:=0.1
		var old_bed:=0.5
		var new_bed:=0.49
		var obstacle:=0.0
		if kind=="lower_local" and column<size/2:new_bed=old_bed;depth=0.0
		if kind in ["mixed","loss_inject_mixed","surface_ties","overflow_surface"]:new_bed=0.53 if column==size/2 else 0.49
		if kind=="surface_ties" and index%2==0:old_bed=0.25;new_bed=0.28 if column==size/2 else 0.24;depth=0.35
		if kind=="capacity_short":new_bed=0.7
		if kind=="disconnected" and column==size/2:obstacle=1.0
		if kind=="thin_link" and column==size/2 and row!=size/2:obstacle=1.0
		if kind=="complex_runs" and (column+row)%2==0:obstacle=1.0
		if kind=="dry_raise":depth=0.0;new_bed=0.55
		if kind=="shallow_raise":depth=0.0005;new_bed=0.55
		if kind=="obstacle_raise":
			obstacle=1.0 if column<size/2 else 0.0
			new_bed=0.55 if obstacle>0.0 else 0.49
		for component in 8:input[index*8+component]=[old_bed,new_bed,depth,0.002,0.02,-0.01,obstacle,0.0][component]
	if kind=="invalid_input":input[63*8+2]=NAN
	if kind=="negative_sediment":input[64*8+3]=-0.1
	if kind=="overflow_surface":input[0]=3e38;input[1]=3.1e38;input[2]=3e38
	results.clear()
	pair_serial+=1
	active_pair=pair_serial
	RenderingServer.call_on_render_thread(_submit_render.bind(push,input.to_byte_array(),scratch.to_byte_array()))
	while results.size()<6:await process_frame
	var parent: PackedByteArray=results[0]
	var candidate: PackedByteArray=results[1]
	var trace: PackedByteArray=results[2].duplicate()
	var hit:=trace.decode_u32(112)
	trace.encode_u32(112,0)
	var expected_hit:=kind not in ["mixed","loss_inject_mixed","capacity_short","invalid_input","negative_sediment","surface_ties","overflow_surface"]
	var passed: bool=parent==candidate and parent==trace and results[3]==results[4] and results[3]==results[5] and (hit>0)==expected_hit
	failed=failed or not passed
	rows.append({"pair_serial":active_pair,"size":size,"case":kind,"pass":passed,"receipt_equal":parent==candidate,"output_equal":results[3]==results[4],"trace_equivalent":parent==trace and results[3]==results[5],"private_trace_hit":hit,"expected_hit":expected_hit,"input_sha256":digest(input.to_byte_array()),"parent_receipt_hex":parent.hex_encode(),"candidate_receipt_hex":candidate.hex_encode(),"parent_output_sha256":digest(results[3]),"candidate_output_sha256":digest(results[4])})
	print("DISPLACEMENT_OPT ",size," ",kind," ",passed," hit=",hit)
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
			for kind in ["lower_all","lower_local","mixed","capacity_short","disconnected","thin_link","complex_runs","dry_raise","shallow_raise","obstacle_raise","invalid_input","negative_sediment","loss_inject_mixed","surface_ties","overflow_surface"]:await _case(size,kind)
		for repeat in 8:await _case(256,repeat_case)
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
	var identities:={}
	for path in [parent_source+"packed.glsl.source",parent_source+"displace.glsl.source","res://shaders/simulation/edit_validation/water_packed_cached.glsl","res://shaders/simulation/edit_validation/water_displace_compensated.glsl"]:identities[path]=FileAccess.get_sha256(path)
	var file:=FileAccess.open(output,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify({"pass":not failed,"checks":checks,"rows":rows,"runtime":hardware,"source_sha256":identities,"timestamp_frames":timestamp_frames,"scope":"private raw displacement buffers; same-frame production parent/candidate timings; third diagnostic variant only writes private reserved receipt word28, checked after masking that one word"},"\t"))
	quit(1 if failed else 0)
