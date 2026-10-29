extends SceneTree

# Real GPU regression for submit-ahead and confirmed owner-thread slot reuse.
const Pipeline=preload("res://scripts/simulation/unified_edit/pipeline.gd")
const Config=preload("res://scripts/simulation/unified_edit/configuration.gd")
const Domain=preload("res://scripts/simulation/sand_water_domain.gd")
const Diagnostics=preload("res://scripts/simulation/unified_edit/diagnostics.gd")

class InboxPipeline extends Pipeline:
	var inbox: Array[Dictionary]=[]
	func _receive(bytes: PackedByteArray, id: Dictionary) -> void:
		# Keep detached data; defer the normal validation/settlement until frame start.
		inbox.append({"bytes":bytes.duplicate(),"id":id.duplicate(true),"at_us":Time.get_ticks_usec()})
	func drain_inbox() -> void:
		var ready:=inbox;inbox=[]
		for row in ready:super._receive(row.bytes,row.id)

var pipeline:=InboxPipeline.new()
var trace:=Diagnostics.new()
var output:=""
var checks: Array=[]
var observations: Dictionary={}
var configuration: Dictionary={}
var frame_heads: Array=[]
var consume_enabled:=false
var first_drain:=true
var failed:=false
var gpu_control:=PackedByteArray()
var registry

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	process_frame.connect(_frame_start)
	call_deferred("_run")

func check(name: String, ok: bool) -> void:
	checks.append({"name":name,"pass":ok});failed=failed or not ok
	print("SUBMIT_AHEAD ",name," ",ok)

func _frame_start() -> void:
	frame_heads.append({"at_us":Time.get_ticks_usec(),"frame":Engine.get_process_frames(),"inbox":pipeline.inbox.size(),"consume_enabled":consume_enabled})
	if not consume_enabled:return
	pipeline.drain_inbox()
	pipeline.pump()
	if first_drain:
		first_drain=false
		observations.first_frame_head={"completed":pipeline.completed_state_seq,"pending":pipeline.pending_count(),"active":pipeline.active_count(),"states":pipeline.slots._slots.map(func(row):return row.state)}

func _control(id: int) -> Dictionary:
	return {"domain_id":"main_beach","generation":1,"command_id":id,"sim_tick":0,"stroke_id":1,"baseline_token":1}

func _sample(id: int, index: int) -> Dictionary:
	var profile: Dictionary=registry.profile(&"shovel_v1")
	return {"domain_id":"main_beach","generation":1,"command_id":id,"sim_tick":0,"stroke_id":1,"baseline_token":1,"sample_index":index,"profile_id":"shovel_v1","profile_version":profile.version,"profile_hash":profile.profile_hash,"start_xz_m":Vector2(0,index),"end_xz_m":Vector2(0,index+1),"parameters":{"depth_m":0.15,"trench_width_m":0.5,"shoulder_width_m":0.5,"speed_m_s":0.25},"features":{"water_policy":3},"seed":101}

func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1280,720));DisplayServer.window_set_title("Submit-ahead and confirmed slot reuse")
	var created: Dictionary=load("res://assets/unified_edit/default_catalog.tres").instantiate_registry();registry=created.registry
	check("registry",created.error.is_empty())
	var simulation:={"enable_erosion":false,"enable_brush_water":true,"unrestricted_sand_tools":true,"enable_structures":false,"local_front_history":false,"rise_front_history":false,"contact_history":false}
	var frozen:=Config.freeze(registry,"main_beach",simulation,{"foam_enabled":false,"gravel_enabled":false},{},{"engine":Engine.get_version_info().string,"test":"submit_ahead_feasibility"},PackedStringArray(Pipeline.SOURCE_PATHS+Pipeline.ADAPTER_SOURCES))
	check("configuration",frozen.error.is_empty());configuration=frozen.value
	check("configure",pipeline.configure(registry,configuration,1).is_empty())
	var domain:=Domain.new(256,0.125);domain.domain_id=&"main_beach";domain.generation=1;domain.sand.fill(0.4);domain.water.fill(0.15)
	pipeline.diagnostics=trace
	RenderingServer.call_on_render_thread(pipeline.initialize_render.bind(domain))
	var deadline:=Time.get_ticks_msec()+30000
	while not pipeline.initialized and Time.get_ticks_msec()<deadline:await process_frame
	check("initialized",pipeline.initialized and pipeline.fault_reason().is_empty())
	if failed:_finish();return
	check("begin_admitted",pipeline.submit_control("begin",_control(1)).accepted)
	check("sample_a_admitted",pipeline.submit_intent(_sample(2,0)).accepted)
	check("water_a_admitted",pipeline.request_tick(0.001).is_empty())
	check("sample_b_admitted",pipeline.submit_intent(_sample(3,1)).accepted)
	check("end_admitted",pipeline.submit_control("end",_control(4)).accepted)
	check("water_b_admitted",pipeline.request_tick(0.001).is_empty())
	observations.submitted_at_us=Time.get_ticks_usec()
	pipeline.pump() # Exactly one pump, while CPU receipt validation/consumption is withheld.
	check("three_recorded_fourth_pending",pipeline.active_count()==3 and pipeline.pending_count()==1)
	deadline=Time.get_ticks_msec()+30000
	while pipeline.inbox.size()<3 and Time.get_ticks_msec()<deadline:await process_frame
	check("three_callbacks_without_cpu_consumption",pipeline.inbox.size()==3 and pipeline.completed_state_seq==0 and pipeline._results.is_empty())
	if failed:_finish();return
	RenderingServer.call_on_render_thread(_read_control)
	while gpu_control.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check("gpu_completed_edit_tick_edit",gpu_control.size()==128 and gpu_control.decode_s64(16)==3 and gpu_control.decode_s64(24)==1)
	observations.gpu_before_cpu={"state_seq":gpu_control.decode_s64(16),"tick":gpu_control.decode_s64(24),"cpu_state_seq":pipeline.completed_state_seq,"inbox_count":pipeline.inbox.size(),"pending":pipeline.pending_count()}
	for i in 2:await process_frame
	check("fourth_still_blocked_by_owned_slots",pipeline.pending_count()==1 and pipeline.completed_state_seq==0)
	consume_enabled=true
	deadline=Time.get_ticks_msec()+30000
	while (pipeline.active_count()!=0 or pipeline.pending_count()!=0) and Time.get_ticks_msec()<deadline:await process_frame
	check("frame_start_consumption_finishes_all",pipeline.active_count()==0 and pipeline.pending_count()==0 and pipeline.completed_state_seq==4 and pipeline.completed_tick==2 and pipeline.fault_reason().is_empty())
	check("frame_start_reuses_confirmed_owner_thread_slots",observations.first_frame_head.completed==3 and observations.first_frame_head.pending==0 and observations.first_frame_head.active==1)
	var results: Array=[]
	for id in range(1,5):results.append(pipeline.take_result(id))
	check("real_shovel_results",results[1].get("outcome")==1 and results[2].get("outcome")==1)
	observations.results=results
	pipeline.close_admission();RenderingServer.call_on_render_thread(pipeline.release_render)
	while not pipeline.released and Time.get_ticks_msec()<deadline:await process_frame
	check("released",pipeline.released)
	var unchanged:=true
	for path in configuration.sources:unchanged=unchanged and FileAccess.get_sha256(path)==configuration.sources[path]
	check("source_identity_unchanged",unchanged)
	_finish()

func _read_control() -> void:
	var error: Error=pipeline.transport.rd.buffer_get_data_async(pipeline.transport.control,_control_arrived,0,128)
	if error!=OK:call_deferred("check","control_read_submitted",false)

func _control_arrived(bytes: PackedByteArray) -> void:call_deferred("_control_stored",bytes)
func _control_stored(bytes: PackedByteArray) -> void:gpu_control=bytes

func _finish() -> void:
	process_frame.disconnect(_frame_start)
	if not output.is_empty():
		FileAccess.open(output.get_basename()+".control.bin",FileAccess.WRITE).store_buffer(gpu_control)
		FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"checks":checks,"configuration":configuration,"probe_sha256":FileAccess.get_sha256("res://tools/unified_edit_pipeline/check_submit_ahead.gd"),"observations":observations,"frame_heads":frame_heads,"timeline":trace.snapshot(),"scope":"Isolated real main RenderingDevice using current product Pipeline, three slots and shaders. Receive decorator queues detached receipts until process_frame. Proves bounded GPU progress without CPU consumption and same-pump reuse after confirmed owner-thread retirement; not full-scene performance or more-than-three-slot capacity."},"\t"))
	quit(1 if failed else 0)
