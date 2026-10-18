extends "res://tests/integration/unified_edit_gpu_probe.gd"

const Observed=preload("res://tests/integration/unified_edit_observed_executor.gd")
const Wire=preload("res://scripts/simulation/unified_edit/protocol.gd")
var cases: Array=[]
var serial:=0
var armed_snapshot:=false
var snapshots_serial:=0
var observations: Dictionary={}
var legacy_local
var legacy_local_images: Dictionary={}
var legacy_local_buffers: Dictionary={}
var legacy_local_sets: Array[RID]=[]
var legacy_local_finished:=false
var legacy_local_bytes: Dictionary={}

func shape_request(profile_id: StringName, a: Vector2, b: Vector2, sample: int, overrides: Dictionary={}, stroke: int=1, token: int=11, material: int=1, authorization: Dictionary={}) -> Dictionary:
	serial+=1
	var profile: Dictionary=registry.profile(profile_id)
	return {"domain_id":"main_beach","generation":9007199254740993,"command_id":serial,"sim_tick":0,"profile_id":profile_id,"profile_version":profile.version,"profile_hash":profile.profile_hash,"start_xz_m":a,"end_xz_m":b,"parameters":overrides,"features":{"water_policy":0,"material_policy":material},"stroke_id":9007199254740993+stroke,"baseline_token":9007199254741993+token,"sample_index":sample,"authorization":authorization}

func control_identity(stroke: int=1, token: int=11) -> Dictionary:
	serial+=1
	return {"domain_id":"main_beach","generation":9007199254740993,"command_id":serial,"sim_tick":0,"stroke_id":9007199254740993+stroke,"baseline_token":9007199254741993+token}

func local_request(profile_id: StringName, point: Vector2=Vector2.ZERO, parameters: Dictionary={}) -> Dictionary:
	serial+=1
	var profile: Dictionary=registry.profile(profile_id)
	return {"domain_id":"main_beach","generation":9007199254740993,"command_id":serial,"sim_tick":0,"profile_id":profile_id,"profile_version":profile.version,"profile_hash":profile.profile_hash,"start_xz_m":point,"parameters":parameters,"features":{"water_policy":0,"material_policy":2}}

func _arm_snapshot_render() -> void:
	pipeline.executor.clear_snapshots();pipeline.executor.snapshot_armed=true;call_deferred("_snapshot_armed")
func _snapshot_armed() -> void:armed_snapshot=true

func _read_all_render() -> void:
	var images:={"rock":pipeline.state.textures.rock,"sand0":pipeline.state.textures.sand[0],"sand1":pipeline.state.textures.sand[1],"water":pipeline.state.textures.water[0],"obstacle":pipeline.state.textures.obstacle,"support0":pipeline.state.textures.mold_support[0],"support1":pipeline.state.textures.mold_support[1],"compact0":pipeline.state.textures.compaction[0],"compact1":pipeline.state.textures.compaction[1],"published":pipeline.state.published_sand,"baseline":pipeline.executor.images.baseline,"coverage":pipeline.executor.images.coverage,"candidate_coverage":pipeline.executor.images.candidate_coverage}
	images.merge(pipeline.executor.snapshots)
	images.merge(_extra_image_fields())
	for key in images:
		if pipeline.transport.rd.texture_get_data_async(images[key],0,_field_render.bind(key))!=OK:call_deferred("_read_failed",key)
	for pair in [["stroke",pipeline.executor.buffers.stroke,64],["cells",pipeline.executor.buffers.cells,65536*L.CELL_BYTES],["control",pipeline.transport.control,L.CONTROL_BYTES]]:
		if pipeline.transport.rd.buffer_get_data_async(pair[1],_field_render.bind(pair[0]),0,pair[2])!=OK:call_deferred("_read_failed",pair[0])
	for key in _extra_buffer_fields():
		var pair: Array=_extra_buffer_fields()[key]
		if pipeline.transport.rd.buffer_get_data_async(pair[0],_field_render.bind(key),0,pair[1])!=OK:call_deferred("_read_failed",key)
	if probe_case.begins_with("transfer"):
		for pair in [["transfer_state",128],["transfer_prefix",65536*32]]:
			if pipeline.transport.rd.buffer_get_data_async(pipeline.executor.buffers[pair[0]],_field_render.bind(pair[0]),0,pair[1])!=OK:call_deferred("_read_failed",pair[0])

func _extra_image_fields() -> Dictionary:return {}
func _extra_buffer_fields() -> Dictionary:return {}

func snapshot(label: String) -> Dictionary:
	fields={};remaining=16+pipeline.executor.snapshots.size()+(2 if probe_case.begins_with("transfer") else 0)+_extra_image_fields().size()+_extra_buffer_fields().size()
	RenderingServer.call_on_render_thread(_read_all_render)
	var begin:=Time.get_ticks_msec()
	while remaining>0 and Time.get_ticks_msec()-begin<10000:await process_frame
	check("read_"+label,remaining==0)
	var index:={}
	for field in fields:
		var path: String=output.get_base_dir()+"/"+label+"_"+String(field)+".bin"
		FileAccess.open(path,FileAccess.WRITE).store_buffer(fields[field])
		index[field]={"path":path,"bytes":fields[field].size(),"sha256":FileAccess.get_sha256(path)}
	return index

func perform(label: String, command: Dictionary, mode: String="") -> Dictionary:
	var before:=await snapshot(label+"_before")
	var wire: Dictionary={}
	if mode.is_empty():
		var frozen:=preload("res://scripts/simulation/unified_edit/intent.gd").freeze(registry,command,"main_beach",9007199254740993)
		if not frozen.error.is_empty():check("wire_"+label+"_"+String(frozen.error),false);return {}
		wire=Wire.decode_command(Wire.encode_command(frozen.value,registry)).value
		if wire.operation==L.Profile.Operation.FIELD_ADJUST:
			legacy_local_finished=false;legacy_local_bytes={}
			RenderingServer.call_on_render_thread(_legacy_compact_render.bind(wire))
			while not legacy_local_finished:await process_frame
			for key in legacy_local_bytes:
				var path: String=output.get_base_dir()+"/"+label+"_"+key+".bin"
				FileAccess.open(path,FileAccess.WRITE).store_buffer(legacy_local_bytes[key])
				before[key]={"path":path,"bytes":legacy_local_bytes[key].size(),"sha256":FileAccess.get_sha256(path)}
	armed_snapshot=false;RenderingServer.call_on_render_thread(_arm_snapshot_render)
	while not armed_snapshot:await process_frame
	var admitted: Dictionary=pipeline.submit_intent(command) if mode.is_empty() else pipeline.submit_control(mode,command)
	check("admission_"+label,admitted.accepted)
	if not admitted.accepted:print(admitted);return {}
	await await_idle()
	if not pipeline.fault_reason().is_empty():return {}
	var result:=pipeline.result(command.command_id)
	var after:=await snapshot(label+"_after")
	for key in ["sand0","sand1","support0","support1","compact0","compact1","baseline","coverage"]:check("candidate_did_not_commit_"+label+"_"+key,before[key].sha256==after["pre_"+key].sha256)
	cases.append({"label":label,"mode":mode,"command":command,"wire":wire,"result":result,"before":before,"after":after})
	return result

# Isolated retained-kernel reference. It only sees copies of the input fields;
# no reference output is fed to admission, candidate validation or commit.
func _legacy_compact_render(wire: Dictionary) -> void:
	var rd: RenderingDevice=pipeline.transport.rd
	if legacy_local==null:
		legacy_local=preload("res://scripts/simulation/unified_edit/gpu.gd").new();legacy_local.rd=rd
		if not legacy_local.compile("legacy","res://scripts/simulation/edit_validation/frame_pipeline/async_smooth.glsl"):
			call_deferred("_legacy_local_error",legacy_local.last_error);return
		for pair in [["command",512],["receipt",128],["cells",65536*64],["control",16]]:
			var data:=PackedByteArray();data.resize(pair[1]);legacy_local_buffers[pair[0]]=legacy_local.own(rd.storage_buffer_create(pair[1],data))
		for pair in [["sand0",RenderingDevice.DATA_FORMAT_R32_SFLOAT],["sand1",RenderingDevice.DATA_FORMAT_R32_SFLOAT],["compact0",RenderingDevice.DATA_FORMAT_R16_SFLOAT],["compact1",RenderingDevice.DATA_FORMAT_R16_SFLOAT],["support0",RenderingDevice.DATA_FORMAT_R32G32_SFLOAT],["support1",RenderingDevice.DATA_FORMAT_R32G32_SFLOAT]]:
			legacy_local_images[pair[0]]=pipeline.state._create_texture(pair[1],PackedByteArray())
		legacy_local_sets.append(legacy_local.binding("legacy",{0:legacy_local_buffers.command,1:legacy_local_buffers.receipt,2:legacy_local_buffers.cells,3:legacy_local_buffers.control}))
		legacy_local_sets.append(legacy_local.binding("legacy",{},{0:legacy_local_images.sand0,1:legacy_local_images.sand1,2:legacy_local_images.compact0,3:legacy_local_images.compact1,4:legacy_local_images.support0,5:legacy_local_images.support1},1))
	var command:=PackedByteArray();command.resize(512)
	for pair in [[24,wire.start_x],[25,wire.start_z],[26,wire.start_x],[27,wire.start_z],[28,wire.radius_m],[29,wire.strength]]:command.encode_float(pair[0]*4,pair[1])
	for pair in [[32,wire.rect_x],[33,wire.rect_z],[34,wire.rect_x+wire.rect_w-1],[35,wire.rect_z+wire.rect_h-1]]:command.encode_u32(pair[0]*4,pair[1])
	var receipt:=PackedByteArray();receipt.resize(128);receipt.encode_u32(12,1)
	rd.buffer_update(legacy_local_buffers.command,0,512,command);rd.buffer_update(legacy_local_buffers.receipt,0,128,receipt)
	for pair in [["sand0",pipeline.state.textures.sand[0]],["sand1",pipeline.state.textures.sand[1]],["compact0",pipeline.state.textures.compaction[0]],["compact1",pipeline.state.textures.compaction[1]],["support0",pipeline.state.textures.mold_support[0]],["support1",pipeline.state.textures.mold_support[1]]]:
		rd.texture_copy(pair[1],legacy_local_images[pair[0]],Vector3.ZERO,Vector3.ZERO,Vector3(256,256,1),0,0,0,0)
	for phase in 2:
		var list:=rd.compute_list_begin();rd.compute_list_bind_compute_pipeline(list,legacy_local.kernels.legacy.pipeline)
		for set_index in 2:rd.compute_list_bind_uniform_set(list,legacy_local_sets[set_index],set_index)
		var push:=PackedInt32Array([4,phase,0,0]).to_byte_array();rd.compute_list_set_push_constant(list,push,16)
		rd.compute_list_dispatch(list,1 if phase==0 else wire.rect_w,1 if phase==0 else wire.rect_h,1);rd.compute_list_end()
	if rd.texture_get_data_async(legacy_local_images.compact0,0,_legacy_local_read.bind("legacy_compact"))!=OK:call_deferred("_legacy_local_error","legacy_texture_read")
	if rd.buffer_get_data_async(legacy_local_buffers.cells,_legacy_local_read.bind("legacy_cells"),0,65536*64)!=OK:call_deferred("_legacy_local_error","legacy_buffer_read")

func _legacy_local_read(data: PackedByteArray, key: String) -> void:call_deferred("_legacy_local_field",data,key)
func _legacy_local_field(data: PackedByteArray, key: String) -> void:
	legacy_local_bytes[key]=data
	if legacy_local_bytes.size()==2:legacy_local_finished=true
func _legacy_local_error(reason: String) -> void:
	check(reason,false);legacy_local_finished=true
func _release_legacy_local_render() -> void:
	if legacy_local!=null:legacy_local.release()

func expect(label: String, result: Dictionary, outcome: int, error: int=0) -> void:
	check(label,not result.is_empty() and result.outcome==outcome and result.error_code==error)

func _run() -> void:
	started=Time.get_ticks_msec();pipeline.executor=Observed.new()
	DisplayServer.window_set_size(Vector2i(1280,720));DisplayServer.window_set_title("Unified target candidate probe")
	var catalog=load("res://assets/unified_edit/default_catalog.tres")
	var resources: Array=Array(catalog.profiles)
	if probe_case=="stroke_bounds":resources.append(load("res://tests/fixtures/unified_edit/wall_small_buffer.tres"))
	registry=preload("res://scripts/simulation/unified_edit/profile_registry.gd").new()
	var registry_error: StringName=registry.initialize(resources)
	check("registry",registry_error.is_empty())
	if not registry_error.is_empty():print(registry_error);finish();return
	var simulation:={"enable_erosion":false,"enable_brush_water":true,"unrestricted_sand_tools":true,"enable_structures":false,"local_front_history":false,"rise_front_history":false,"contact_history":false}
	var extras:=PackedStringArray(Pipeline.SOURCE_PATHS+Pipeline.ADAPTER_SOURCES)
	extras.append("res://tests/integration/unified_edit_observed_executor.gd")
	extras.append("res://scripts/simulation/edit_validation/frame_pipeline/async_smooth.glsl")
	var configuration:=Config.freeze(registry,"main_beach",simulation,{"foam_enabled":false,"gravel_enabled":false},{},{"engine":Engine.get_version_info().string,"probe":probe_case},extras)
	check("configuration",configuration.error.is_empty())
	if not configuration.error.is_empty():finish();return
	source_hashes=configuration.value.sources.duplicate(true)
	check("configure",pipeline.configure(registry,configuration.value,9007199254740993).is_empty())
	domain=Domain.new(256,0.125);domain.domain_id=&"main_beach";domain.generation=9007199254740993
	domain.sand.fill(0.2);domain.water.fill(0.0);domain.rock.fill(0.05)
	if probe_case in ["smooth","compact","local_mixed","local_invalid"] or probe_case.begins_with("transfer"):
		var tagged:=PackedFloat32Array();tagged.resize(65536)
		for z in 256:
			for x in 256:
				var i:=z*256+x
				domain.sand[i]=0.35+0.1*sin(float(x)*0.31)*cos(float(z)*0.27)+0.01*float(x%7)
				tagged[i]=domain.sand[i]*0.35
		domain.compaction.fill(0.25);domain.set_meta("brush_initial_mold_depth",tagged)
	if probe_case.begins_with("transfer"):
		for z in 256:
			for x in 256:domain.compaction[z*256+x]=0.2+0.1*float(x%5)
	if probe_case=="transfer_empty":
		domain.sand.fill(0.0)
		var empty_tag:=PackedFloat32Array();empty_tag.resize(65536);domain.set_meta("brush_initial_mold_depth",empty_tag)
	if probe_case in ["transfer_capacity","transfer_limited"]:
		for z in 256:
			for x in 256:
				# One entire shoulder is protected; a separate donor obstacle
				# tests atomic rejection away from the first footprint.
				var point:=(Vector2(x,z)+Vector2.ONE*0.5-Vector2.ONE*128.0)*0.125
				var near:=Vector2(clampf(point.x,0.0,1.0),0.0)
				if point.y<0.0 and point.distance_to(near)>=0.25:domain.obstacle[z*256+x]=1.0
		if probe_case=="transfer_capacity":domain.obstacle[128*256+160]=1.0
		else:domain.obstacle[123*256+128]=0.0
	if probe_case=="castle":
		for z in 256:
			for x in 256:
				domain.rock[z*256+x]=-0.2+float(z%13)*0.001
				if x>128:domain.sand[z*256+x]=1.1
				if x in range(123,126) and z in range(124,128):domain.obstacle[z*256+x]=1.0
	RenderingServer.call_on_render_thread(pipeline.initialize_render.bind(domain))
	while not pipeline.initialized and Time.get_ticks_msec()-started<20000:await process_frame
	check("gpu_initialized",pipeline.initialized and pipeline.fault_reason().is_empty())
	if not pipeline.fault_reason().is_empty():print(pipeline.fault_reason());finish();return
	if probe_case=="controls":await controls()
	elif probe_case=="castle":await castle()
	elif probe_case=="wall":await wall()
	elif probe_case=="stroke_bounds":await stroke_bounds()
	elif probe_case=="smooth":await smooth()
	elif probe_case=="compact":await compact()
	elif probe_case=="local_mixed":await local_mixed()
	elif probe_case=="local_invalid":await local_invalid()
	elif probe_case.begins_with("transfer"):await transfer()
	else:check("known_case",false)
	pipeline.close_admission();RenderingServer.call_on_render_thread(_release_legacy_local_render);RenderingServer.call_on_render_thread(pipeline.release_render)
	var end:=Time.get_ticks_msec()
	while not pipeline.released and Time.get_ticks_msec()-end<10000:await process_frame
	check("released",pipeline.released)
	finish()

func controls() -> void:
	expect("end_without_begin",await perform("end_without_begin",control_identity(),"end"),L.Outcome.REJECTED,L.ErrorCode.INVALID_BASELINE)
	expect("begin",await perform("begin",control_identity(),"begin"),L.Outcome.NO_CHANGE)
	expect("duplicate_begin",await perform("duplicate_begin",control_identity(2,12),"begin"),L.Outcome.REJECTED,L.ErrorCode.INVALID_BASELINE)
	expect("wrong_end",await perform("wrong_end",control_identity(2,12),"end"),L.Outcome.REJECTED,L.ErrorCode.INVALID_BASELINE)
	expect("wall_valid",await perform("wall_valid",shape_request(&"wall_v1",Vector2.ZERO,Vector2(1,0),1)),L.Outcome.APPLIED)
	expect("duplicate_sample",await perform("duplicate_sample",shape_request(&"wall_v1",Vector2.ZERO,Vector2(1,0),1)),L.Outcome.REJECTED,L.ErrorCode.INVALID_BASELINE)
	expect("repeat_wall",await perform("repeat_wall",shape_request(&"wall_v1",Vector2.ZERO,Vector2(1,0),2)),L.Outcome.NO_CHANGE)
	expect("end",await perform("end",control_identity(),"end"),L.Outcome.NO_CHANGE)
	expect("inactive_wall",await perform("inactive_wall",shape_request(&"wall_v1",Vector2.ZERO,Vector2(1,0),3)),L.Outcome.REJECTED,L.ErrorCode.INVALID_BASELINE)
	expect("new_begin",await perform("new_begin",control_identity(2,12),"begin"),L.Outcome.NO_CHANGE)
	expect("cancel",await perform("cancel",control_identity(2,12),"cancel"),L.Outcome.NO_CHANGE)
	expect("explicit_reopen_existing_identity",await perform("explicit_reopen_existing_identity",control_identity(2,12),"begin"),L.Outcome.NO_CHANGE)
	expect("close_reopened_identity",await perform("close_reopened_identity",control_identity(2,12),"end"),L.Outcome.NO_CHANGE)
	var begin:=control_identity(3,13);begin.sim_tick=2
	var draw:=shape_request(&"wall_v1",Vector2(-2,0),Vector2(-1,0),1,{},3,13)
	var end:=control_identity(3,13)
	check("future_begin_admitted",pipeline.submit_control("begin",begin).accepted)
	check("draw_after_future_begin_admitted",pipeline.submit_intent(draw).accepted)
	check("end_barrier_admitted",pipeline.submit_control("end",end).accepted)
	await await_idle()
	var a:=pipeline.result(begin.command_id);var b:=pipeline.result(draw.command_id);var c:=pipeline.result(end.command_id)
	check("control_barriers_preserve_dependency",not a.is_empty() and not b.is_empty() and not c.is_empty() and a.outcome==L.Outcome.NO_CHANGE and b.outcome==L.Outcome.APPLIED and c.outcome==L.Outcome.NO_CHANGE and a.applied_tick==2 and b.applied_tick==2 and c.applied_tick==2)
	observations.control_barrier=await snapshot("control_barrier_final")

func castle() -> void:
	expect("begin",await perform("begin",control_identity(),"begin"),L.Outcome.NO_CHANGE)
	var params:={"height_m":0.7,"scale_xz":1.5,"yaw_rad":0.4}
	expect("castle_mixed",await perform("castle_mixed",shape_request(&"castle_v1",Vector2.ZERO,Vector2.ZERO,1,params)),L.Outcome.APPLIED)
	expect("castle_repeat",await perform("castle_repeat",shape_request(&"castle_v1",Vector2.ZERO,Vector2.ZERO,2,params)),L.Outcome.NO_CHANGE)
	expect("castle_budget",await perform("castle_budget",shape_request(&"castle_v1",Vector2(-5,0),Vector2(-5,0),3,params,1,11,1,{"add_budget_m3":0.0})),L.Outcome.REJECTED,L.ErrorCode.BUDGET_EXCEEDED)
	expect("castle_plain",await perform("castle_plain",shape_request(&"castle_v1",Vector2(-5,0),Vector2(-5,0),4,params,1,11,0)),L.Outcome.APPLIED)
	var high:=await perform("castle_high",shape_request(&"castle_v1",Vector2(5,0),Vector2(5,0),5,{"height_m":0.7,"scale_xz":1.0,"yaw_rad":0.0}))
	expect("castle_high",high,L.Outcome.NO_CHANGE)
	check("coverage_only_no_revision",not high.is_empty() and high.coverage_changed==1 and high.changed_fields==L.Profile.COVERAGE and high.input_revision==high.output_revision)
	expect("end",await perform("end",control_identity(),"end"),L.Outcome.NO_CHANGE)

func wall() -> void:
	expect("begin",await perform("begin",control_identity(),"begin"),L.Outcome.NO_CHANGE)
	expect("wall_first",await perform("wall_first",shape_request(&"wall_v1",Vector2(-2,0),Vector2.ZERO,1)),L.Outcome.APPLIED)
	serial+=1;var dig: Dictionary=request(serial,&"dig_v1",Vector2(-1,0),0.1)
	expect("dig_old_coverage",await perform("dig_old_coverage",dig),L.Outcome.APPLIED)
	expect("wall_stationary",await perform("wall_stationary",shape_request(&"wall_v1",Vector2(4,0),Vector2(4,0),2)),L.Outcome.NO_CHANGE)
	expect("wall_far_restores_old",await perform("wall_far_restores_old",shape_request(&"wall_v1",Vector2(4,0),Vector2(6,0),3)),L.Outcome.APPLIED)
	expect("wall_repeat",await perform("wall_repeat",shape_request(&"wall_v1",Vector2(4,0),Vector2(6,0),4)),L.Outcome.NO_CHANGE)
	expect("wall_corner",await perform("wall_corner",shape_request(&"wall_v1",Vector2(6,0),Vector2(6,2),5)),L.Outcome.APPLIED)
	expect("wall_budget",await perform("wall_budget",shape_request(&"wall_v1",Vector2(-4,0),Vector2(-2,0),6,{},1,11,1,{"add_budget_m3":0.0})),L.Outcome.REJECTED,L.ErrorCode.BUDGET_EXCEEDED)
	expect("rejected_sample_consumed",await perform("rejected_sample_consumed",shape_request(&"wall_v1",Vector2(-4,0),Vector2(-2,0),6)),L.Outcome.REJECTED,L.ErrorCode.INVALID_BASELINE)
	expect("end",await perform("end",control_identity(),"end"),L.Outcome.NO_CHANGE)

func stroke_bounds() -> void:
	expect("begin",await perform("begin",control_identity(),"begin"),L.Outcome.NO_CHANGE)
	var first:=shape_request(&"wall_small_buffer",Vector2.ZERO,Vector2(0.5,0),1)
	var second:=shape_request(&"wall_small_buffer",Vector2.ZERO,Vector2(0.5,0),2)
	var third:=shape_request(&"wall_small_buffer",Vector2.ZERO,Vector2(0.5,0),3)
	check("small_buffer_first",pipeline.submit_intent(first).accepted)
	check("small_buffer_second",pipeline.submit_intent(second).accepted)
	var overflow:=pipeline.submit_intent(third)
	check("profile_buffer_cap",not overflow.accepted and overflow.error==&"stroke_buffer_full")
	await await_idle()
	check("buffer_recovers_without_new_stroke",pipeline.submit_intent(third).accepted)
	await await_idle()
	var sample:=4
	var all_results:=true
	for chunk in 5:
		var ids: Array[int]=[]
		for offset in mini(64,300-chunk*64):
			var item:=shape_request(&"wall_v1",Vector2.ZERO,Vector2(0.5,0),sample)
			all_results=all_results and pipeline.submit_intent(item).accepted
			ids.append(item.command_id);sample+=1
		await await_idle()
		for id in ids:
			var value:=pipeline.result(id)
			all_results=all_results and not value.is_empty() and value.outcome in [L.Outcome.APPLIED,L.Outcome.NO_CHANGE]
	check("stroke_beyond_256_samples",all_results and sample==304)
	observations.long_stroke=await snapshot("long_stroke_final")
	check("actual_last_sample",fields.stroke.decode_s64(24)==303 and fields.stroke.decode_s64(8)==9007199254740994 and fields.stroke.decode_s64(16)==9007199254742004)
	expect("end",await perform("end",control_identity(),"end"),L.Outcome.NO_CHANGE)

func smooth() -> void:
	expect("smooth",await perform("smooth",local_request(&"smooth_v1",Vector2.ZERO,{"radius_m":2.0,"strength":0.7})),L.Outcome.APPLIED)
	expect("smooth_zero",await perform("smooth_zero",local_request(&"smooth_v1",Vector2.ZERO,{"radius_m":2.0,"strength":0.0})),L.Outcome.NO_CHANGE)
	expect("smooth_edge",await perform("smooth_edge",local_request(&"smooth_v1",Vector2(15.7,15.7),{"radius_m":1.25,"strength":0.4})),L.Outcome.APPLIED)
	expect("smooth_empty",await perform("smooth_empty",local_request(&"smooth_v1",Vector2.ZERO,{"radius_m":0.001})),L.Outcome.REJECTED,L.ErrorCode.INVALID_PLACEMENT)

func compact() -> void:
	var first:=await perform("compact",local_request(&"compact_v1",Vector2.ZERO,{"radius_m":1.5,"strength":1.0}))
	expect("compact",first,L.Outcome.APPLIED)
	check("compact_only_material",not first.is_empty() and first.changed_fields==L.Profile.MATERIAL and first.added_m3==0.0 and first.removed_m3==0.0)
	expect("compact_zero",await perform("compact_zero",local_request(&"compact_v1",Vector2.ZERO,{"radius_m":1.5,"strength":0.0})),L.Outcome.NO_CHANGE)
	expect("compact_tiny",await perform("compact_tiny",local_request(&"compact_v1",Vector2.ZERO,{"radius_m":1.5,"strength":0.000001})),L.Outcome.NO_CHANGE)
	expect("compact_empty",await perform("compact_empty",local_request(&"compact_v1",Vector2.ZERO,{"radius_m":0.001})),L.Outcome.REJECTED,L.ErrorCode.INVALID_PLACEMENT)
	for count in 12:
		var value:=await perform("compact_repeat_"+str(count),local_request(&"compact_v1",Vector2(0.0625,0.0625),{"radius_m":0.07,"strength":1.0}))
		check("compact_repeat_valid_"+str(count),not value.is_empty() and value.outcome in [L.Outcome.APPLIED,L.Outcome.NO_CHANGE])
	expect("compact_saturated",await perform("compact_saturated",local_request(&"compact_v1",Vector2(0.0625,0.0625),{"radius_m":0.07})),L.Outcome.NO_CHANGE)

func local_mixed() -> void:
	expect("mixed_compact",await perform("mixed_compact",local_request(&"compact_v1",Vector2.ZERO,{"radius_m":1.0,"strength":0.5})),L.Outcome.APPLIED)
	expect("mixed_smooth",await perform("mixed_smooth",local_request(&"smooth_v1",Vector2.ZERO,{"radius_m":1.0,"strength":0.5})),L.Outcome.APPLIED)
	serial+=1
	expect("mixed_volume",await perform("mixed_volume",request(serial,&"fill_v1",Vector2(3,0),0.05)),L.Outcome.APPLIED)
	expect("mixed_smaller_smooth",await perform("mixed_smaller_smooth",local_request(&"smooth_v1",Vector2(3,0),{"radius_m":0.5,"strength":0.25})),L.Outcome.APPLIED)
	expect("mixed_empty_compact",await perform("mixed_empty_compact",local_request(&"compact_v1",Vector2(3,0),{"radius_m":0.001})),L.Outcome.REJECTED,L.ErrorCode.INVALID_PLACEMENT)

func _inject_invalid_compaction_render() -> void:
	var invalid:=PackedByteArray();invalid.resize(65536*2)
	for index in 65536:invalid.encode_half(index*2,0.25)
	invalid.encode_half((128*256+128)*2,NAN)
	var texture: RID=pipeline.state._create_texture(RenderingDevice.DATA_FORMAT_R16_SFLOAT,invalid)
	for target in pipeline.state.textures.compaction:pipeline.transport.rd.texture_copy(texture,target,Vector3.ZERO,Vector3.ZERO,Vector3(256,256,1),0,0,0,0)
	call_deferred("_snapshot_armed")

func local_invalid() -> void:
	armed_snapshot=false;RenderingServer.call_on_render_thread(_inject_invalid_compaction_render)
	while not armed_snapshot:await process_frame
	expect("invalid_compact",await perform("invalid_compact",local_request(&"compact_v1")),L.Outcome.REJECTED,L.ErrorCode.CANDIDATE_INVALID)
	expect("invalid_smooth",await perform("invalid_smooth",local_request(&"smooth_v1")),L.Outcome.REJECTED,L.ErrorCode.CANDIDATE_INVALID)

func transfer() -> void:
	if probe_case=="transfer_invalid":expect("without_begin",await perform("without_begin",shape_request(&"shovel_v1",Vector2.ZERO,Vector2(1,0),1,{},1,11,2)),L.Outcome.REJECTED,L.ErrorCode.INVALID_BASELINE)
	expect("begin",await perform("begin",control_identity(),"begin"),L.Outcome.NO_CHANGE)
	if probe_case=="transfer_invalid":
		expect("wrong_token",await perform("wrong_token",shape_request(&"shovel_v1",Vector2.ZERO,Vector2(1,0),1,{},1,12,2)),L.Outcome.REJECTED,L.ErrorCode.INVALID_BASELINE)
		armed_snapshot=false;RenderingServer.call_on_render_thread(_inject_invalid_compaction_render)
		while not armed_snapshot:await process_frame
		expect("invalid_material",await perform("invalid_material",shape_request(&"shovel_v1",Vector2.ZERO,Vector2(1,0),1,{},1,11,2)),L.Outcome.REJECTED,L.ErrorCode.CANDIDATE_INVALID)
		expect("consumed_rejected_sample",await perform("consumed_rejected_sample",shape_request(&"shovel_v1",Vector2.ZERO,Vector2(1,0),1,{},1,11,2)),L.Outcome.REJECTED,L.ErrorCode.INVALID_BASELINE)
	elif probe_case=="transfer_empty":
		expect("empty_donor",await perform("empty_donor",shape_request(&"shovel_v1",Vector2.ZERO,Vector2(1,0),1,{},1,11,2)),L.Outcome.NO_CHANGE)
	elif probe_case=="transfer_capacity":
		expect("one_side_blocked",await perform("one_side_blocked",shape_request(&"shovel_v1",Vector2.ZERO,Vector2(1,0),1,{},1,11,2)),L.Outcome.NO_CHANGE)
		expect("donor_obstacle",await perform("donor_obstacle",shape_request(&"shovel_v1",Vector2(4,0),Vector2(5,0),2,{},1,11,2)),L.Outcome.REJECTED,L.ErrorCode.INVALID_PLACEMENT)
		expect("boundary_valid",await perform("boundary_valid",shape_request(&"shovel_v1",Vector2(15.25,2),Vector2(15.25,3),3,{},1,11,2)),L.Outcome.APPLIED)
		var outside:=shape_request(&"shovel_v1",Vector2(15.8,2),Vector2(15.8,3),4,{},1,11,2)
		var rejected:=pipeline.submit_intent(outside)
		check("full_footprint_admission_boundary",not rejected.accepted and rejected.error==&"out_of_domain")
	elif probe_case=="transfer_limited":
		var value:=await perform("limited",shape_request(&"shovel_v1",Vector2.ZERO,Vector2(1,0),1,{},1,11,2))
		expect("limited",value,L.Outcome.APPLIED)
		check("limited_by_one_receiver",not value.is_empty() and absf(value.removed_m3-0.015625)<value.eps_transfer_m3)
	elif probe_case=="transfer_stress":
		expect("diagonal",await perform("diagonal",shape_request(&"shovel_v1",Vector2(-0.7,-0.7),Vector2(0.7,0.7),1,{"depth_m":0.3,"trench_width_m":1.0,"shoulder_width_m":1.0},1,11,2)),L.Outcome.APPLIED)
		expect("crossing",await perform("crossing",shape_request(&"shovel_v1",Vector2(-0.7,0.7),Vector2(0.7,-0.7),2,{"depth_m":0.3,"trench_width_m":1.0,"shoulder_width_m":1.0},1,11,2)),L.Outcome.APPLIED)
		var repeated:=await perform("max_repeat",shape_request(&"shovel_v1",Vector2(-0.7,0.7),Vector2(0.7,-0.7),3,{"depth_m":0.3,"trench_width_m":1.0,"shoulder_width_m":1.0},1,11,2))
		check("max_repeat_native_closure",not repeated.is_empty() and repeated.outcome in [L.Outcome.APPLIED,L.Outcome.NO_CHANGE] and repeated.removed_m3<=repeated.eps_transfer_m3)
	else:
		var a:=Vector2.ZERO;var b:=Vector2(1,0)
		if probe_case=="transfer_reverse":a=Vector2(1,0);b=Vector2.ZERO
		expect("straight",await perform("straight",shape_request(&"shovel_v1",a,b,1,{},1,11,2)),L.Outcome.APPLIED)
		if probe_case!="transfer_reverse":
			expect("repeat",await perform("repeat",shape_request(&"shovel_v1",a,b,2,{},1,11,2)),L.Outcome.NO_CHANGE)
			expect("reverse_repeat",await perform("reverse_repeat",shape_request(&"shovel_v1",b,a,3,{},1,11,2)),L.Outcome.NO_CHANGE)
			expect("stationary",await perform("stationary",shape_request(&"shovel_v1",a,a,4,{},1,11,2)),L.Outcome.NO_CHANGE)
			expect("overlap_turn",await perform("overlap_turn",shape_request(&"shovel_v1",Vector2(0.5,0),Vector2(1.5,0.5),5,{},1,11,2)),L.Outcome.APPLIED)
			expect("zero_authorization",await perform("zero_authorization",shape_request(&"shovel_v1",Vector2(3,0),Vector2(4,0),6,{},1,11,2,{"transfer_budget_m3":0.0})),L.Outcome.NO_CHANGE)
			expect("small_authorization",await perform("small_authorization",shape_request(&"shovel_v1",Vector2(5,0),Vector2(6,0),7,{},1,11,2,{"transfer_budget_m3":0.001})),L.Outcome.APPLIED)
	expect("end",await perform("end",control_identity(),"end"),L.Outcome.NO_CHANGE)
	if probe_case=="transfer_invalid":expect("after_end",await perform("after_end",shape_request(&"shovel_v1",Vector2.ZERO,Vector2(1,0),2,{},1,11,2)),L.Outcome.REJECTED,L.ErrorCode.INVALID_BASELINE)

func finish() -> void:
	var typed_path:=output.get_base_dir()+"/typed_cases.variant"
	FileAccess.open(typed_path,FileAccess.WRITE).store_buffer(var_to_bytes({"cases":cases,"observations":observations,"terminal_results":pipeline._results,"configuration":pipeline._configuration,"source_hashes":source_hashes}))
	var result:={"pass":not failed,"case":probe_case,"checks":checks,"cases":cases,"observations":observations,"typed_evidence":{"path":typed_path,"sha256":FileAccess.get_sha256(typed_path)},"fault":String(pipeline.fault_reason()),"scope":"T03 common candidates and public commit boundary; no complete water response or formal entry claim"}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"));quit(1 if failed else 0)
