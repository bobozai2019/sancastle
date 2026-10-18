extends "res://tests/integration/unified_edit_restore_probe.gd"

const Reference=preload("res://tests/integration/unified_edit_legacy_visual_reference.gd")
var reference:=Reference.new()
var reference_done:=false
var reference_ok:=false
var capture_result: Dictionary={}
var displays: Array=[]

func _run() -> void:
	started=Time.get_ticks_msec();DisplayServer.window_set_size(Vector2i(1280,720));DisplayServer.window_set_title("Unified enabled display histories")
	var created: Dictionary=load("res://assets/unified_edit/default_catalog.tres").instantiate_registry();registry=created.registry;check("registry",created.error.is_empty())
	var simulation:={"enable_erosion":false,"enable_brush_water":true,"unrestricted_sand_tools":true,"enable_structures":false,"local_front_history":probe_case not in ["visual_foam","visual_gravel"],"rise_front_history":false,"contact_history":false}
	var extras:=PackedStringArray(Pipeline.SOURCE_PATHS+Pipeline.ADAPTER_SOURCES+Reference.SOURCES+[get_script().resource_path,"res://tests/integration/unified_edit_restore_probe.gd","res://tests/fixtures/unified_edit/visual_consumer.tscn","res://tests/fixtures/unified_edit/visual_consumer.gdshader"])
	var frozen:=Config.freeze(registry,"main_beach",simulation,{"foam_enabled":probe_case!="visual_gravel","gravel_enabled":probe_case!="visual_foam" and probe_case!="visual_front"},{},{"engine":Engine.get_version_info().string,"probe":probe_case,"local_front_wide_field":probe_case=="visual_wide"},extras)
	check("configuration",frozen.error.is_empty());configuration=frozen.value;source_hashes=configuration.sources.duplicate(true)
	check("configure",pipeline.configure(registry,configuration,9007199254740993).is_empty())
	domain=Domain.new(256,0.125);domain.domain_id=&"main_beach";domain.generation=9007199254740993
	domain.rock.fill(0.05);domain.sand.fill(0.25);domain.water.fill(0.1);domain.wetness.fill(0.1);domain.compaction.fill(0.3)
	var qx:=PackedFloat32Array();qx.resize(65536)
	for z in 256:
		for x in 256:
			var at:=z*256+x;domain.sand[at]+=0.003*sin(float(x)*0.1);domain.water[at]=0.1 if x<160 else 0.005;qx[at]=0.045*cos(float(x)*0.03)
	domain.set_meta("edit_validation_initial_qx",qx)
	if probe_case in ["visual_init_failure","visual_init_unknown"]:
		pipeline.inject_initialization_failure_after=&"visuals";pipeline.transport.inject_idle_fence_unavailable=probe_case=="visual_init_unknown"
	RenderingServer.call_on_render_thread(pipeline.initialize_render.bind(domain))
	var begin:=Time.get_ticks_msec()
	while not pipeline.initialized and Time.get_ticks_msec()-begin<25000:await process_frame
	if probe_case in ["visual_init_failure","visual_init_unknown"]:
		check("visual_initialization_failure_reported",pipeline.initialized and pipeline.initialization_error==&"injected_initialization/visuals" and not pipeline._ready)
		observations.initialization={"owners_before_cleanup":pipeline.initialization_ownership.duplicate(true),"cleanup_unknown":pipeline.initialization_cleanup_unknown,"owners_held":pipeline.ownership_counts()}
		if probe_case=="visual_init_unknown":
			check("visual_unknown_retains_all_owned_rids",not pipeline.released and pipeline.initialization_cleanup_unknown and pipeline.ownership_counts()==pipeline.initialization_ownership)
			RenderingServer.call_on_render_thread(_allow_cleanup);await process_frame;pipeline.retry_initialization_cleanup();begin=Time.get_ticks_msec()
			while not pipeline.released and Time.get_ticks_msec()-begin<10000:await process_frame
		check("visual_failed_factory_all_resources_released",pipeline.released)
		await shutdown_visuals();finish();return
	check("initialized",pipeline.initialized and pipeline.fault_reason().is_empty())
	if not pipeline._ready:observations.error=String(pipeline.fault_reason());await shutdown_visuals();finish();return
	observations.initial=await snapshot(pipeline,"initial")
	var display=bind_display(pipeline)
	RenderingServer.call_on_render_thread(_reference_initialize)
	while not reference_done:await process_frame
	check("original_display_classes_initialized",reference_ok)
	check("tick_accepted",pipeline.request_tick(0.001).is_empty());await await_idle()
	observations.first=await snapshot(pipeline,"first")
	observations.first_render=await render_display(display,"first")
	reference_done=false;RenderingServer.call_on_render_thread(_reference_step.bind(pipeline.advanced_time_s))
	while not reference_done:await process_frame
	check("original_display_classes_stepped",reference_ok)
	for field in observations.reference:
		var key: String="visual_view/"+field
		if field=="bed":key="visual/bed_"+str(pipeline.visuals.foam_index)
		check("original_kernel_exact_"+field,observations.reference[field].sha256==observations.first[key].sha256)
	if probe_case in ["visual_fatal","visual_bad_cfl"]:
		armed=false;RenderingServer.call_on_render_thread(_poison_visual_work)
		while not armed:await process_frame
		observations.fatal_before=await snapshot(pipeline,"fatal_before")
		if probe_case=="visual_bad_cfl":check("bad_cfl_tick_admitted",pipeline.request_tick(0.001).is_empty())
		else:
			for id in range(1,4):check("fatal_edit_"+str(id),pipeline.submit_intent(request(id,&"fill_v1",Vector2(2,1))).accepted)
		begin=Time.get_ticks_msec()
		while pipeline.fault_reason().is_empty() and Time.get_ticks_msec()-begin<10000:await process_frame
		check("visual_real_fatal_observed",not pipeline.fault_reason().is_empty())
		observations.fatal_after=await snapshot(pipeline,"fatal_after");observations.fatal_render=await render_display(display,"fatal")
		for field in pipeline.visuals.published:check("fatal_preserves_published_"+field,observations.fatal_before["visual_view/"+field].sha256==observations.fatal_after["visual_view/"+field].sha256)
		pipeline.cleanup_fault();begin=Time.get_ticks_msec()
		while pipeline.active_count()>0 and Time.get_ticks_msec()-begin<10000:await process_frame
		check("visual_fatal_borrowers_drained",pipeline.active_count()==0)
		await shutdown_visuals();finish();return
	if probe_case=="visual_edit":
		var raw: PackedFloat32Array=FileAccess.get_file_as_bytes(observations.first["visual/gravel_0"].path).to_float32_array()
		check("edit_only_admitted",pipeline.submit_intent(request(1,&"fill_v1",Vector2(raw[17*4],raw[17*4+2]),0.04)).accepted);await await_idle()
		observations.edit_only=await snapshot(pipeline,"edit_only");observations.edit_render=await render_display(display,"edit_only")
		reference_done=false;reference_bytes={};reference_stage="edit_reference";RenderingServer.call_on_render_thread(_reference_project)
		while not reference_done:await process_frame
		check("original_edit_reprojection_exact",observations.edit_reference.gravel.sha256==observations.edit_only["visual_view/gravel"].sha256)
	var selection:={"policy":0,"speed":0.0,"brush":{"tool":&"place_sand","parameters":{},"dig_amount_m3":0.05,"fill_amount_m3":0.05}}
	var path:=output.get_base_dir()+"/enabled.sandue"
	check("capture_accepted",pipeline.save_checkpoint(path,selection,func(value: Dictionary):capture_result=value).accepted)
	if probe_case=="visual_capture_unknown":
		pipeline.checkpoint_capture.inject_registration_failure_once=true;pipeline.transport.inject_idle_fence_unavailable=true;begin=Time.get_ticks_msec()
		while not pipeline.checkpoint_status().get("unknown",false) and Time.get_ticks_msec()-begin<10000:await process_frame
		observations.capture_unknown={"status":pipeline.checkpoint_status(),"owners":pipeline.ownership_counts(),"registered":pipeline.checkpoint_capture.registered,"pending":pipeline.checkpoint_capture.pending,"callback_count":0 if capture_result.is_empty() else 1}
		check("unknown_visual_readers_keep_resources",pipeline.checkpoint_status().get("unknown",false) and capture_result.is_empty() and not pipeline.released)
		RenderingServer.call_on_render_thread(_allow_cleanup);await process_frame;pipeline.retry_checkpoint_lifetime();begin=Time.get_ticks_msec()
		while capture_result.is_empty() and Time.get_ticks_msec()-begin<10000:await process_frame
		check("unknown_capture_reports_real_error_after_proof",capture_result.get("error")==&"checkpoint_readback_registration" and not FileAccess.file_exists(path))
		observations.capture_error=capture_result;observations.capture_info=pipeline.last_checkpoint_info.duplicate(true);observations.unknown_after=await snapshot(pipeline,"unknown_after")
		await shutdown_visuals();finish();return
	begin=Time.get_ticks_msec()
	while capture_result.is_empty() and Time.get_ticks_msec()-begin<15000:await process_frame
	check("enabled_capture_valid",capture_result.get("error",&"missing")==&"")
	if capture_result.get("error",&"missing")!=&"":observations.capture_error=capture_result;await shutdown_visuals();finish();return
	var loaded:=Codec.load(path,configuration);check("enabled_container_loaded",loaded.error.is_empty())
	observations.container={"path":path,"sha256":FileAccess.get_sha256(path)};observations.capture_info=pipeline.last_checkpoint_info.duplicate(true)
	var checkpoint: Dictionary=loaded.checkpoint
	if probe_case=="visual_indices":
		checkpoint.native.foam.current_index=1
		checkpoint.native.foam.foam_0.encode_float(0,0.33);checkpoint.native.foam.bed_0.encode_float(0,0.77)
		checkpoint.visual_extensions.gravel_v1.current_index=1
		checkpoint.visual_extensions.gravel_v1.state_0.encode_float(4,0.6)
		check("distinct_native_visual_indices_valid",Codec.validate(checkpoint,configuration).is_empty())
		observations.modified_fixture=save_fields({"foam_0":checkpoint.native.foam.foam_0,"bed_0":checkpoint.native.foam.bed_0,"gravel_0":checkpoint.visual_extensions.gravel_v1.state_0},"distinct_fixture")
	candidate=Pipeline.new();candidate.restore_verifier.capture_bytes=true
	if probe_case=="visual_restore_failure":candidate.restore_verifier.inject_registration_failure_once=true
	check("candidate_configured",candidate.configure_restore(registry,configuration,EPOCH,checkpoint).is_empty())
	RenderingServer.call_on_render_thread(candidate.initialize_render.bind(candidate.restore_domain()))
	begin=Time.get_ticks_msec()
	while not candidate.initialized and Time.get_ticks_msec()-begin<25000:await process_frame
	if probe_case=="visual_restore_failure":
		check("enabled_candidate_failure_retired",not candidate._ready and candidate.initialization_error==&"restore_readback_registration" and candidate.released)
		observations.failed_restore={"error":candidate.initialization_error,"records":candidate.restore_verifier.records.duplicate(true),"owners_before_cleanup":candidate.initialization_ownership.duplicate(true)}
		observations.source_after_failed_restore=await snapshot(pipeline,"source_after_failed_restore")
		for field in observations.first:check("failed_candidate_preserves_current_"+field,observations.first[field].sha256==observations.source_after_failed_restore[field].sha256)
		await shutdown_visuals();finish();return
	check("enabled_candidate_verified",candidate._ready and candidate.restore_verifier.passed)
	observations.verifier=candidate.restore_verifier.records.duplicate(true);observations.restored=await snapshot(candidate,"restored")
	var candidate_display=bind_display(candidate);observations.restored_render=await render_display(candidate_display,"restored")
	var frozen_fixture: Dictionary=checkpoint.native.foam.duplicate(true)
	if pipeline.visuals.foam_enabled:
		for index in 2:
			for prefix in ["foam_","bed_"]:
				var key: String=prefix+str(index);check("restored_native_"+key,FileAccess.get_file_as_bytes(observations.restored["visual/"+key].path)==frozen_fixture[key])
	candidate_pump=true
	for subject in [pipeline,candidate]:
		var edit:=request(checkpoint.highwater_id+1,&"fill_v1",Vector2(2,1),0.02);edit.generation=subject._generation
		check("continued_edit_"+str(subject._generation),subject.submit_intent(edit).accepted);check("continued_tick_"+str(subject._generation),subject.request_tick(0.001).is_empty())
	await await_idle();begin=Time.get_ticks_msec()
	while (candidate.active_count()>0 or candidate.pending_count()>0) and Time.get_ticks_msec()-begin<15000:await process_frame
	check("restored_second_work_complete",candidate.fault_reason().is_empty() and candidate.active_count()==0 and candidate.pending_count()==0)
	observations.source_second=await snapshot(pipeline,"source_second");observations.candidate_second=await snapshot(candidate,"candidate_second")
	observations.second_render=await render_display(display,"second");observations.candidate_second_render=await render_display(candidate_display,"candidate_second")
	if probe_case!="visual_indices":
		for field in observations.source_second:
			if field in ["control","stamp"]:continue
			check("continued_exact_"+field,observations.source_second[field].sha256==observations.candidate_second[field].sha256)
	await shutdown_visuals();finish()

func _reference_initialize() -> void:
	var valid:=reference.initialize(pipeline,domain,configuration);call_deferred("_reference_finished",valid)

func _reference_finished(valid: bool) -> void:reference_ok=valid;reference_done=true

func _reference_step(dt: float) -> void:
	var valid:=reference.step(dt)
	var images: Dictionary=reference.output_images();call_deferred("_reference_reads_started",images.size(),valid)
	for key in images:reference.rd.texture_get_data_async(images[key],0,_reference_arrived.bind(key))

var reference_pending:=0
var reference_bytes: Dictionary={}
var reference_stage:="reference"
func _reference_reads_started(count: int, valid: bool) -> void:reference_pending=count;reference_ok=valid
func _reference_arrived(bytes: PackedByteArray, key: String) -> void:call_deferred("_reference_received",bytes,key)
func _reference_received(bytes: PackedByteArray, key: String) -> void:
	reference_bytes[key]=bytes;reference_pending-=1
	if reference_pending==0:observations[reference_stage]=save_fields(reference_bytes,reference_stage);reference_done=true

func _reference_project() -> void:
	var valid:=reference.reproject(pipeline.completed_tick,pipeline.completed_revision)
	var images: Dictionary=reference.output_images();call_deferred("_reference_reads_started",images.size(),valid)
	for key in images:reference.rd.texture_get_data_async(images[key],0,_reference_arrived.bind(key))

func _allow_cleanup() -> void:pipeline.transport.inject_idle_fence_unavailable=false

func _poison_visual_work() -> void:
	if probe_case=="visual_bad_cfl":
		var data:=PackedByteArray();data.resize(65536*4);data.encode_float(0,NAN)
		var rid: RID=pipeline.state._create_texture(RenderingDevice.DATA_FORMAT_R32_SFLOAT,data)
		pipeline.transport.rd.texture_copy(rid,pipeline.state.textures.momentum_x[0],Vector3.ZERO,Vector3.ZERO,Vector3(256,256,1),0,0,0,0)
	else:pipeline.transport.rd.buffer_update(pipeline.transport.control,40,8,PackedInt64Array([9223372036854775806]).to_byte_array())
	call_deferred("_armed")

func snapshot(subject, label: String) -> Dictionary:
	snapshot_fields={};snapshot_pending=25+subject.visuals.capture_images().size()+subject.visuals.published.size();RenderingServer.call_on_render_thread(_snapshot_render.bind(subject))
	var begin:=Time.get_ticks_msec()
	while snapshot_pending>0 and Time.get_ticks_msec()-begin<10000:await process_frame
	check("snapshot_"+label,snapshot_pending==0);return save_fields(snapshot_fields,label)

func _snapshot_render(subject) -> void:
	super._snapshot_render(subject)
	var images: Dictionary=subject.visuals.capture_images()
	for field in subject.visuals.published:images["visual_view/"+field]=subject.visuals.published[field]
	for key in images:
		if subject.transport.rd.texture_get_data_async(images[key],0,_snapshot_arrived.bind(key))!=OK:call_deferred("_snapshot_failed",key)

func shutdown_visuals() -> void:
	RenderingServer.call_on_render_thread(reference.release)
	for subject in [pipeline,candidate]:
		if subject!=null and not subject.views.bindings.is_empty():check("material_detached_"+str(subject._generation),await subject.views.detach_bindings())
	await shutdown();observations.source_ownership=pipeline.ownership_counts()
	for display in displays:display.queue_free()
	await process_frame

func bind_display(subject):
	var display=load("res://tests/fixtures/unified_edit/visual_consumer.tscn").instantiate();root.add_child(display);displays.append(display)
	var parameters: Dictionary={}
	for pair in [["foam","foam_state"],["local_front","front_state"],["gravel","gravel_state"]]:
		if subject.visuals.published.has(pair[0]):parameters[pair[1]]=pair[0]
	for name in ["Foam","Front","Gravel"]:check("material_bound_"+name+"_"+str(subject._generation),subject.views.bind_material(display.get_node(name).material,parameters).is_empty())
	return display

func render_display(display, label: String) -> Dictionary:
	await RenderingServer.frame_post_draw;await RenderingServer.frame_post_draw
	var image: Image=display.get_texture().get_image();var path:=output.get_base_dir()+"/"+label+".png"
	check("render_"+label,image.save_png(path)==OK)
	return {"path":path,"sha256":FileAccess.get_sha256(path)}

func finish() -> void:
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"case":probe_case,"checks":checks,"observations":observations,"source_hashes":source_hashes,"engine":Engine.get_version_info(),"scope":"Enabled foam/local-front/gravel common tail, original independent recorder comparison, real native capture and candidate continuation. No prescribed tide/wave or formal entry/cost claim."},"\t"));quit(1 if failed else 0)
