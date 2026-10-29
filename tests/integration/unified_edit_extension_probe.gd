extends "res://tests/integration/unified_edit_gpu_probe.gd"

const Intent=preload("res://scripts/simulation/unified_edit/intent.gd")
var observations: Dictionary={}
var snapshot_index: Dictionary={}
var capture_label:=""

func _run() -> void:
	started=Time.get_ticks_msec();DisplayServer.window_set_size(Vector2i(1280,720))
	var created: Dictionary=load("res://assets/unified_edit/extensions/extension_catalog.tres").instantiate_registry()
	check("extension_registry",created.error.is_empty());registry=created.registry
	if not created.error.is_empty():finish();return
	check("fourteen_profiles_two_templates",registry.catalog_snapshot().size()==14 and registry._templates.size()==2)
	var mapping:={"fill_base":&"fill_v1","fill_new":&"wide_fill_v1","stamp_base":&"castle_v1","stamp_new":&"stepped_mound_tool_v1","transfer_base":&"shovel_v1","transfer_new":&"wide_transfer_v1"}
	var profile_id: StringName=mapping[probe_case]
	var profile: Dictionary=registry.profile(profile_id)
	var extras:=PackedStringArray(Pipeline.SOURCE_PATHS+Pipeline.ADAPTER_SOURCES)
	extras.append_array(PackedStringArray([get_script().resource_path,"res://tests/integration/unified_edit_gpu_probe.gd","res://assets/unified_edit/extensions/extension_catalog.tres","res://assets/unified_edit/extensions/fixture_identity.json"]))
	var sim:={"enable_erosion":false,"enable_brush_water":true,"unrestricted_sand_tools":true,"enable_structures":false,"local_front_history":false,"rise_front_history":false,"contact_history":false}
	var frozen:=Config.freeze(registry,"main_beach",sim,{"foam_enabled":false,"gravel_enabled":false},{},{"engine":Engine.get_version_info().string,"fixture":"g7_config_only_flat_wet"},extras)
	check("immutable_configuration",frozen.error.is_empty())
	if not frozen.error.is_empty():print(frozen.error);finish();return
	source_hashes=frozen.value.sources.duplicate(true);observations.profile=profile.duplicate(true);observations.configuration_hash=frozen.value.configuration_hash
	check("configure_common_pipeline",pipeline.configure(registry,frozen.value,9007199254740993).is_empty())
	domain=Domain.new(256,0.125);domain.domain_id=&"main_beach";domain.generation=9007199254740993
	domain.rock.fill(0.05);domain.sand.fill(0.25);domain.water.fill(0.1);domain.compaction.fill(0.4);domain.wetness.fill(0.2)
	RenderingServer.call_on_render_thread(pipeline.initialize_render.bind(domain))
	while not pipeline.initialized and Time.get_ticks_msec()-started<180000:await process_frame
	check("gpu_initialized",pipeline.initialized and pipeline.fault_reason().is_empty())
	if not pipeline.fault_reason().is_empty():print(pipeline.fault_reason());finish();return
	await _snapshot("before")
	var id:=1;var stroke: bool=profile.stroke_policy!=0
	if stroke:
		check("common_begin",pipeline.submit_control("begin",_control(id)).accepted);id+=1
	var command:=_command(id,profile)
	var bad:=command.duplicate(true);bad.features={"water_policy":99}
	check("unsupported_feature_rejected_before_reservation",not pipeline.submit_intent(bad).accepted and pipeline.command_highwater()==id-1)
	bad=command.duplicate(true);bad.parameters[profile.defaults.keys()[0]]=NAN
	check("nonfinite_parameter_rejected",not pipeline.submit_intent(bad).accepted)
	var decoded:=Intent.freeze(registry,command,"main_beach",9007199254740993)
	check("actual_request_frozen",decoded.error.is_empty())
	if not decoded.error.is_empty():print(decoded.error);finish();return
	observations.intent=decoded.value.duplicate(true)
	check("common_sample",pipeline.submit_intent(command).accepted)
	if stroke:check("common_end",pipeline.submit_control("end",_control(id+1)).accepted)
	await await_idle()
	var result:=pipeline.result(id)
	check("actual_gpu_applied",not result.is_empty() and result.outcome==L.Outcome.APPLIED and result.error_code==0 and result.invalid_flags==0)
	check("same_publication_lifecycle",pipeline.completed_tick==0 and pipeline.advanced_time_s==0.0 and pipeline.completed_state_seq>0 and pipeline.accounting.stroke.is_empty())
	check("derived_write_fields_enforced",result.changed_fields & ~decoded.value.configuration.derived_fields==0)
	observations.result=result.duplicate(true);observations.trace=pipeline.executor.traces.duplicate(true);observations.sample_id=id
	await _snapshot("after")
	var identity: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/unified_edit/extensions/fixture_identity.json"))
	var stable:=true
	for path in identity.core_before:stable=stable and FileAccess.get_sha256("res://"+path)==identity.core_before[path]
	check("all_fifty_one_core_hashes_unchanged",stable)
	observations.core_before=identity.core_before.duplicate(true)
	pipeline.close_admission();RenderingServer.call_on_render_thread(pipeline.release_render)
	var start:=Time.get_ticks_msec()
	while not pipeline.released and Time.get_ticks_msec()-start<15000:await process_frame
	check("extension_uses_common_release",pipeline.released)
	finish()

func _control(id: int) -> Dictionary:return {"domain_id":"main_beach","generation":9007199254740993,"command_id":id,"sim_tick":0,"stroke_id":101,"baseline_token":101}
func _command(id: int, profile: Dictionary) -> Dictionary:
	var value:={"domain_id":"main_beach","generation":9007199254740993,"command_id":id,"sim_tick":0,"profile_id":StringName(profile.profile_id),"profile_version":profile.version,"profile_hash":profile.profile_hash,"start_xz_m":Vector2.ZERO,"end_xz_m":Vector2.ZERO,"parameters":profile.defaults.duplicate(true),"features":{"water_policy":3},"seed":73}
	if profile.shape==L.Profile.Shape.SWEPT_CAPSULE:value.start_xz_m=Vector2(-0.75,0);value.end_xz_m=Vector2(0.75,0)
	if profile.stroke_policy!=0:value.merge({"stroke_id":101,"baseline_token":101,"sample_index":0})
	return value

func _snapshot(label: String) -> void:
	capture_label=label;fields={};remaining=21;RenderingServer.call_on_render_thread(_read_render)
	var start:=Time.get_ticks_msec()
	while remaining>0 and Time.get_ticks_msec()-start<15000:await process_frame
	check("snapshot_"+label,remaining==0)
	var index:={}
	for key in fields:
		var path: String=output.get_base_dir()+"/"+label+"_"+key+".bin";FileAccess.open(path,FileAccess.WRITE).store_buffer(fields[key]);index[key]={"path":path,"sha256":FileAccess.get_sha256(path),"bytes":fields[key].size()}
	snapshot_index[label]=index
func _read_render() -> void:
	var t: Dictionary=pipeline.state.textures
	for key in ["sand","water","sediment","momentum_x","momentum_z","compaction","wetness","mold_support","flux"]:
		for i in 2:
			if pipeline.transport.rd.texture_get_data_async(t[key][i],0,_field_render.bind(key+str(i)))!=OK:call_deferred("_read_failed",key+str(i))
	for key in ["rock","obstacle"]:
		if pipeline.transport.rd.texture_get_data_async(t[key],0,_field_render.bind(key))!=OK:call_deferred("_read_failed",key)
	if pipeline.transport.rd.buffer_get_data_async(pipeline.transport.control,_field_render.bind("control"),0,L.CONTROL_BYTES)!=OK:call_deferred("_read_failed","control")
func finish() -> void:
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"case":probe_case,"checks":checks,"source_hashes":source_hashes,"observations":observations,"snapshots":snapshot_index,"scope":"Config-only original fixtures, real wet edit fields and common trace/lifecycle; no new product UI or writer, broader G7 audit pending"},"\t"));quit(1 if failed else 0)
