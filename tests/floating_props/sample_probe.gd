extends "res://tests/integration/unified_edit_gpu_probe.gd"

const ProbeCodec=preload("res://scripts/simulation/unified_edit/probe_codec.gd")
const PropProfile=preload("res://scripts/props/floating_prop_profile.gd")
var receipt: Dictionary={}
var receipts: Array=[]
var callback_count:=0
var probe_id:=0
var released:=false

func _request(count: int=3) -> Dictionary:
	probe_id+=1
	var points: Array=[]
	for index in count:
		var position:=Vector3(-1.25+0.125*index,2.0,0.125*index)
		if index==0:position=Vector3(-16,0,-16)
		if index==1:position=Vector3(15.999,0,15.999)
		points.append({"body_id":9223372036854775807,"point_id":9007199254740993+index,"position":position})
	return {"domain_id":"main_beach","generation":pipeline._generation,"owner_token":9007199254740995,"pose_seq":1,"request_id":probe_id,"minimum_state_seq":0,"points":points,"footprints":[Rect2(-15.9,-15.9,31.8,31.8)]}

func _received(result: Dictionary) -> void:receipt=result;callback_count+=1

func _wait_receipt(before: int) -> void:
	var deadline:=Time.get_ticks_msec()+15000
	while callback_count==before and Time.get_ticks_msec()<deadline:await process_frame
	check("receipt_deadline_"+str(checks.size()),callback_count==before+1)

func _query(label: String, value: Dictionary, expected: StringName=&"") -> void:
	var before:=callback_count
	var accepted: Dictionary=pipeline.views.request_probe(value,_received)
	check(label+"_admitted",accepted.accepted)
	if not accepted.accepted:return
	await _wait_receipt(before)
	check(label+"_error",receipt.get("error",&"missing")==expected)
	_save(label,value)

func _save(label: String, value: Dictionary) -> void:
	var row:={"label":label,"request":value.duplicate(true),"result":receipt.duplicate(true)}
	var stem:=output.get_base_dir()+"/"+label
	var input:=ProbeCodec.encode(value,pipeline.views.probe.serial)
	FileAccess.open(stem+"_request.bin",FileAccess.WRITE).store_buffer(input)
	if receipt.has("raw"):
		FileAccess.open(stem+"_result.bin",FileAccess.WRITE).store_buffer(receipt.raw)
		row.result.erase("raw");row.raw_sha256=FileAccess.get_sha256(stem+"_result.bin")
	receipts.append(row)

func _run() -> void:
	started=Time.get_ticks_msec();DisplayServer.window_set_size(Vector2i(1280,720))
	check("CPU_GPU_depth_constants_exact",ProbeCodec.DRY_DEPTH_M==PackedFloat32Array([0.001])[0] and ProbeCodec.VELOCITY_DEPTH_M==PackedFloat32Array([0.005])[0])
	var profile:=PropProfile.new();profile.type_id=&"fixture";profile.point_positions_m=[Vector3.ZERO];profile.point_half_heights_m=PackedFloat32Array([0.1]);profile.point_volumes_m3=PackedFloat32Array([0.001]);profile.point_mass_weights=PackedFloat32Array([1.0])
	check("typed_physical_profile_valid",profile.validate().is_empty() and profile.get_script()==PropProfile and not profile.snapshot().is_empty())
	profile.point_mass_weights[0]=0.9
	check("profile_rejects_mass_partition",profile.validate()==&"invalid_profile")
	profile.point_mass_weights[0]=1.0;profile.mass_kg=NAN
	check("profile_rejects_nonfinite_mass",profile.validate()==&"invalid_profile")
	var created: Dictionary=load("res://assets/unified_edit/default_catalog.tres").instantiate_registry();registry=created.registry
	var flags:={"enable_erosion":false,"enable_brush_water":true,"unrestricted_sand_tools":true,"enable_structures":false,"local_front_history":false,"rise_front_history":false,"contact_history":false}
	var config:=Config.freeze(registry,"main_beach",flags,{"foam_enabled":false,"gravel_enabled":false},{},{"engine":Engine.get_version_info().string,"test":"floating_props_sample"},PackedStringArray(Pipeline.SOURCE_PATHS+Pipeline.ADAPTER_SOURCES))
	check("configuration",config.error.is_empty())
	if not config.error.is_empty():finish();return
	source_hashes=config.value.sources.duplicate(true)
	check("configure",pipeline.configure(registry,config.value,9007199254740993).is_empty())
	domain=Domain.new(256,0.125);domain.domain_id=&"main_beach";domain.generation=9007199254740993
	var qx:=PackedFloat32Array();var qz:=PackedFloat32Array();qx.resize(65536);qz.resize(65536)
	for index in 65536:
		var x: float=(float(index%256)+0.5-128.0)*0.125
		var z: float=(float(index/256)+0.5-128.0)*0.125
		domain.rock[index]=-0.2;domain.sand[index]=0.4+0.003*x+0.002*z
		domain.water[index]=0.3+0.001*x
		qx[index]=0.2+0.002*z;qz[index]=-0.1+0.001*x
		if probe_case=="constant":domain.sand[index]=0.4;domain.water[index]=0.3;qx[index]=0.12;qz[index]=-0.06
		if probe_case=="thin":domain.sand[index]=0.4;domain.water[index]=0.003;qx[index]=0.003;qz[index]=-0.0015
	# Dry corner deliberately retains momentum: the public sampler must zero u.
	if probe_case!="constant":domain.water[0]=0;qx[0]=9;qz[0]=-7
	if probe_case=="thin":domain.water[0]=0.0005
	domain.set_meta("edit_validation_initial_qx",qx);domain.set_meta("edit_validation_initial_qz",qz)
	RenderingServer.call_on_render_thread(pipeline.initialize_render.bind(domain))
	var deadline:=Time.get_ticks_msec()+25000
	while not pipeline.initialized and Time.get_ticks_msec()<deadline:await process_frame
	check("real_gpu_initialize",pipeline.initialized and pipeline.fault_reason().is_empty())
	if not pipeline._ready:finish();return
	var value:=_request(32)
	await _query("linear32",value)
	if receipt.error.is_empty():
		check("all32_and_int64_ids",receipt.points.size()==32 and receipt.points[31].body_id==9223372036854775807 and receipt.points[31].point_id==9007199254741024)
		var numerical:=true
		for index in 32:
			var point: Dictionary=receipt.points[index];var p: Vector3=point.sample_position
			var x:=clampf(p.x,-15.9375,15.9375);var z:=clampf(p.z,-15.9375,15.9375)
			var h:=0.3+0.001*x;var bed:=0.2+0.003*x+0.002*z
			var u:=Vector2(0.2+0.002*z,-0.1+0.001*x)/h
			if probe_case=="constant":h=0.3;bed=0.2;u=Vector2(0.4,-0.2)
			elif probe_case=="thin":h=0.003;bed=0.2;u=Vector2(0.6,-0.3)
			elif index==0:h=0;u=Vector2.ZERO
			if probe_case=="thin" and index==0:h=0.0005;u=Vector2.ZERO
			numerical=numerical and absf(point.bed-bed)<0.000002 and absf(point.h-h)<0.000002 and absf(point.eta-(bed+h))<0.000002 and point.u_xz.distance_to(u)<0.00002
		check("hand_calculated_linear_center_edge_dry",numerical)
		check("all64_chunk_versions_initial_zero",receipt.footprint_versions.size()==64 and receipt.footprint_versions.values().all(func(v):return v==0))
		check("all64_change_bounds_initial_zero",receipt.footprint_change_bounds.size()==64 and receipt.footprint_change_bounds.values().all(func(v):return v==0.0))
		var malformed: PackedByteArray=receipt.raw.duplicate();malformed.resize(64)
		check("truncated_receipt_rejected",ProbeCodec.decode(malformed,value,pipeline.views.probe.serial).error==&"readback_failed")
		malformed=receipt.raw.duplicate();malformed.encode_s64(8,probe_id+1)
		check("foreign_request_rejected",not ProbeCodec.decode(malformed,value,pipeline.views.probe.serial).error.is_empty())
		malformed=receipt.raw.duplicate();malformed.encode_float(128+28,NAN)
		check("nan_receipt_rejected",not ProbeCodec.decode(malformed,value,pipeline.views.probe.serial).error.is_empty())
		malformed=receipt.raw.duplicate();malformed.encode_u32(0,2)
		check("old_ABI_semantics_rejected",not ProbeCodec.decode(malformed,value,pipeline.views.probe.serial).error.is_empty())
		malformed=receipt.raw.duplicate();malformed.encode_float(2176+4,NAN)
		check("nan_change_bound_rejected",not ProbeCodec.decode(malformed,value,pipeline.views.probe.serial).error.is_empty())
		malformed=receipt.raw.duplicate();malformed.encode_float(2176+4,-1.0)
		check("negative_change_bound_rejected",not ProbeCodec.decode(malformed,value,pipeline.views.probe.serial).error.is_empty())
		malformed=receipt.raw.duplicate();malformed.encode_float(2176+4,INF)
		var unknown_bound:=ProbeCodec.decode(malformed,value,pipeline.views.probe.serial)
		check("saturated_change_bound_is_unknown",unknown_bound.error.is_empty() and unknown_bound.footprint_change_bounds[0]==-1.0)
	check("duplicate_request_id_rejected",pipeline.views.request_probe(value,_received).error==&"invalid_request")
	remaining=6;RenderingServer.call_on_render_thread(_read_render)
	deadline=Time.get_ticks_msec()+10000
	while remaining>0 and Time.get_ticks_msec()<deadline:await process_frame
	check("pure_probe_leaves_raw_authority_unchanged",remaining==0 and fields.sand==domain.sand.to_byte_array() and fields.water==domain.water.to_byte_array() and fields.qx==qx.to_byte_array() and fields.sand_spare==fields.sand and fields.published==fields.sand)
	for field in fields:FileAccess.open(output.get_base_dir()+"/pure_probe_"+String(field)+".bin",FileAccess.WRITE).store_buffer(fields[field])
	var invalid:=value.duplicate(true);invalid.points.append(invalid.points[0])
	check("over_capacity_rejected",pipeline.views.request_probe(invalid,_received).error==&"invalid_request")
	invalid=value.duplicate(true);invalid.generation+=1
	check("wrong_generation_rejected",pipeline.views.request_probe(invalid,_received).error==&"stale_generation")
	invalid=value.duplicate(true);invalid.points[2].position.x=16.0
	check("outside_domain_rejected",pipeline.views.request_probe(invalid,_received).error==&"out_of_domain")
	invalid=value.duplicate(true);invalid.points[2].position.x=NAN
	check("nan_request_rejected",pipeline.views.request_probe(invalid,_received).error==&"invalid_request")
	invalid=_request();invalid.points[2].point_id=invalid.points[1].point_id
	check("duplicate_point_identity_rejected",pipeline.views.request_probe(invalid,_received).error==&"invalid_request")
	value=_request();value.minimum_state_seq=1
	await _query("future_minimum",value,&"stale_sample")
	# Readback registration failure retains the existing output; producer advances.
	var probe=pipeline.views.probe;probe.inject_readback_failure_once=true
	value=_request();var before:=callback_count
	check("unknown_accepted",pipeline.views.request_probe(value,_received).accepted)
	deadline=Time.get_ticks_msec()+10000
	while not probe.unknown and Time.get_ticks_msec()<deadline:await process_frame
	check("unknown_owns_reader",probe.pending and probe.unknown and not pipeline.views.can_release())
	check("water_admitted_with_probe_unknown",pipeline.request_tick(0.001).is_empty());await await_idle()
	var command:=request(1,&"fill_v1",Vector2(0.0625,0.0625),0.01)
	check("edit_admitted_with_probe_unknown",pipeline.submit_intent(command).accepted);await await_idle()
	check("water_and_edit_completed_independently",pipeline.completed_tick==1 and pipeline.completed_state_seq>=2 and probe.pending)
	pipeline.views.retry_preview_readback();await _wait_receipt(before);_save("retry_original",value)
	check("retry_did_not_resubmit_gpu_query",receipt.error.is_empty() and receipt.captured_state_seq==0 and receipt.captured_time_s==0.0)
	value=_request();await _query("after_production",value)
	check("captured_actual_complete_clock",receipt.error.is_empty() and receipt.captured_state_seq==pipeline.completed_state_seq and absf(receipt.captured_time_s-pipeline.advanced_time_s)<1e-8 and receipt.captured_tick==pipeline.completed_tick)
	check("relevant_chunk_versions_not_global_seq",receipt.error.is_empty() and receipt.footprint_versions.values().has(0) and receipt.footprint_versions.values().has(pipeline.completed_state_seq))
	check("real_edit_advances_change_bounds",receipt.error.is_empty() and receipt.footprint_change_bounds.values().any(func(v):return v>0.0))
	# A pending probe leaves the separate mouse preview channel available.
	probe.hold_delivery=true;before=callback_count;value=_request()
	check("held_accepted",pipeline.views.request_probe(value,_received).accepted)
	deadline=Time.get_ticks_msec()+10000
	while probe.held.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	var held_serial: int=probe.serial;var held_bytes: PackedByteArray=probe.held.get("bytes",PackedByteArray()).duplicate()
	check("probe_busy",pipeline.views.request_probe(value,_received).error==&"probe_busy")
	var preview:={"done":false,"error":&"missing"}
	check("preview_independent_admission",pipeline.views.request_preview(command,func(r):preview.done=true;preview.error=r.error).accepted)
	deadline=Time.get_ticks_msec()+10000
	while not preview.done and Time.get_ticks_msec()<deadline:await process_frame
	check("preview_completed_during_probe_hold",preview.done and preview.error.is_empty() and probe.pending)
	check("advance_pose_context",probe.set_context(value.owner_token,2).is_empty())
	probe.deliver_held();await _wait_receipt(before);_save("stale_pose",value)
	check("stale_pose_reported",receipt.error==&"stale_pose")
	probe._received(held_bytes,held_serial)
	check("duplicate_callback_ignored",callback_count==before+1)
	value=_request();value.pose_seq=2;value.owner_token+=1
	probe.hold_delivery=true;before=callback_count
	check("old_owner_inflight",pipeline.views.request_probe(value,_received).accepted)
	deadline=Time.get_ticks_msec()+10000
	while probe.held.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	probe.set_context(value.owner_token+1,1);probe.deliver_held();await _wait_receipt(before)
	check("stale_owner_reported",receipt.error==&"stale_owner")
	value=_request();value.owner_token+=2
	probe.inject_upload_failure_once=true
	await _query("upload_failed",value,&"readback_failed")
	check("unrecorded_failure_reclaims",not probe.pending and not receipt.recorded)
	value=_request();value.owner_token+=2
	probe.hold_delivery=true;before=callback_count
	check("close_with_inflight",pipeline.views.request_probe(value,_received).accepted)
	deadline=Time.get_ticks_msec()+10000
	while probe.held.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	pipeline.close_admission()
	check("close_does_not_drop_reader",not pipeline.views.can_release())
	probe.deliver_held();await _wait_receipt(before)
	check("closing_terminal",receipt.error==&"closing" and probe.completed_count==probe.accepted_count)
	check("closing_rejects_admission",pipeline.views.request_probe(value,_received).error==&"closing")
	check("readers_releasable",pipeline.views.can_release())
	await await_idle();RenderingServer.call_on_render_thread(pipeline.release_render)
	deadline=Time.get_ticks_msec()+15000
	while not pipeline.released and Time.get_ticks_msec()<deadline:await process_frame
	check("all_resources_released",pipeline.released and pipeline.ownership_counts().values().all(func(v):return v==0))
	finish()

func finish() -> void:
	var evidence:={"pass":not failed,"case":probe_case,"checks":checks,"receipts":receipts,"sources":source_hashes,"engine":Engine.get_version_info(),"hardware":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name(),"output_size":DisplayServer.window_get_size(),"physics_engine":ProjectSettings.get_setting("physics/3d/physics_engine"),"scope":"G1 public raw sample and reader ownership only; no Jolt clock or props behavior claim"}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(evidence,"\t"));quit(1 if failed else 0)
