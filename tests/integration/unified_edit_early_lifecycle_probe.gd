extends "res://tests/integration/unified_edit_gpu_probe.gd"

var observations: Dictionary={}
var sample_ready:=false

func _run() -> void:
	started=Time.get_ticks_msec();DisplayServer.window_set_size(Vector2i(1280,720));DisplayServer.window_set_title("Unified early lifecycle terminal guards")
	var created: Dictionary=load("res://assets/unified_edit/default_catalog.tres").instantiate_registry();registry=created.registry
	check("registry",created.error.is_empty())
	var simulation:={"enable_erosion":true,"enable_brush_water":true,"unrestricted_sand_tools":true,"enable_structures":false,"local_front_history":false,"rise_front_history":false,"contact_history":false}
	var extra:=PackedStringArray(Pipeline.SOURCE_PATHS+Pipeline.ADAPTER_SOURCES);extra.append(get_script().resource_path)
	var frozen:=Config.freeze(registry,"main_beach",simulation,{"foam_enabled":false,"gravel_enabled":false},{},{"engine":Engine.get_version_info().string,"probe":probe_case},extra)
	check("configuration",frozen.error.is_empty());source_hashes=frozen.value.sources.duplicate(true)
	if probe_case!="early_release_unconfigured":check("configured",pipeline.configure(registry,frozen.value,9007199254740993).is_empty())
	domain=Domain.new(256,0.125);domain.domain_id=&"main_beach";domain.generation=9007199254740993
	if probe_case=="early_cancel":
		check("cancel_before_render_initialize",pipeline.cancel_initialization())
		RenderingServer.call_on_render_thread(pipeline.initialize_render.bind(domain))
		var begin:=Time.get_ticks_msec()
		while not pipeline.initialized and Time.get_ticks_msec()-begin<10000:await process_frame
		check("cancelled_without_gpu_allocation",pipeline.initialized and pipeline.released and pipeline.fault_reason()==&"initialization_cancelled")
	else:
		RenderingServer.call_on_render_thread(pipeline.release_render)
		var begin:=Time.get_ticks_msec()
		while not pipeline.released and Time.get_ticks_msec()-begin<10000:await process_frame
		check("released_before_initialization",pipeline.released and not pipeline.initialized and not pipeline.initialization_started)
	check("released_object_cannot_configure",pipeline.configure(registry,frozen.value,9007199254740993)==&"pipeline_already_configured")
	RenderingServer.call_on_render_thread(pipeline.initialize_render.bind(domain))
	RenderingServer.call_on_render_thread(pipeline.initialize_render.bind(domain))
	RenderingServer.call_on_render_thread(_sample_render)
	var begin:=Time.get_ticks_msec()
	while not sample_ready and Time.get_ticks_msec()-begin<10000:await process_frame
	check("late_initialize_never_reallocates",sample_ready and observations.sample.released and not observations.sample.ready and observations.sample.all_zero and observations.sample.idle_serial==0)
	check("terminal_admission_closed",not pipeline.submit_intent(request(1,&"fill_v1",Vector2.ZERO)).accepted and not pipeline.request_tick(0.001).is_empty())
	check("no_fake_work_or_results",pipeline.completed_state_seq==0 and pipeline.completed_tick==0 and pipeline.completed_revision==0 and pipeline.executor.recorded_commands==0 and pipeline.active_count()==0 and pipeline.pending_count()==0 and pipeline.result_reservations()==0)
	finish()

func _sample_render() -> void:
	var counts:=pipeline.ownership_counts();var all_zero:=true
	for count in counts.values():all_zero=all_zero and count==0
	call_deferred("_sampled",{"owners":counts,"all_zero":all_zero,"released":pipeline.released,"initialized":pipeline.initialized,"initialization_started":pipeline.initialization_started,"ready":pipeline._ready,"fault":String(pipeline.fault_reason()),"idle_serial":pipeline.transport._idle_serial,"idle_receipt_hex":pipeline.transport.idle_receipt.hex_encode()})

func _sampled(record: Dictionary) -> void:observations.sample=record;sample_ready=true

func finish() -> void:
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"case":probe_case,"checks":checks,"observations":observations,"source_hashes":source_hashes,"engine":Engine.get_version_info(),"scope":"Pre-initialization cancellation/release and terminal object reuse guards. No GPU allocations are expected; no formal scene shutdown claim."},"\t"));quit(1 if failed else 0)
