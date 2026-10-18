extends "res://tests/integration/unified_edit_gpu_probe.gd"

const FailedViews=preload("res://tests/integration/unified_edit_failed_views.gd")
var observations: Dictionary={}
var observed: Dictionary={}

func _run() -> void:
	started=Time.get_ticks_msec()
	DisplayServer.window_set_size(Vector2i(1280,720));DisplayServer.window_set_title("Unified initialization failure lifecycle")
	var created: Dictionary=load("res://assets/unified_edit/default_catalog.tres").instantiate_registry()
	check("registry",created.error.is_empty());registry=created.registry
	var simulation:={"enable_erosion":true,"enable_brush_water":true,"unrestricted_sand_tools":true,"enable_structures":false,"local_front_history":false,"rise_front_history":false,"contact_history":false}
	var extras:=PackedStringArray(Pipeline.SOURCE_PATHS+Pipeline.ADAPTER_SOURCES)
	extras.append(get_script().resource_path);extras.append("res://tests/integration/unified_edit_failed_views.gd")
	var config:=Config.freeze(registry,"main_beach",simulation,{"foam_enabled":false,"gravel_enabled":false},{},{"engine":Engine.get_version_info().string,"probe":probe_case},extras)
	check("configuration",config.error.is_empty())
	if not config.error.is_empty():finish();return
	source_hashes=config.value.sources.duplicate(true)
	check("configure",pipeline.configure(registry,config.value,9007199254740993).is_empty())
	domain=Domain.new(256,0.125);domain.domain_id=&"main_beach";domain.generation=9007199254740993
	domain.sand.fill(0.25);domain.water.fill(0.1)
	var expected_error:=""
	if probe_case=="init_bad_field":domain.wetness.resize(1);expected_error="state/initial_field_size"
	elif probe_case=="init_bad_domain":domain.generation+=1;expected_error="initial_domain_mismatch"
	elif probe_case=="init_null_domain":domain=null;expected_error="initial_domain_mismatch"
	elif probe_case=="init_compile":pipeline.views=FailedViews.new();expected_error="views/query:"
	else:
		var stage:=probe_case.trim_prefix("init_")
		if stage=="unknown":stage="views";pipeline.transport.inject_idle_fence_unavailable=true
		pipeline.inject_initialization_failure_after=StringName(stage);expected_error="injected_initialization/"+stage
	RenderingServer.call_on_render_thread(pipeline.initialize_render.bind(domain))
	while not pipeline.initialized and Time.get_ticks_msec()-started<20000:await process_frame
	check("failed_init_observable",pipeline.initialized and not pipeline._ready and String(pipeline.fault_reason()).begins_with(expected_error))
	observations.failure={"error":String(pipeline.initialization_error),"ownership_at_failure":pipeline.initialization_ownership.duplicate(true),"released":pipeline.released,"unknown":pipeline.initialization_cleanup_unknown,"pending":pipeline.initialization_cleanup_pending}
	if probe_case=="init_compile":
		observations.compiler_error=pipeline.views.actual_compile_error
		observations.compiler_source=FailedViews.BROKEN_SOURCE
		check("actual_glsl_compile_rejection",not pipeline.views.actual_compile_error.is_empty() and "deliberately_invalid_token" in pipeline.views.actual_compile_error)
	if probe_case=="init_unknown":
		await sample("unknown")
		check("unknown_retains_every_owner",not pipeline.released and pipeline.initialization_cleanup_unknown and observed.counts==pipeline.initialization_ownership)
		check("ordinary_release_cannot_bypass_unknown",not pipeline.released)
		RenderingServer.call_on_render_thread(pipeline.release_render)
		await sample("after_blocked_release")
		check("blocked_release_retains_every_owner",not pipeline.released and observed.counts==pipeline.initialization_ownership)
		RenderingServer.call_on_render_thread(_enable_idle_proof)
		pipeline.retry_initialization_cleanup()
		var begin:=Time.get_ticks_msec()
		while not pipeline.released and Time.get_ticks_msec()-begin<10000:await process_frame
	await sample("final")
	var empty:=true
	for count in observed.counts.values():empty=empty and count==0
	check("every_owner_released_after_real_proof",pipeline.released and empty and not pipeline.initialization_cleanup_pending and not pipeline.initialization_cleanup_unknown)
	check("failure_root_cause_preserved",String(pipeline.fault_reason()).begins_with(expected_error))
	check("no_fabricated_work_or_completion",pipeline.completed_state_seq==0 and pipeline.completed_tick==0 and pipeline.completed_revision==0 and pipeline.executor.recorded_commands==0 and pipeline.active_count()==0 and pipeline.pending_count()==0 and pipeline._results.is_empty())
	check("failed_pipeline_admission_closed",not pipeline.submit_intent(request(1,&"fill_v1",Vector2.ZERO)).accepted and pipeline.request_tick(0.001)==&"backend_failed")
	RenderingServer.call_on_render_thread(pipeline.initialize_render.bind(domain))
	await sample("duplicate_init")
	check("duplicate_initialize_cannot_reallocate",observed.counts==observations.final.counts and pipeline.released)
	finish()

func _enable_idle_proof() -> void:pipeline.transport.inject_idle_fence_unavailable=false

func sample(label: String) -> void:
	observed={};RenderingServer.call_on_render_thread(_sample_render.bind(label))
	var begin:=Time.get_ticks_msec()
	while observed.is_empty() and Time.get_ticks_msec()-begin<10000:await process_frame
	check("sample_"+label,not observed.is_empty())

func _sample_render(label: String) -> void:
	var record:={"counts":pipeline.ownership_counts(),"idle_serial":pipeline.transport._idle_serial,"idle_receipt_hex":pipeline.transport.idle_receipt.hex_encode(),"idle_pending":pipeline.transport._idle_pending,"has_owned_work":pipeline.transport.has_owned()}
	call_deferred("_sampled",label,record)

func _sampled(label: String, record: Dictionary) -> void:observed=record;observations[label]=record.duplicate(true)

func finish() -> void:
	var report:={"pass":not failed,"case":probe_case,"checks":checks,"observations":observations,"fault":String(pipeline.fault_reason()),"source_hashes":source_hashes,"engine":Engine.get_version_info(),"elapsed_ms":Time.get_ticks_msec()-started,"scope":"Candidate initialization lifecycle: real staged resources, real compiler failure, GPU idle proof, unknown retention and explicit cleanup retry. No formal entry or full restore claim."}
	if not output.is_empty():FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	quit(1 if failed else 0)
