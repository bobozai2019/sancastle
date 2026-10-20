extends SceneTree

# Offline metadata/validator probe. No RenderingDevice or active domain is built.
const Codec=preload("res://scripts/simulation/unified_edit/checkpoint_codec.gd")
const Config=preload("res://scripts/simulation/unified_edit/configuration.gd")
const Consumer=preload("res://scripts/simulation/unified_edit/consumer_checkpoint_sources.gd")

func _initialize() -> void:
	var output:=""
	var inputs:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		if arg.begins_with("--inputs="):inputs=arg.trim_prefix("--inputs=")
	if output.is_empty() or inputs.is_empty() or DirAccess.dir_exists_absolute(output):quit(2);return
	DirAccess.make_dir_recursive_absolute(output)
	var request: Variant=JSON.parse_string(FileAccess.get_file_as_string(inputs))
	if not request is Array:quit(2);return
	var rows: Array=[]
	var known: Array=[]
	for path in request:
		var row:={"path":path,"exists":FileAccess.file_exists(path)}
		if row.exists:
			row.sha256=FileAccess.get_sha256(path)
			var loaded:=Codec.read_container(path)
			row.container_error=String(loaded.error)
			if loaded.error.is_empty():
				var cp: Dictionary=loaded.checkpoint
				row.configuration_hash=cp.configuration.configuration_hash
				row.validation_error=String(Codec.validate(cp,cp.configuration,false))
				# Historical Variant mixed-key sorting may differ. An exact original
				# configuration pin can authorize only this derived-hash validation.
				var validation_copy:=cp.duplicate(true)
				validation_copy.configuration.configuration_hash=Config.stable_hash(validation_copy.configuration)
				row.normalized_validation_error=String(Codec.validate(validation_copy,validation_copy.configuration,false))
				row.sim_tick=str(cp.sim_tick);row.revision=str(cp.revision);row.advanced_time_s=cp.advanced_time_s
				row.source_count=cp.configuration.sources.size()
				if row.normalized_validation_error.is_empty():
					known.append({"configuration":cp.configuration.duplicate(true),"fixture":{"path":path,"sha256":row.sha256},"validation":"full_native_v6_after_exact_configuration_pin_and_derived_hash_normalization"})
		rows.append(row)
	var original_consumer: Variant=bytes_to_var(FileAccess.get_file_as_bytes(Consumer.CATALOG))
	var original_legacy: Variant=bytes_to_var(FileAccess.get_file_as_bytes("res://assets/unified_edit/legacy_source_catalog.variant"))
	var catalog:={"schema":1,"native_sources":known,"inherited_consumer_catalog":original_consumer,"inherited_legacy_catalog":original_legacy}
	var catalog_path:=output.path_join("source_configurations.variant")
	FileAccess.open(catalog_path,FileAccess.WRITE).store_buffer(var_to_bytes(catalog))
	var report:={"scope":"offline source validation and exact Variant configurations; no target migration or runtime restore acceptance","rows":rows,"catalog_path":catalog_path,"catalog_sha256":FileAccess.get_sha256(catalog_path),"engine":Engine.get_version_info(),"probe_sha256":FileAccess.get_sha256(get_script().resource_path)}
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print(JSON.stringify(report));quit(0 if not known.is_empty() else 1)
