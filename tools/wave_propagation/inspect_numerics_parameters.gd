extends SceneTree
const N=preload("res://scripts/simulation/unified_edit/numerics_checkpoint_sources.gd")
func _initialize() -> void:
	var output:=OS.get_cmdline_user_args()[0]
	var catalog: Dictionary=bytes_to_var(FileAccess.get_file_as_bytes(N.CATALOG))
	var sources: Array=[];var targets: Array=[]
	for row in catalog.native_sources:sources.append({"fixture":row.fixture,"parameters":N.parameters(row.configuration),"mappings":row.mappings})
	for row in catalog.targets:targets.append({"strict":row.parameters,"consumer":row.consumer_parameters})
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"sources":sources,"targets":targets},"\t"));quit()
