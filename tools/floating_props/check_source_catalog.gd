extends SceneTree
const Codec=preload("res://scripts/simulation/unified_edit/checkpoint_codec.gd")
const Sources=preload("res://scripts/simulation/unified_edit/consumer_checkpoint_sources.gd")
func _initialize() -> void:
	for path in ["res://test_output/floating_props/baseline_20261018_01/baseline.sandue","res://test_output/floating_props/fault_recovery_20261018_02/before_fault.sandue"]:
		var value:=Codec.read_container(path)
		print("SOURCE ",path," ",Codec.Config.validate(value.checkpoint.configuration)," hash ",value.checkpoint.configuration.configuration_hash," actual ",Codec.Config.stable_hash(value.checkpoint.configuration))
		if path.contains("baseline_"):
			FileAccess.open("res://test_output/floating_props/catalog_source_headless.bin",FileAccess.WRITE).store_buffer(var_to_bytes(Codec.Config.canonical(value.checkpoint.configuration)))
			FileAccess.open("res://test_output/floating_props/catalog_source_headless.json",FileAccess.WRITE).store_string(JSON.stringify(Codec.Config.canonical(value.checkpoint.configuration)))
	var catalog: Dictionary=bytes_to_var(FileAccess.get_file_as_bytes(Sources.CATALOG))
	print("CAT_SOURCE ",Codec.Config.validate(catalog.source_configuration)," hash ",catalog.source_configuration.configuration_hash," actual ",Codec.Config.stable_hash(catalog.source_configuration))
	quit()
