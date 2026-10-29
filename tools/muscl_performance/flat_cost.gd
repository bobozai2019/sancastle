extends "res://tools/wave_propagation/gpu_probe.gd"

const Cost=preload("res://tools/muscl_performance/cost_scene.gd")
var timeline
var phase:=""
var rows: Array=[]
var gpu_rows: Array=[]
var previous_us:=0
var collecting:=false
var seen_gpu:=-1
var recording:=false
var installed:=false
var install_error:=""
var original_tail: Callable
var total_buffer:=RID()
var counter_pipeline:=RID()
var counter_binding:=RID()
var totals:=PackedByteArray()

func _process(delta: float) -> bool:
	super._process(delta)
	if owner==null or not owner.initialized:return false
	if recording and owner.pending_count()+owner.active_count()<2:check("tick_admitted",owner.request_tick(1.0/30.0).is_empty())
	if not phase.is_empty():
		var now:=Time.get_ticks_usec()
		rows.append({"phase":phase,"frame_ms":(now-previous_us)/1000.0,"us":now,"focused":root.has_focus(),"sim_s":owner.advanced_time_s,"tick":owner.completed_tick,"pending":owner.pending_count(),"active":owner.active_count()})
		previous_us=now
		if not collecting:collecting=true;RenderingServer.call_on_render_thread(collect_gpu)
	return false

func collect_gpu() -> void:
	var rd: RenderingDevice=owner.state.rd
	var frame:=rd.get_captured_timestamps_frame()
	var marks: Array=[]
	if frame!=seen_gpu:
		seen_gpu=frame
		for i in rd.get_captured_timestamps_count():marks.append({"name":rd.get_captured_timestamp_name(i),"gpu_ns":rd.get_captured_timestamp_gpu_time(i),"cpu_us":rd.get_captured_timestamp_cpu_time(i)})
	gpu_received.call_deferred(frame,marks)

func gpu_received(frame: int, marks: Array) -> void:
	collecting=false
	if not marks.is_empty():gpu_rows.append({"frame":frame,"marks":marks})

func install_render() -> void:
	var water=owner.water
	var rd: RenderingDevice=owner.state.rd
	var source:=RDShaderSource.new()
	source.source_compute="#version 450\nlayout(local_size_x=1)in;layout(set=0,binding=0,std430)readonly buffer Decision{uint d[];};layout(set=0,binding=1,std430)readonly buffer Cache{uint cached[];};layout(set=0,binding=2,std430)buffer Totals{uint total[];};void main(){total[0]++;total[1]+=d[1];total[2]+=d[10];total[3]+=cached[2];}"
	var spirv:=rd.shader_compile_spirv_from_source(source)
	install_error=spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
	if install_error.is_empty():
		var shader: RID=water._own(rd.shader_create_from_spirv(spirv));counter_pipeline=water._own(rd.compute_pipeline_create(shader))
		var zero:=PackedByteArray();zero.resize(16)
		total_buffer=water._own(rd.storage_buffer_create(16,zero))
		var cache: RID=water.muscl.buffers.retry_cache if water.muscl.buffers.has("retry_cache") else water._own(rd.storage_buffer_create(16,zero))
		counter_binding=water._make_binding(shader,0,[],[water.decision,cache,total_buffer])
		original_tail=water.tail_recorder;water.tail_recorder=count_tail
		owner.state.profile_passes=true
	installed=true

func count_tail(decision: RID) -> void:
	if original_tail.is_valid():original_tail.call(decision)
	var rd: RenderingDevice=owner.state.rd
	var list:=rd.compute_list_begin();rd.compute_list_bind_compute_pipeline(list,counter_pipeline);rd.compute_list_bind_uniform_set(list,counter_binding,0);rd.compute_list_dispatch(list,1,1,1);rd.compute_list_end()

func read_totals() -> void:
	totals_received.call_deferred(owner.state.rd.buffer_get_data(total_buffer))

func totals_received(bytes: PackedByteArray) -> void:totals=bytes

func run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	DisplayServer.window_set_title("MUSCL flat no-retry cost (synthetic)")
	var catalog: Dictionary=load("res://assets/unified_edit/default_catalog.tres").instantiate_registry()
	var simulation:={"enable_erosion":false,"enable_brush_water":true,"unrestricted_sand_tools":true,"enable_structures":false,"local_front_history":false,"rise_front_history":false,"contact_history":false}
	var frozen:=Config.freeze(catalog.registry,"main_beach",simulation,{"foam_enabled":false,"gravel_enabled":false},{},{"engine":Engine.get_version_info().string,"water_numerics":{"schema":1,"solver_id":Config.Numerics.MUSCL}},PackedStringArray(Pipeline.SOURCE_PATHS+Pipeline.ADAPTER_SOURCES))
	check("configuration",frozen.error.is_empty());configuration=frozen.value
	owner=Pipeline.new();check("configure",owner.configure(catalog.registry,configuration,1).is_empty())
	var domain:=Domain.new(256,0.125);domain.domain_id=&"main_beach";domain.generation=1;domain.water.fill(0.1);domain.sand.fill(0.4)
	RenderingServer.call_on_render_thread(owner.initialize_render.bind(domain))
	while not owner.initialized and owner.initialization_error.is_empty():await process_frame
	check("initialized",owner.initialized and owner.fault_reason().is_empty())
	if failed:quit(1);return
	timeline=Cost.CostTimeline.new();timeline.pipeline_ref=weakref(owner);timeline.generation=1;owner.diagnostics=timeline
	RenderingServer.call_on_render_thread(install_render)
	while not installed:await process_frame
	if not install_error.is_empty():push_error(install_error);quit(1);return
	root.grab_focus();recording=true
	await create_timer(3.0).timeout
	phase="live";previous_us=Time.get_ticks_usec()
	var interval:={"phase":"live","start_us":previous_us,"start_tick":owner.completed_tick,"start_sim_s":owner.advanced_time_s}
	await create_timer(6.0).timeout
	interval.merge({"end_us":Time.get_ticks_usec(),"end_tick":owner.completed_tick,"end_sim_s":owner.advanced_time_s})
	recording=false;phase="drain"
	await idle();await create_timer(0.5).timeout
	RenderingServer.call_on_render_thread(read_totals)
	while totals.is_empty():await process_frame
	phase=""
	while collecting:await process_frame
	check("all_ticks_no_rejection",totals.size()==16 and totals.decode_u32(0)>0 and totals.decode_u32(8)==0)
	check("no_retry_cache_hits",totals.decode_u32(12)==0)
	var drift: Array=[]
	for path in configuration.sources:
		if FileAccess.get_sha256(path)!=configuration.sources[path]:drift.append(path)
	var metadata:={"engine":Engine.get_version_info(),"adapter":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name(),"window":DisplayServer.window_get_size(),"vsync":DisplayServer.window_get_vsync_mode(),"camera":null,"configuration":configuration,"intervals":[interval],"last_error":String(owner.fault_reason()),"source_drift":drift,"note":"Synthetic uniform wet domain, no coupling/consumers; no-retry overhead only, not game FPS. Same one-pass GPU diagnostic total counter in both variants included in tick interval."}
	FileAccess.open(output.path_join("capture.json"),FileAccess.WRITE).store_string(JSON.stringify({"metadata":metadata,"frames":rows,"gpu":gpu_rows,"timeline":timeline.snapshot(),"checks":checks,"flat_totals":{"ticks":totals.decode_u32(0),"accepted":totals.decode_u32(4),"rejected":totals.decode_u32(8),"cache_hits":totals.decode_u32(12)}},"",true,true))
	owner.close_admission();RenderingServer.call_on_render_thread(owner.release_render)
	while not owner.released:await process_frame
	original_tail=Callable()
	quit(1 if failed or not drift.is_empty() else 0)
