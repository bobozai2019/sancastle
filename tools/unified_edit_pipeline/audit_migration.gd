extends SceneTree

# Independent container and byte audit. No production codec/projector/validator.
var checks: Array=[]
var failed:=false
var folder:=""
func check(name: String, passed: bool) -> void:
	checks.append({"name":name,"pass":passed});failed=failed or not passed
func read_container(path: String, magic: String) -> Dictionary:
	var raw:=FileAccess.get_file_as_bytes(path)
	check(path+"_size",raw.size()>=48)
	if raw.size()<48:return {}
	check(path+"_magic",raw.slice(0,8).get_string_from_ascii()==magic)
	check(path+"_version",raw.decode_u32(8)==1)
	check(path+"_length",raw.decode_u32(12)==raw.size()-48)
	var context:=HashingContext.new();context.start(HashingContext.HASH_SHA256);context.update(raw.slice(48))
	check(path+"_digest",context.finish()==raw.slice(16,48))
	var value: Variant=bytes_to_var(raw.slice(48))
	check(path+"_data_dictionary",value is Dictionary)
	return value if value is Dictionary else {}
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--folder="):folder=arg.trim_prefix("--folder=")
	call_deferred("_run")
func _run() -> void:
	var report: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(folder+"/report.json"))
	check("visible_probe_passed",report.get("pass",false))
	var probe: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(folder+"/migration_main/probe.json"))
	check("two_genuine_formats",probe.observations.migrations.size()==2)
	var catalog: Dictionary=bytes_to_var(FileAccess.get_file_as_bytes("res://assets/unified_edit/legacy_source_catalog.variant"))
	check("catalog_has_two_validated_sources",catalog.schema==1 and catalog.sources.size()==2)
	for row in probe.observations.migrations:
		var modern: bool=row.format=="edit5_native3"
		var original:=read_container(row.source,"SANDGP05" if modern else "SANDCP01")
		# The older container includes the unchanged checkpoint envelope.
		if not modern:original=original.get("checkpoint",{})
		var actual:=read_container(row.native,"SANDUE06")
		if original.is_empty() or actual.is_empty():continue
		var native: Dictionary=original.native if modern else original.gpu_beach_native
		for group in ["fields","spare","material","foam"]:
			check(row.format+"_"+group+"_key_count",actual.native[group].size()==native[group].size())
			for key in native[group]:check(row.format+"_"+group+"_"+str(key),actual.native[group].get(key)==native[group][key])
		if modern:
			check("v3_histories",actual.native.histories==native.histories)
			var control: PackedByteArray=native.control.duplicate();control.encode_s64(8,actual.generation)
			check("v3_control_only_epoch_rebased",actual.native.control==control)
			for key in ["ledger","state_seq","sim_tick","revision","advanced_time_s","highwater_id","initial_sand_total_m3"]:check("v3_"+key,actual[key]==original[key])
		else:
			check("v2_ledger",actual.ledger==original.gpu_beach_edit.ledger)
			check("v2_local_front",actual.native.histories.local_front==original.local_front_history.to_byte_array())
			check("v2_new_sequence_zero",actual.state_seq==0)
			check("v2_tick",actual.sim_tick==original.tick)
			check("v2_revision",actual.revision==original.revision)
			check("v2_explicit_clock_mapping",actual.advanced_time_s==PackedFloat32Array([float(original.tick)/30.0])[0])
			check("v2_original_prefix",actual.source_provenance.original_prefix==original.gpu_beach_edit.prefix)
			var control:=PackedByteArray();control.resize(128)
			control.encode_u32(0,1);control.encode_s64(8,actual.generation);control.encode_s64(24,original.tick);control.encode_float(32,PackedFloat32Array([float(original.tick)/30.0])[0]);control.encode_s64(40,original.revision)
			check("v2_explicit_control_mapping",actual.native.control==control)
		var gravel: Dictionary=original.visual_extensions.gravel_v1
		var restored: Dictionary=actual.visual_extensions.gravel_v1
		for key in gravel:
			if key not in ["source_generation","version"]:check(row.format+"_gravel_"+key,restored[key]==gravel[key])
		check(row.format+"_gravel_generation_rebased",restored.source_generation==actual.generation)
		check(row.format+"_gravel_v2_count_mapping",restored.version==2 and restored.active_count==gravel.get("active_count",gravel.count))
		check(row.format+"_source_file_hash",FileAccess.get_sha256(row.source)==row.source_sha256 and actual.source_provenance.sha256==row.source_sha256)
		var signature: Dictionary=original.configuration if modern else original.gpu_beach_edit.configuration
		check(row.format+"_original_configuration_preserved",actual.source_provenance.configuration==signature)
		var known:=false
		for item in catalog.sources:
			if item.format==row.format:known=item.configuration==signature and item.fixture.sha256==row.source_sha256 and item.fixture.path==row.source
		check(row.format+"_catalog_matches_genuine_source",known)
	FileAccess.open(folder+"/independent_audit.json",FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"checks":checks,"auditor_sha256":FileAccess.get_sha256(get_script().resource_path)},"\t"))
	print("MIGRATION_AUDIT ",not failed," checks=",checks.size())
	quit(1 if failed else 0)
