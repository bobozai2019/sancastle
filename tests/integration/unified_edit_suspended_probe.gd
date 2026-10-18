extends "res://tests/integration/unified_edit_target_probe.gd"

const Retained=preload("res://tests/integration/unified_edit_legacy_coupled_reference.gd")
var retained
var retained_ready:=false
var retained_bytes: Dictionary={}
var retained_error:=""

func _extra_image_fields() -> Dictionary:
	var t: Dictionary=pipeline.state.textures
	var extra:={"sediment0":t.sediment[0],"sediment1":t.sediment[1],"water1":t.water[1],"wetness0":t.wetness[0],"wetness1":t.wetness[1],"qx0":t.momentum_x[0],"qx1":t.momentum_x[1],"qz0":t.momentum_z[0],"qz1":t.momentum_z[1],"flux0":t.flux[0],"flux1":t.flux[1]}
	if pipeline.coupled.images.has("dirty"):extra.dirty=pipeline.coupled.images.dirty
	return extra

func _run() -> void:
	started=Time.get_ticks_msec();pipeline.executor=Observed.new()
	DisplayServer.window_set_size(Vector2i(1280,720));DisplayServer.window_set_title("Unified suspended / coupled contract")
	var created: Dictionary=load("res://assets/unified_edit/default_catalog.tres").instantiate_registry()
	check("registry",created.error.is_empty());registry=created.registry
	var simulation:={"enable_erosion":probe_case!="suspended_disabled","enable_brush_water":true,"unrestricted_sand_tools":true,"enable_structures":false,"local_front_history":false,"rise_front_history":false,"contact_history":false}
	var extras:=PackedStringArray(Pipeline.SOURCE_PATHS+Pipeline.ADAPTER_SOURCES)
	extras.append_array(_additional_sources())
	extras.append_array(PackedStringArray(Retained.SOURCES))
	extras.append(get_script().resource_path)
	extras.append_array(PackedStringArray(["res://tests/integration/unified_edit_observed_executor.gd","res://tests/integration/unified_edit_target_probe.gd","res://tests/integration/unified_edit_suspended_probe.gd"]))
	var configuration:=Config.freeze(registry,"main_beach",simulation,{"foam_enabled":false,"gravel_enabled":false},{},{"engine":Engine.get_version_info().string,"probe":"all_profiles" if probe_case.begins_with("all_profiles") else probe_case},extras)
	check("configuration",configuration.error.is_empty())
	if not configuration.error.is_empty():finish();return
	source_hashes=configuration.value.sources.duplicate(true)
	check("configure",pipeline.configure(registry,configuration.value,9007199254740993).is_empty())
	domain=Domain.new(256,0.125);domain.domain_id=&"main_beach";domain.generation=9007199254740993
	domain.rock.fill(0.05);domain.sand.fill(0.25);domain.water.fill(0.1);domain.sediment.fill(0.03);domain.compaction.fill(0.4);domain.wetness.fill(0.1)
	var tagged:=PackedFloat32Array();tagged.resize(65536)
	for z in 256:
		for x in 256:
			var index:=z*256+x
			if probe_case.begins_with("coupled"):
				domain.sand[index]=0.2+1.0*exp(-Vector2(x-128,z-128).length_squared()/8.0)
				if "molded" in probe_case:tagged[index]=domain.sand[index]*0.6
			else:
				tagged[index]=domain.sand[index]*0.35
				if x<128:domain.water[index]=0.001
	domain.set_meta("brush_initial_mold_depth",tagged)
	if not probe_case.begins_with("coupled"):domain.obstacle[128*256+130]=1.0
	else:
		var desired:=int(probe_case.get_slice("_",1));var speed: float=(float(desired)-0.25)*0.35*0.125/0.001
		var momentum:=PackedFloat32Array();momentum.resize(65536);momentum.fill(maxf(0.0,speed-sqrt(9.81*0.1))*0.1);domain.set_meta("edit_validation_initial_qx",momentum)
	_configure_domain()
	RenderingServer.call_on_render_thread(pipeline.initialize_render.bind(domain))
	while not pipeline.initialized and Time.get_ticks_msec()-started<20000:await process_frame
	check("gpu_initialized",pipeline.initialized and pipeline.fault_reason().is_empty())
	if not pipeline.fault_reason().is_empty():print(pipeline.fault_reason());finish();return
	if probe_case.begins_with("coupled"):await coupled_tick()
	elif probe_case=="suspended_disabled":
		var rejected:=pipeline.submit_intent(request(1,&"suspended_v1",Vector2.ZERO))
		check("disabled_capability_rejected",not rejected.accepted and rejected.error==&"unsupported_suspended_capability" and pipeline.executor.recorded_commands==0)
	else:await suspended()
	pipeline.close_admission();RenderingServer.call_on_render_thread(_release_legacy_local_render);RenderingServer.call_on_render_thread(pipeline.release_render)
	var end:=Time.get_ticks_msec()
	while not pipeline.released and Time.get_ticks_msec()-end<10000:await process_frame
	check("released",pipeline.released);finish()

func _configure_domain() -> void:pass
func _additional_sources() -> PackedStringArray:return PackedStringArray()

func suspended() -> void:
	var profile: StringName=&"suspended_sweep_v1" if probe_case=="suspended_sweep" else &"suspended_v1"
	if probe_case=="suspended_invalid":
		armed_snapshot=false;RenderingServer.call_on_render_thread(_invalid_sediment_render)
		while not armed_snapshot:await process_frame
		expect("invalid_sediment",await perform("invalid_sediment",request(1,profile,Vector2.ZERO)),L.Outcome.REJECTED,L.ErrorCode.CANDIDATE_INVALID)
		for field in ["sediment0","sediment1"]:check("invalid_sediment_precommit_"+field,cases[0].before[field].sha256==cases[0].after["pre_"+field].sha256)
		return
	expect("wet",await perform("wet",request(1,profile,Vector2.ZERO)),L.Outcome.APPLIED)
	var zero:=request(2,profile,Vector2.ZERO);zero.parameters.strength=0.0
	expect("zero",await perform("zero",zero),L.Outcome.NO_CHANGE)
	expect("dry",await perform("dry",request(3,profile,Vector2(-3,0))),L.Outcome.REJECTED,L.ErrorCode.OUT_OF_DOMAIN)
	var budget:=request(4,profile,Vector2.ZERO);budget.authorization={"available_m3":0.0}
	expect("budget",await perform("budget",budget),L.Outcome.REJECTED,L.ErrorCode.BUDGET_EXCEEDED)
	expect("bed_after_suspended",await perform("bed_after_suspended",request(5,&"fill_v1",Vector2(3,0))),L.Outcome.APPLIED)
	expect("smaller",await perform("smaller",request(6,&"suspended_v1",Vector2(0.25,0))),L.Outcome.APPLIED)
	for item in cases:
		for field in ["sediment0","sediment1"]:check(item.label+"_precommit_"+field,item.before[field].sha256==item.after["pre_"+field].sha256)
		if item.wire.destination==L.Profile.Destination.SUSPENDED_SAND:
			for field in ["sand0","sand1","support0","support1","compact0","compact1","water","water1","wetness0","wetness1","qx0","qx1","qz0","qz1"]:check(item.label+"_read_only_"+field,item.before[field].sha256==item.after[field].sha256)

func coupled_tick() -> void:
	var before:=await snapshot("coupled_before")
	check("tick_admitted",pipeline.request_tick(0.001).is_empty());await await_idle()
	RenderingServer.call_on_render_thread(_read_decision_render)
	var begin:=Time.get_ticks_msec()
	while water_decision.is_empty() and Time.get_ticks_msec()-begin<10000:await process_frame
	check("decision",water_decision.size()==64)
	var after:=await snapshot("coupled_after")
	observations.coupled={"before":before,"after":after,"decision_hex":water_decision.hex_encode(),"actual_time_s":pipeline.advanced_time_s,"tick":pipeline.completed_tick,"revision":pipeline.completed_revision}
	check("real_coupled_clock",pipeline.completed_tick==1 and pipeline.advanced_time_s>0.0)
	check("material_advances_or_native_quantum",before.wetness0.sha256!=after.wetness0.sha256 or water_decision.decode_float(8)*1.5<0.00006103515625)
	check("sediment_really_advanced",before.sediment0.sha256!=after.sediment0.sha256)
	retained_ready=false;RenderingServer.call_on_render_thread(_retained_render)
	begin=Time.get_ticks_msec()
	while not retained_ready and Time.get_ticks_msec()-begin<20000:await process_frame
	check("retained_completed",retained_ready and retained_error.is_empty() and retained_bytes.size()==9)
	var index:={}
	for key in retained_bytes:
		var path: String=output.get_base_dir()+"/reference_"+String(key)+".bin"
		FileAccess.open(path,FileAccess.WRITE).store_buffer(retained_bytes[key]);index[key]={"path":path,"bytes":retained_bytes[key].size(),"sha256":FileAccess.get_sha256(path)}
		var actual: String={"sand":"sand0","water":"water","sediment":"sediment0","qx":"qx0","qz":"qz0","wetness":"wetness0","compact":"compact0","support":"support0","flux":"flux0"}[key]
		check("retained_exact_"+String(key),after[actual].sha256==index[key].sha256)
	observations.coupled.reference=index
	retained_ready=false;RenderingServer.call_on_render_thread(_release_retained_render)
	while not retained_ready:await process_frame

func _retained_render() -> void:
	retained=Retained.new()
	if not retained.initialize(pipeline.transport.rd,domain,water_decision):call_deferred("_retained_failed",retained.last_error);return
	retained.record(water_decision)
	for key in retained.output_images():
		if pipeline.transport.rd.texture_get_data_async(retained.output_images()[key],0,_retained_read.bind(key))!=OK:call_deferred("_retained_failed","retained_read")
func _retained_read(data: PackedByteArray, key: String) -> void:call_deferred("_retained_field",data,key)
func _retained_field(data: PackedByteArray, key: String) -> void:
	retained_bytes[key]=data
	if retained_bytes.size()==9:retained_ready=true
func _retained_failed(reason: String) -> void:retained_error=reason;retained_ready=true
func _release_retained_render() -> void:retained.release();call_deferred("_retained_released")
func _retained_released() -> void:retained_ready=true

func _invalid_sediment_render() -> void:
	var data: PackedByteArray=domain.sediment.to_byte_array();data.encode_float((128*256+128)*4,NAN)
	var texture: RID=pipeline.state._create_texture(RenderingDevice.DATA_FORMAT_R32_SFLOAT,data)
	for target in pipeline.state.textures.sediment:pipeline.transport.rd.texture_copy(texture,target,Vector3.ZERO,Vector3.ZERO,Vector3(256,256,1),0,0,0,0)
	call_deferred("_snapshot_armed")
