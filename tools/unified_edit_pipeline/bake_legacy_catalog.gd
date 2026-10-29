extends SceneTree

# Offline extraction from validated immutable fixture identities. No legacy runtime.
const Legacy=preload("res://scripts/simulation/unified_edit/legacy_sources.gd")
const FIXTURES=["res://test_output/unified_edit_pipeline/g0_function_baseline01/regression_all_tools_1.sandgp","res://test_output/gpu_pipeline/g7_20261017_03/migration.sandcp"]
func _initialize() -> void:
	var rows: Array=[]
	for path in FIXTURES:
		var read:=Legacy._read_file(path)
		if not read.error.is_empty():push_error(read.error);quit(1);return
		rows.append({"format":read.format,"configuration":read.signature,"fixture":{"path":path,"sha256":FileAccess.get_sha256(path)}})
		var old: Dictionary=read.checkpoint
		var native: bool=read.format=="edit5_native3"
		print(JSON.stringify({"format":read.format,"domain":old.domain_id if native else old.shadow.domain_id,"simulation":old.simulation if native else {},"tick":old.sim_tick if native else old.tick,"cohesion":old.cohesion_yield_height_m if native else old.sand_cohesion_yield_height_m,"gravel":old.visual_extensions.gravel_v1.profile_values}))
	var target:="res://assets/unified_edit/legacy_source_catalog.variant"
	if FileAccess.file_exists(target):push_error("catalog already exists");quit(1);return
	FileAccess.open(target,FileAccess.WRITE).store_buffer(var_to_bytes({"schema":1,"sources":rows}))
	print("CATALOG_SHA256 ",FileAccess.get_sha256(target));quit()
