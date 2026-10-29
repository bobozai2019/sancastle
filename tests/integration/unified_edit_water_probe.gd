extends "res://tests/integration/unified_edit_suspended_probe.gd"
const OriginalResponse=preload("res://tests/integration/unified_edit_legacy_response_reference.gd")
var response_reference
var response_reference_bytes: Dictionary={}
var response_reference_ready:=false
var response_reference_error:=""
const PROFILE_ORDER=[&"dig_v1",&"fill_v1",&"dig_sweep_v1",&"fill_sweep_v1",&"suspended_v1",&"suspended_sweep_v1",&"smooth_v1",&"compact_v1",&"castle_v1",&"wall_v1",&"shovel_v1"]

func _additional_sources() -> PackedStringArray:return PackedStringArray(OriginalResponse.SOURCES)

func _extra_image_fields() -> Dictionary:
	var images:=super._extra_image_fields();images.published_water=pipeline.state.published_water;return images

func _extra_buffer_fields() -> Dictionary:
	var b: Dictionary=pipeline.executor.response.buffers
	return {"water_input":[b.input,65536*32],"water_candidate":[b.candidate,65536*16],"water_receipt":[b.receipt,128],"water_scratch":[b.scratch,65536*20],"water_indirect":[b.indirect,36],"decision":[pipeline.executor.buffers.decision,128],"summary":[pipeline.executor.buffers.summary,L.SUMMARY_BUFFER_BYTES]}

func _configure_domain() -> void:
	domain.water.fill(0.15);domain.obstacle.fill(0.0)
	var qx:=PackedFloat32Array();qx.resize(65536);qx.fill(0.03)
	var qz:=PackedFloat32Array();qz.resize(65536);qz.fill(0.01)
	if "cfl" in probe_case:qx.fill(15.0)
	if "split" in probe_case:
		for z in 256:domain.obstacle[z*256+128]=1.0
	if "partial" in probe_case:
		for z in 256:
			for x in 256:
				if x<124:domain.water[z*256+x]=0.0;qx[z*256+x]=0.0;qz[z*256+x]=0.0
	if "limited" in probe_case:qx.fill(0.585)
	if "capacity" in probe_case or "sealed" in probe_case or "dry" in probe_case or "many" in probe_case:
		domain.water.fill(0.0);domain.sediment.fill(0.0);qx.fill(0.0);qz.fill(0.0)
		for z in 256:
			for x in 256:
				var wet: bool=(x in range(120,136) and z in range(120,136)) if "capacity" in probe_case else ((x==126 and z==128) if "sealed" in probe_case else (x%4<2 if "many" in probe_case else false))
				if wet:domain.water[z*256+x]=0.15;domain.sediment[z*256+x]=0.03
	if "plain" in probe_case:
		var tags:=PackedFloat32Array();tags.resize(65536);domain.set_meta("brush_initial_mold_depth",tags)
	domain.set_meta("edit_validation_initial_qx",qx);domain.set_meta("edit_validation_initial_qz",qz)

func suspended() -> void:
	if probe_case.begins_with("all_profiles"):await all_profiles();return
	var policy:=int(probe_case.get_slice("_",probe_case.get_slice_count("_")-1))
	var kind:=probe_case.get_slice("_",1)
	if kind=="overflow":await water_overflow();return
	var rejected:=kind in ["fail","cfl"]
	var material_invalid:=kind in ["materialbad","refbad","nan"]
	if material_invalid:
		armed_snapshot=false;RenderingServer.call_on_render_thread(_inject_bad_response_input.bind(kind))
		while not armed_snapshot:await process_frame
	if kind=="fail":
		armed_snapshot=false;RenderingServer.call_on_render_thread(_arm_response_loss_render)
		while not armed_snapshot:await process_frame
	var result: Dictionary={}
	if kind in ["wall","shovel","castle","moldplain"]:
		expect("begin",await perform("begin",control_identity(),"begin"),L.Outcome.NO_CHANGE)
		var profile: StringName={"wall":&"wall_v1","shovel":&"shovel_v1","castle":&"castle_v1","moldplain":&"castle_v1"}[kind]
		var command:=shape_request(profile,Vector2.ZERO,Vector2.ZERO if kind in ["castle","moldplain"] else Vector2(1,0),1,{},1,11,2 if kind=="shovel" else (0 if kind=="moldplain" else 1))
		command.features.water_policy=policy
		result=await perform("response",command)
		expect("end",await perform("end",control_identity(),"end"),L.Outcome.NO_CHANGE)
	else:
		var command:=request(1,&"dig_v1" if kind=="dig" else &"fill_v1",Vector2(-0.25,0))
		command.features.water_policy=policy
		command.parameters.speed_m_s=0.6 if policy==3 else 0.0
		if kind=="only":command.parameters.strength=1e-20
		result=await perform("response",command)
	expect("response",result,L.Outcome.REJECTED if rejected or material_invalid else L.Outcome.APPLIED,(L.ErrorCode.WATER_CANDIDATE_INVALID if kind=="nan" else L.ErrorCode.CANDIDATE_INVALID) if material_invalid else (L.ErrorCode.WATER_CANDIDATE_INVALID if rejected else 0))
	if not rejected and not material_invalid:check("response_declares_water_capability",not result.is_empty() and (result.changed_fields&L.Profile.WATER)!=0 if policy!=2 and kind not in ["dig","dry","sealed","only"] else true)
	if rejected:
		var successor:=local_request(&"compact_v1",Vector2(3,0));successor.command_id=2
		expect("successor",await perform("successor",successor),L.Outcome.APPLIED)
		observations.expected_water_failure=kind
	if material_invalid:observations.expected_input_failure=kind
	if kind=="only":check("only_momentum_changes",result.changed_fields==L.Profile.MOMENTUM and result.added_m3==0.0 and result.removed_m3==0.0)
	if kind in ["capacity","sealed"]:check("capacity_retains_water",result.retained_water_m3>0.0)
	observations.traces=pipeline.executor.traces.duplicate(true)
	for item in cases:
		for field in ["sediment0","sediment1"]:check(item.label+"_candidate_precommit_"+field,item.before[field].sha256==item.after["pre_"+field].sha256)
		if item.label=="response" and kind in ["plain","moldplain"]:check("plain_keeps_material",item.before.support0.sha256==item.after.support0.sha256 and item.before.compact0.sha256==item.after.compact0.sha256)
		if item.label=="response" and not rejected and not material_invalid:await compare_response(item)
	if kind=="many":check("topology_falls_back",FileAccess.get_file_as_bytes(cases[0].after.water_receipt.path).decode_u32(27*4)==0)
	if kind=="limited":check("velocity_limit_really_applied",FileAccess.get_file_as_bytes(cases[0].after.water_receipt.path).decode_u32(21*4)>0)

func _inject_bad_response_input(kind: String) -> void:
	var data:=PackedByteArray()
	if kind=="nan":
		data.resize(65536*4)
		for index in 65536:data.encode_float(index*4,0.15)
		data.encode_float((128*256+220)*4,NAN)
		var source: RID=pipeline.state._create_texture(RenderingDevice.DATA_FORMAT_R32_SFLOAT,data)
		for target in pipeline.state.textures.water:pipeline.transport.rd.texture_copy(source,target,Vector3.ZERO,Vector3.ZERO,Vector3(256,256,1),0,0,0,0)
	else:
		data.resize(65536*8)
		for index in 65536:data.encode_float(index*8,0.0875);data.encode_float(index*8+4,0.25)
		data.encode_float((128*256+128)*8,0.3 if kind=="materialbad" else 0.1);data.encode_float((128*256+128)*8+4,0.25 if kind=="materialbad" else 0.5)
		var source: RID=pipeline.state._create_texture(RenderingDevice.DATA_FORMAT_R32G32_SFLOAT,data)
		for target in pipeline.state.textures.mold_support:pipeline.transport.rd.texture_copy(source,target,Vector3.ZERO,Vector3.ZERO,Vector3(256,256,1),0,0,0,0)
	call_deferred("_snapshot_armed")

func _arm_overflow_render() -> void:
	pipeline.transport.rd.buffer_update(pipeline.transport.control,40,8,PackedInt64Array([9223372036854775807]).to_byte_array());call_deferred("_snapshot_armed")

func water_overflow() -> void:
	armed_snapshot=false;RenderingServer.call_on_render_thread(_arm_overflow_render)
	while not armed_snapshot:await process_frame
	var before:=await snapshot("overflow_before")
	var command:=request(1,&"fill_v1",Vector2(-0.25,0));command.features.water_policy=3;command.parameters.strength=1e-20;command.parameters.speed_m_s=0.6
	check("overflow_admitted",pipeline.submit_intent(command).accepted);pipeline.pump()
	var begin:=Time.get_ticks_msec()
	while pipeline.fault_reason().is_empty() and Time.get_ticks_msec()-begin<10000:await process_frame
	check("water_only_overflow_fatal",not pipeline.fault_reason().is_empty() and pipeline.result(1).is_empty())
	var after:=await snapshot("overflow_after")
	for key in ["sand0","sand1","water","water1","sediment0","sediment1","qx0","qx1","qz0","qz1","support0","support1","compact0","compact1","baseline","coverage"]:check("overflow_no_commit_"+key,before[key].sha256==after[key].sha256)
	observations.overflow={"before":before,"after":after}
	pipeline.cleanup_fault();begin=Time.get_ticks_msec()
	while pipeline.active_count()>0 and Time.get_ticks_msec()-begin<10000:await process_frame
	check("overflow_terminal_proof",pipeline.active_count()==0 and not pipeline.transport.has_owned() and pipeline.executor.recorded_commands==1)

func _arm_response_loss_render() -> void:
	pipeline.executor.response.inject_water_loss_once=true;call_deferred("_snapshot_armed")

func compare_response(item: Dictionary) -> void:
	response_reference_ready=false;response_reference_bytes={};response_reference_error=""
	RenderingServer.call_on_render_thread(_response_reference_render.bind(item))
	var begin:=Time.get_ticks_msec()
	while not response_reference_ready and Time.get_ticks_msec()-begin<20000:await process_frame
	check("original_response_ready",response_reference_ready and response_reference_error.is_empty() and response_reference_bytes.size()==2)
	var index:={}
	for key in response_reference_bytes:
		var path: String=output.get_base_dir()+"/"+String(item.label)+"_original_"+String(key)+".bin"
		FileAccess.open(path,FileAccess.WRITE).store_buffer(response_reference_bytes[key]);index[key]={"path":path,"bytes":response_reference_bytes[key].size(),"sha256":FileAccess.get_sha256(path)}
		var actual:=FileAccess.get_file_as_bytes(item.after["water_"+String(key)].path)
		var expected: PackedByteArray=response_reference_bytes[key]
		if key=="candidate":
			var valid:=true;var exact_depths:=true;var max_error:=0.0
			for cell in 65536:
				for component in 4:
					var at:=cell*16+component*4;var a:=actual.decode_float(at);var b:=expected.decode_float(at)
					if component<2:exact_depths=exact_depths and actual.decode_u32(at)==expected.decode_u32(at)
					else:valid=valid and absf(a-b)<=preload("res://scripts/simulation/edit_validation/edit_protocol.gd").cell_budget(b,a)
					max_error=maxf(max_error,absf(a-b))
			check("original_exact_depths",exact_depths);check("original_frozen_velocity_budget",valid)
			item.original_max_error=max_error
		else:
			var valid:=true
			for word in 32:
				if word in [17,18,19,20,22,23,24,30]:continue
				valid=valid and actual.decode_u32(word*4)==expected.decode_u32(word*4)
			check("original_nonvelocity_receipt_exact",valid)
	item.original_response=index
	response_reference_ready=false;RenderingServer.call_on_render_thread(_release_response_reference_render)
	while not response_reference_ready:await process_frame

func _response_reference_render(item: Dictionary) -> void:
	response_reference=OriginalResponse.new()
	if not response_reference.initialize(pipeline.transport.rd,FileAccess.get_file_as_bytes(item.after.water_input.path),FileAccess.get_file_as_bytes(item.after.cells.path),item.wire):call_deferred("_response_reference_failed",response_reference.last_error);return
	response_reference.record(item.wire)
	for pair in [["candidate",65536*16],["receipt",128]]:
		if pipeline.transport.rd.buffer_get_data_async(response_reference.buffers[pair[0]],_response_reference_read.bind(pair[0]),0,pair[1])!=OK:call_deferred("_response_reference_failed","response_reference_read")
func _response_reference_read(data: PackedByteArray, key: String) -> void:call_deferred("_response_reference_field",data,key)
func _response_reference_field(data: PackedByteArray, key: String) -> void:
	response_reference_bytes[key]=data
	if response_reference_bytes.size()==2:response_reference_ready=true
func _response_reference_failed(reason: String) -> void:response_reference_error=reason;response_reference_ready=true
func _release_response_reference_render() -> void:response_reference.release();call_deferred("_response_reference_released")
func _response_reference_released() -> void:response_reference_ready=true

func _profile_program() -> Array:
	var program: Array=[]
	for profile_id in PROFILE_ORDER:
		var profile: Dictionary=registry.profile(profile_id);var identity:={}
		if profile.stroke_policy!=0:
			identity=control_identity(program.size()+1,program.size()+101)
			program.append({"label":"begin_"+String(profile_id),"mode":"begin","command":identity})
		serial+=1
		var command:={"domain_id":"main_beach","generation":9007199254740993,"command_id":serial,"sim_tick":0,"profile_id":profile_id,"profile_version":profile.version,"profile_hash":profile.profile_hash,"start_xz_m":Vector2.ZERO}
		if profile.shape==1:command.end_xz_m=Vector2(1,0)
		if profile.stroke_policy!=0:
			for key in ["stroke_id","baseline_token"]:command[key]=identity[key]
			command.sample_index=1
		program.append({"label":String(profile_id),"mode":"","command":command})
		if profile.stroke_policy!=0:program.append({"label":"end_"+String(profile_id),"mode":"end","command":control_identity(program.size()-1,program.size()+99)})
	return program

func all_profiles() -> void:
	var program:=_profile_program()
	# END must carry the BEGIN identity, independent of how many records a
	# profile emits. Keep the public int64 identity rather than recalculate it.
	var active:={}
	for item in program:
		if item.mode=="begin":active=item.command
		if item.mode=="end":
			for key in ["stroke_id","baseline_token"]:item.command[key]=active[key]
	observations.program=program
	if probe_case=="all_profiles_batch":
		observations.initial=await snapshot("joint_initial")
		for item in program:
			var admission: Dictionary=pipeline.submit_intent(item.command) if item.mode.is_empty() else pipeline.submit_control(item.mode,item.command)
			check("joint_admission_"+item.label,admission.accepted)
		pipeline.hold_completions=true;pipeline.pump()
		observations.recorded_before_consumption={"active":pipeline.active_count(),"pending":pipeline.pending_count(),"results":pipeline._results.size()}
		check("joint_records_before_cpu_consumption",pipeline.active_count()>0 and pipeline._results.is_empty())
		pipeline.hold_completions=false;await await_idle()
		for item in program:
			var value:=pipeline.result(item.command.command_id)
			check("joint_terminal_"+item.label,not value.is_empty() and value.outcome in [L.Outcome.APPLIED,L.Outcome.NO_CHANGE] and value.error_code==0)
	else:
		for item in program:
			var value:=await perform(item.label,item.command,item.mode)
			check("joint_terminal_"+item.label,not value.is_empty() and value.outcome in [L.Outcome.APPLIED,L.Outcome.NO_CHANGE] and value.error_code==0)
			cases[-1].trace=pipeline.executor.traces[-1].duplicate(true)
			if item.mode.is_empty():
				var profile: Dictionary=registry.profile(item.command.profile_id);var wire: Dictionary=cases[-1].wire
				check("joint_default_water_"+item.label,wire.water_policy==profile.water_policy)
				check("joint_default_material_"+item.label,wire.material_policy==profile.material_policy)
				for key in profile.defaults:check("joint_default_"+item.label+"_"+String(key),PackedFloat32Array([wire[key]])==PackedFloat32Array([profile.defaults[key]]))
				if wire.water_policy>0:await compare_response(cases[-1])
	observations.final=await snapshot("joint_final")
	observations.traces=pipeline.executor.traces.duplicate(true)
	observations.terminal_results=pipeline._results.duplicate(true)
