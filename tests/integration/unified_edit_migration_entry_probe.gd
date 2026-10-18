extends "res://tests/integration/unified_edit_playable_probe.gd"

const Router=preload("res://scripts/simulation/unified_edit/checkpoint_router.gd")
const Legacy=preload("res://scripts/simulation/unified_edit/legacy_sources.gd")
const Config=preload("res://scripts/simulation/unified_edit/configuration.gd")
const FIXTURES=preload("res://tests/integration/unified_edit_configuration_probe.gd").FIXTURES

func _run() -> void:
	orphan_baseline=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	DisplayServer.window_set_size(Vector2i(1280,720))
	scene=load(_entry_path(scene_key)).instantiate();scene.playing=false;scene.generation=1001;root.add_child(scene)
	var start:=Time.get_ticks_msec()
	while not scene.ready_for_ticks and scene.last_error.is_empty() and Time.get_ticks_msec()-start<_ready_timeout_ms():await process_frame
	check("migration_entry_ready",scene.ready_for_ticks and scene.last_error.is_empty())
	if not scene.ready_for_ticks:await _close();return
	observations.sources=scene.configuration.sources.duplicate(true)
	var source:=Legacy.new()
	check("bundled_catalog_without_fixture_initialization",source.initialize_catalog(Router.CATALOG,Router.CATALOG_SHA256).is_empty())
	check("bad_catalog_hash_rejected",Legacy.new().initialize_catalog(Router.CATALOG,"0".repeat(64))==&"legacy_catalog_identity_mismatch")
	check("catalog_cannot_reinitialize",source.initialize_catalog(Router.CATALOG,Router.CATALOG_SHA256)==&"legacy_sources_already_initialized")
	observations.migrations=[]
	for index in FIXTURES.size():
		var path: String=FIXTURES[index]
		var owner=scene.runtime.current
		var epoch: int=scene.generation
		var inspected:=source.inspect_file(path)
		check("trusted_source_"+str(index),inspected.error.is_empty())
		var error: StringName=await scene.restore_gpu_checkpoint(path)
		if scene_key!="main":
			check("foreign_domain_explicitly_rejected_"+str(index),error in [&"checkpoint_domain_mismatch",&"legacy_domain_or_erosion_mismatch"])
			check("foreign_domain_keeps_current_"+str(index),scene.runtime.current==owner and scene.runtime.candidate==null and scene.generation==epoch and scene.runtime.ready_for_input())
			continue
		check("actual_legacy_candidate_restore_"+str(index),error.is_empty())
		if not error.is_empty():print("MIGRATION_ERROR ",error);continue
		await _retired()
		check("new_epoch_and_old_owner_released_"+str(index),scene.generation>epoch and owner.released and scene.runtime.retired.is_empty())
		var saved:=output+"/migrated_"+str(index)+".sandue"
		check("save_after_migration_"+str(index),(await scene.save_gpu_checkpoint(saved)).is_empty())
		var actual:=Codec.load(saved,scene.configuration)
		var projected:=Router.load_file(path,scene.configuration)
		check("migrated_native_load_"+str(index),actual.error.is_empty() and projected.error.is_empty())
		if not actual.error.is_empty() or not projected.error.is_empty():continue
		var expected: Dictionary=projected.checkpoint
		var value: Dictionary=actual.checkpoint
		for group in ["fields","spare","material","foam","histories"]:
			check("raw_"+str(index)+"_"+group,value.native[group]==expected.native[group])
		for key in ["ledger","sim_tick","revision","state_seq","advanced_time_s","highwater_id","wave_highwater_id","wave_start_times"]:
			check("preserved_"+str(index)+"_"+key,value[key]==expected[key])
		var gravel: Dictionary=value.visual_extensions.gravel_v1
		var old_gravel: Dictionary=expected.visual_extensions.gravel_v1
		for key in old_gravel:
			if key not in ["version","source_generation"]:check("gravel_"+str(index)+"_"+str(key),gravel.get(key)==old_gravel[key])
		check("gravel_population_restored_"+str(index),gravel.version==2 and gravel.source_generation==scene.generation and gravel.active_count==old_gravel.get("active_count",old_gravel.count) and scene.get_node("GravelLayer").multimesh.visible_instance_count==scene.runtime.current.visuals.active_count)
		check("original_source_provenance_"+str(index),value.source_provenance.format==inspected.format and value.source_provenance.sha256==FileAccess.get_sha256(path) and value.source_provenance.configuration==inspected.provenance.configuration)
		check("native_router_roundtrip_"+str(index),Router.load_file(saved,scene.configuration).error.is_empty())
		observations.migrations.append({"format":inspected.format,"source":path,"source_sha256":FileAccess.get_sha256(path),"native":saved,"native_sha256":FileAccess.get_sha256(saved),"generation":scene.generation,"state_seq":value.state_seq,"tick":value.sim_tick,"time":value.advanced_time_s})
	# A structurally valid old file cannot install its own source signature.
	var changed: Dictionary=Legacy.Old.load(FIXTURES[0]).checkpoint
	changed.configuration["unknown_release"]=true
	var unknown:=output+"/untrusted.sandgp"
	check("unknown_signature_fixture_valid_old_format",Legacy.Old.save(unknown,changed).is_empty())
	check("unknown_source_signature_rejected",Router.load_file(unknown,scene.configuration).error==&"unknown_legacy_source_configuration")
	var broken:=output+"/bad_header.sandue"
	FileAccess.open(broken,FileAccess.WRITE).store_buffer(PackedByteArray());check("truncated_header_rejected",Router.load_file(broken,scene.configuration).error==&"invalid_file_size")
	FileAccess.open(broken,FileAccess.WRITE).store_buffer("UNKNOWN!".repeat(6).to_ascii_buffer());check("unknown_family_rejected",Router.load_file(broken,scene.configuration).error==&"unsupported_checkpoint_family")
	if scene_key=="main":
		var current=scene.runtime.current
		check("edit_after_old_restore",scene.input.begin(&"place_sand",Vector2(3,0),{},0.1,3,0.25).accepted);scene.input.finish();await _idle()
		check("edit_after_restore_published",scene.runtime.current==current and scene.runtime.current.completed_state_seq>observations.migrations[-1].state_seq)
	observations.events=scene.runtime.events.duplicate(true)
	await _close()

func _retired() -> void:
	var start:=Time.get_ticks_msec()
	while not scene.runtime.retired.is_empty() and Time.get_ticks_msec()-start<30000:await process_frame
	await process_frame

func finish() -> void:
	FileAccess.open(output+"/probe.json",FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"checks":checks,"observations":observations,"scope":"Bundled source trust, genuine old fixtures through unified restore, byte-preserving native resave, rejection and close. Consumed sources identify the actual scene family."},"\t"))
	quit(1 if failed else 0)
