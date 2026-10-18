extends "res://tests/integration/unified_edit_gpu_probe.gd"

const Codec=preload("res://scripts/simulation/unified_edit/checkpoint_codec.gd")
const Half=preload("res://scripts/simulation/unified_edit/unit_half.gd")
var candidate
var candidate_pump:=false
var observations: Dictionary={}
var configuration: Dictionary={}
var snapshot_fields: Dictionary={}
var snapshot_pending:=0
var surface
var callback_probe_done:=false
const EPOCH:=9007199254740994

func _process(_delta: float) -> bool:
	pipeline.pump()
	if candidate_pump:candidate.pump()
	return false

func _run() -> void:
	started=Time.get_ticks_msec();DisplayServer.window_set_size(Vector2i(1280,720));DisplayServer.window_set_title("Unified native restore candidate")
	var created: Dictionary=load("res://assets/unified_edit/default_catalog.tres").instantiate_registry()
	check("registry",created.error.is_empty());registry=created.registry
	var simulation:={"enable_erosion":true,"enable_brush_water":true,"unrestricted_sand_tools":true,"enable_structures":false,"local_front_history":false,"rise_front_history":false,"contact_history":false}
	var extra:=PackedStringArray(Pipeline.SOURCE_PATHS+Pipeline.ADAPTER_SOURCES);extra.append(get_script().resource_path)
	var frozen:=Config.freeze(registry,"main_beach",simulation,{"foam_enabled":false,"gravel_enabled":false},{},{"engine":Engine.get_version_info().string,"probe":probe_case,"ordinary_cohesion_yield_height_m":0.025 if probe_case=="restore_cohesion" else 0.0},extra)
	check("configuration",frozen.error.is_empty())
	if not frozen.error.is_empty():finish();return
	configuration=frozen.value;source_hashes=configuration.sources.duplicate(true)
	check("configure_source",pipeline.configure(registry,configuration,9007199254740993).is_empty())
	domain=Domain.new(256,0.125);domain.domain_id=&"main_beach";domain.generation=9007199254740993
	domain.rock.fill(0.05);domain.sand.fill(0.3);domain.water.fill(0.1);domain.sediment.fill(0.02);domain.wetness.fill(0.1);domain.compaction.fill(0.3)
	var tagged:=PackedFloat32Array();tagged.resize(65536)
	for z in 256:
		for x in 256:
			var index:=z*256+x;domain.sand[index]+=float((x+z)%7)*0.001
			if probe_case=="restore_cohesion":domain.sand[index]+=exp(-Vector2(x-128,z-128).length_squared()/8.0)
			if x<64:tagged[index]=0.05
	domain.set_meta("brush_initial_mold_depth",tagged)
	RenderingServer.call_on_render_thread(pipeline.initialize_render.bind(domain))
	while not pipeline.initialized and Time.get_ticks_msec()-started<20000:await process_frame
	check("source_initialized",pipeline.initialized and pipeline.fault_reason().is_empty())
	if not pipeline.fault_reason().is_empty():finish();return
	check("source_fill",pipeline.submit_intent(request(41,&"fill_v1",Vector2(2,1))).accepted)
	check("source_dig",pipeline.submit_intent(request(42,&"dig_v1",Vector2(-2,-1))).accepted)
	check("source_tick",pipeline.request_tick(0.001).is_empty());await await_idle()
	var source:=await snapshot(pipeline,"source")
	observations.source=source
	var checkpoint:=make_checkpoint(source)
	if probe_case=="restore_distinct":
		for group in [checkpoint.native.fields,checkpoint.native.spare]:
			for field in ["wetness","compaction"]:
				for index in 65536:
					var code: int=(index if field=="wetness" else 65535-index)%(0x3c01+1)
					group[field].encode_u16(index*2,code if code<0x3c01 else 0x8000)
		for field in ["momentum_x","momentum_z","flux"]:checkpoint.native.spare[field].encode_u32(0,0x80000000);checkpoint.native.spare[field].encode_u32(4,1)
	check("checkpoint_valid",Codec.validate(checkpoint,configuration).is_empty())
	var fixture_path:=output.get_base_dir()+"/captured.sandue"
	check("container_saved",Codec.save(fixture_path,checkpoint,configuration).is_empty())
	var loaded:=Codec.load(fixture_path,configuration)
	check("container_loaded_exact",loaded.error.is_empty() and loaded.get("checkpoint")==checkpoint)
	observations.container={"path":fixture_path,"sha256":FileAccess.get_sha256(fixture_path),"origin":"source GPU fields/control captured after two edits and one real water tick; disabled foam envelope is zero metadata; distinct case explicitly modifies valid native boundary fixture bytes"}
	if not loaded.error.is_empty():await shutdown();finish();return
	observations.native_fixture=save_native(checkpoint.native,"fixture")
	for group_name in ["fields","spare"]:
		for field in ["wetness","compaction"]:
			var bad:=checkpoint.duplicate(true);bad.native[group_name][field].encode_u16(0,0x8001)
			var rejected:=Pipeline.new();check("reject_negative_subnormal_"+group_name+"_"+field,rejected.configure_restore(registry,configuration,EPOCH,bad)==&"invalid_pipeline_half" and rejected._registry==null)
	var rejected:=Pipeline.new();check("same_generation_rejected",rejected.configure_restore(registry,configuration,checkpoint.generation,checkpoint)==&"restore_generation_not_new")
	var wrong_cohesion:=checkpoint.duplicate(true);wrong_cohesion.cohesion_yield_height_m=0.1
	check("wrong_ordinary_cohesion_rejected",Pipeline.new().configure_restore(registry,configuration,EPOCH,wrong_cohesion)==&"restore_ordinary_cohesion_configuration_mismatch")
	candidate=Pipeline.new();candidate.restore_verifier.capture_bytes=true
	if probe_case in ["restore_hold","restore_cancel"]:candidate.restore_verifier.hold_delivery=true
	if probe_case in ["restore_registration","restore_unknown"]:candidate.restore_verifier.inject_registration_failure_once=true
	if probe_case=="restore_corrupt":candidate.restore_verifier.inject_corruption_once=true
	if probe_case=="restore_unknown":candidate.transport.inject_idle_fence_unavailable=true
	check("configure_restore",candidate.configure_restore(registry,configuration,EPOCH,loaded.checkpoint).is_empty())
	loaded.checkpoint.native.fields.sand.encode_float(0,999.0);loaded.checkpoint.highwater_id=1
	check("restore_immutable_caller_snapshot",candidate._restore.native.fields.sand==checkpoint.native.fields.sand and candidate._highwater==42)
	RenderingServer.call_on_render_thread(candidate.initialize_render.bind(candidate.restore_domain()))
	if probe_case in ["restore_hold","restore_cancel"]:
		var begin:=Time.get_ticks_msec()
		while candidate.restore_verifier.held.size()<35 and Time.get_ticks_msec()-begin<10000:await process_frame
		observations.held={"count":candidate.restore_verifier.held.size(),"pending":candidate.restore_verifier.pending,"initialized":candidate.initialized,"ready":candidate._ready,"owners":candidate.ownership_counts()}
		check("readback_hold_blocks_ready_and_admission",not candidate.initialized and not candidate._ready and candidate.restore_verifier.pending>0 and not candidate.submit_intent(candidate_request(43)).accepted)
		callback_probe_done=false;RenderingServer.call_on_render_thread(_duplicate_callbacks_render.bind(true))
		while not callback_probe_done:await process_frame
		if probe_case=="restore_cancel":check("cancel_inflight_initialization",candidate.cancel_initialization() and not candidate._ready)
		RenderingServer.call_on_render_thread(candidate.restore_verifier.release_held_render)
	var begin:=Time.get_ticks_msec()
	while not candidate.initialized and Time.get_ticks_msec()-begin<20000:await process_frame
	check("restore_build_terminal",candidate.initialized)
	observations.verification={"passed":candidate.restore_verifier.passed,"error":String(candidate.restore_verifier.error),"records":candidate.restore_verifier.records.duplicate(true),"captured":save_fields(candidate.restore_verifier.raw_fields,"verified")}
	observations.cohesion={"environment":configuration.environment.ordinary_cohesion_yield_height_m,"checkpoint":checkpoint.cohesion_yield_height_m,"source_state":pipeline.state.cohesion_yield_height_m,"candidate_state":candidate.state.cohesion_yield_height_m,"source_push_hex":pipeline.coupled.slope_push.hex_encode(),"candidate_push_hex":candidate.coupled.slope_push.hex_encode()}
	callback_probe_done=false;RenderingServer.call_on_render_thread(_duplicate_callbacks_render.bind(false))
	while not callback_probe_done:await process_frame
	if probe_case in ["restore_registration","restore_corrupt","restore_unknown","restore_cancel"]:
		check("failed_candidate_not_ready",not candidate._ready and not candidate.fault_reason().is_empty())
		if probe_case=="restore_unknown":
			observations.unknown={"owners":candidate.ownership_counts(),"original_owners":candidate.initialization_ownership.duplicate(true),"released":candidate.released,"unknown":candidate.initialization_cleanup_unknown}
			check("unknown_retains_all_resources",not candidate.released and candidate.initialization_cleanup_unknown and candidate.ownership_counts()==candidate.initialization_ownership)
			RenderingServer.call_on_render_thread(_allow_retry);candidate.retry_initialization_cleanup()
			begin=Time.get_ticks_msec()
			while not candidate.released and Time.get_ticks_msec()-begin<10000:await process_frame
		check("failed_candidate_cleaned",candidate.released and candidate.restore_verifier.pending==0)
		if not candidate.released and candidate.initialization_cleanup_unknown:
			observations.unexpected_cleanup=cleanup_observation()
			candidate.retry_initialization_cleanup();begin=Time.get_ticks_msec()
			while not candidate.released and Time.get_ticks_msec()-begin<10000:await process_frame
			check("unexpected_cleanup_explicit_retry_releases",candidate.released)
	else:
		check("verified_candidate_ready",candidate._ready and candidate.restore_verifier.passed and candidate.restore_verifier.records.size()==35)
		check("saved_actual_counters_and_clock",candidate.completed_state_seq==checkpoint.state_seq and candidate.completed_tick==checkpoint.sim_tick and candidate.completed_revision==checkpoint.revision and candidate.advanced_time_s==checkpoint.advanced_time_s)
		check("saved_highwater_rejects_reused_id",not candidate.submit_intent(candidate_request(42)).accepted and candidate.result_reservations()==0)
		await verify_physics(checkpoint)
	var unchanged:=await snapshot(pipeline,"source_after_candidate")
	for field in source:check("active_domain_unchanged_"+field,source[field].sha256==unchanged[field].sha256)
	observations.active_after_candidate=unchanged
	if not candidate.released:
		candidate_pump=true
		check("candidate_next_edit",candidate.submit_intent(candidate_request(43)).accepted)
		check("candidate_next_tick",candidate.request_tick(0.001).is_empty())
		check("source_same_edit",pipeline.submit_intent(request(43,&"fill_v1",Vector2(3,2))).accepted)
		check("source_same_tick",pipeline.request_tick(0.001).is_empty())
		await await_idle();begin=Time.get_ticks_msec()
		while (candidate.active_count()>0 or candidate.pending_count()>0) and Time.get_ticks_msec()-begin<15000:await process_frame
		check("candidate_second_operation_completed",candidate.active_count()==0 and candidate.pending_count()==0 and candidate.fault_reason().is_empty() and candidate.result(43).outcome==L.Outcome.APPLIED and candidate.result(43).generation==EPOCH)
		observations.second={"source":await snapshot(pipeline,"source_second"),"candidate":await snapshot(candidate,"candidate_second"),"result":candidate.result(43),"state_seq":candidate.completed_state_seq,"tick":candidate.completed_tick,"revision":candidate.completed_revision,"time_s":candidate.advanced_time_s}
		if probe_case!="restore_distinct":
			for field in observations.second.source:
				if field in ["control","stamp"]:continue
				check("second_operation_exact_"+field,observations.second.source[field].sha256==observations.second.candidate[field].sha256)
	else:
		check("active_still_accepts_after_failed_candidate",pipeline.submit_intent(request(43,&"fill_v1",Vector2(3,2))).accepted);await await_idle()
		check("active_completes_after_failed_candidate",pipeline.result(43).outcome==L.Outcome.APPLIED)
	await shutdown();finish()

func candidate_request(id: int) -> Dictionary:
	var value:=request(id,&"fill_v1",Vector2(3,2));value.generation=EPOCH;value.sim_tick=candidate.completed_tick if candidate!=null else pipeline.completed_tick;return value

func _allow_retry() -> void:candidate.transport.inject_idle_fence_unavailable=false

func _duplicate_callbacks_render(while_held: bool) -> void:
	var reader=candidate.restore_verifier
	var before:={"pending":reader.pending,"held":reader.held.size(),"records":reader.records.size()}
	var data: Dictionary=reader.held if while_held else reader.raw_fields
	var key: String=data.keys()[0];var bytes: PackedByteArray=data[key]
	reader._arrived(bytes,key);reader._arrived(bytes,key);reader._arrived(bytes,"stale_unknown_key")
	var after:={"pending":reader.pending,"held":reader.held.size(),"records":reader.records.size()}
	call_deferred("_callbacks_checked",while_held,before,after)

func _callbacks_checked(while_held: bool, before: Dictionary, after: Dictionary) -> void:
	observations["duplicate_held" if while_held else "late_callbacks"]={"before":before,"after":after}
	check("duplicate_or_late_callbacks_ignored_"+str(while_held),before==after);callback_probe_done=true

func cleanup_observation() -> Dictionary:
	return {"pending":candidate.initialization_cleanup_pending,"unknown":candidate.initialization_cleanup_unknown,"idle_serial":candidate.transport._idle_serial,"idle_receipt_hex":candidate.transport.idle_receipt.hex_encode(),"verifier_pending":candidate.restore_verifier.pending,"has_owned_work":candidate.transport.has_owned(),"height_active":candidate.heights.active_count(),"views_can_release":candidate.views.can_release(),"idle_pending":candidate.transport._idle_pending}

func make_checkpoint(source: Dictionary) -> Dictionary:
	var current:={};var spare:={}
	for field in Codec.Old.FIELD_BYTES:current[field]=FileAccess.get_file_as_bytes(source["field/"+field].path)
	for field in Codec.Old.SPARE:spare[field]=FileAccess.get_file_as_bytes(source["spare/"+field].path)
	var control: PackedByteArray=FileAccess.get_file_as_bytes(source.control.path)
	var zero_foam:=PackedByteArray();zero_foam.resize(65536*8)
	var zero_bed:=PackedByteArray();zero_bed.resize(65536*4)
	var material:=Pipeline.State.MaterialCodec.make_record(FileAccess.get_file_as_bytes(source["material/0"].path),FileAccess.get_file_as_bytes(source["material/1"].path),true,FileAccess.get_sha256(Config.MATERIAL_PATH))
	var simulation: Dictionary=configuration.simulation.duplicate(true);simulation.prescribed_tide_boundary=false
	var total:=0.0
	for field in ["sand","sediment"]:
		for amount in domain.get(field):total+=float(amount)*0.015625
	return {"version":6,"protocol_family":"unified_edit","pipeline_protocol_version":1,"grid_size":256,"cell_size_m":0.125,"domain_id":"main_beach","generation":domain.generation,"state_seq":control.decode_s64(16),"sim_tick":control.decode_s64(24),"revision":control.decode_s64(40),"advanced_time_s":control.decode_float(32),"highwater_id":pipeline._highwater,"ticket_id":pipeline.slots._lease_seq,"configuration":configuration.duplicate(true),"simulation":simulation,"ledger_precision":Codec.PRECISION,"ledger":{"tool_inventory_m3":0.0,"sand_source_m3":pipeline.result(41).source_m3,"sand_sink_m3":pipeline.result(42).sink_m3,"water_source_m3":control.decode_float(88),"water_sink_m3":control.decode_float(92)},"initial_sand_total_m3":total,"nominal_upper_supply":0.0,"selection":{"policy":0,"speed":0.0,"brush":{"tool":&"place_sand","parameters":{},"dig_amount_m3":0.05,"fill_amount_m3":0.05}},"cohesion_yield_height_m":pipeline.state.cohesion_yield_height_m,"wave_requests":[],"wave_highwater_id":0,"wave_start_times":{},"native":{"version":3,"current_index":0,"fields":current,"spare":spare,"material":material,"foam":{"current_index":0,"foam_0":zero_foam,"foam_1":zero_foam,"bed_0":zero_bed,"bed_1":zero_bed},"histories":{},"control":control},"visual_extensions":{"gravel_v1":{"version":2,"enabled":false}},"source_provenance":{"format":"native_v6","path":"","sha256":"","configuration":{},"trusted_fixture":{},"original_prefix":[],"policies":{}}}

func snapshot(subject, label: String) -> Dictionary:
	snapshot_fields={};snapshot_pending=25;RenderingServer.call_on_render_thread(_snapshot_render.bind(subject))
	var begin:=Time.get_ticks_msec()
	while snapshot_pending>0 and Time.get_ticks_msec()-begin<10000:await process_frame
	check("snapshot_"+label,snapshot_pending==0 and snapshot_fields.size()==25)
	return save_fields(snapshot_fields,label)

func _snapshot_render(subject) -> void:
	var images:={}
	for field in Codec.Old.FIELD_BYTES:images["field/"+field]=subject.state.textures[field] if field in ["rock","obstacle"] else subject.state.textures[field][0]
	for field in Codec.Old.SPARE:images["spare/"+field]=subject.state.textures[field][1]
	for index in 2:images["material/"+str(index)]=subject.state.textures.mold_support[index]
	images.published_sand=subject.state.published_sand;images.published_water=subject.state.published_water;images.clock=subject.transport.clock_texture
	for key in images:
		if subject.transport.rd.texture_get_data_async(images[key],0,_snapshot_arrived.bind(key))!=OK:call_deferred("_snapshot_failed",key)
	for pair in [["control",subject.transport.control,128],["stamp",subject.state.published_stamp,32]]:
		if subject.transport.rd.buffer_get_data_async(pair[1],_snapshot_arrived.bind(pair[0]),0,pair[2])!=OK:call_deferred("_snapshot_failed",pair[0])

func _snapshot_arrived(bytes: PackedByteArray, key: String) -> void:call_deferred("_snapshot_field",bytes,key)
func _snapshot_field(bytes: PackedByteArray, key: String) -> void:snapshot_fields[key]=bytes;snapshot_pending-=1
func _snapshot_failed(key: String) -> void:check("snapshot_readback_"+key,false);snapshot_pending-=1

func save_fields(data: Dictionary, label: String) -> Dictionary:
	var index:={}
	for key in data:
		var path:=output.get_base_dir()+"/"+label+"_"+String(key).replace("/","_")+".bin"
		FileAccess.open(path,FileAccess.WRITE).store_buffer(data[key]);index[key]={"path":path,"bytes":data[key].size(),"sha256":FileAccess.get_sha256(path)}
	return index

func save_native(native: Dictionary, label: String) -> Dictionary:
	var bytes:={"control":native.control}
	for group in ["fields","spare"]:
		for field in native[group]:bytes[("field/" if group=="fields" else "spare/")+field]=native[group][field]
	bytes["material/0"]=native.material.current_support;bytes["material/1"]=native.material.spare_support
	return save_fields(bytes,label)

func verify_physics(checkpoint: Dictionary) -> void:
	surface=load("res://scenes/unified_edit_height_surface.tscn").instantiate();root.add_child(surface)
	surface.consumer=candidate.heights;candidate.heights.proxy=surface;candidate.heights.notify_complete();candidate_pump=true
	var begin:=Time.get_ticks_msec()
	while (candidate.heights.applied_state_seq.size()!=64 or candidate.heights.active_count()>0 or candidate.heights.hinted) and Time.get_ticks_msec()-begin<15000:await process_frame
	check("restored_all_64_physics_chunks",candidate.heights.applied_state_seq.size()==64 and candidate.heights.active_count()==0)
	var maps:=PackedByteArray();var all_match:=true
	var rock: PackedFloat32Array=checkpoint.native.fields.rock.to_float32_array();var sand: PackedFloat32Array=checkpoint.native.fields.sand.to_float32_array()
	for chunk in 64:
		var shape: HeightMapShape3D=surface.shapes[chunk].shape
		if shape==null:all_match=false;continue
		var heights:=shape.map_data;maps.append_array(heights.to_byte_array())
		for z in 33:
			for x in 33:
				var at: int=mini(255,(chunk/8)*32+z)*256+mini(255,(chunk%8)*32+x)
				all_match=all_match and heights[z*33+x]==PackedFloat32Array([rock[at]+sand[at]])[0]
		all_match=all_match and candidate.heights.applied_state_seq.get(chunk)==checkpoint.state_seq
	check("restored_physics_exact_saved_bed_and_version",all_match)
	observations.physics={"maps":save_fields({"maps":maps},"physics").maps,"state_seq":candidate.heights.applied_state_seq.duplicate(true)}
	candidate.heights.close();surface.consumer=null;candidate.heights.proxy=null;surface.queue_free();await process_frame;candidate_pump=false

func shutdown() -> void:
	for subject in [pipeline,candidate]:
		if subject==null or subject.released:continue
		subject.close_admission();RenderingServer.call_on_render_thread(subject.release_render)
		var begin:=Time.get_ticks_msec()
		while not subject.released and Time.get_ticks_msec()-begin<10000:await process_frame
		check("released_"+("source" if subject==pipeline else "candidate"),subject.released)
	if candidate!=null:observations.final_ownership=candidate.ownership_counts();observations.final_fault=String(candidate.fault_reason());observations.cleanup=cleanup_observation()

func finish() -> void:
	var report:={"pass":not failed,"case":probe_case,"checks":checks,"observations":observations,"source_hashes":source_hashes,"engine":Engine.get_version_info(),"scope":"Real native checkpoint candidate restore/readback/second operation and isolated active-domain preservation. No formal atomic domain swap or enabled effects/boundary restore claim."}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"));quit(1 if failed else 0)
