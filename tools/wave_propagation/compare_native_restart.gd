extends SceneTree
const Codec=preload("res://scripts/simulation/unified_edit/checkpoint_codec.gd")
var checks: Array=[]
var failed:=false
func check(label: String,okay: bool) -> void:checks.append({"label":label,"pass":okay});failed=failed or not okay;print("COLD_RESTART ",label," ",okay)
func compare(first: Dictionary,second: Dictionary,label: String) -> void:
	for group in ["fields","spare","material","foam","histories"]:check(label+"/native/"+group,first.native[group]==second.native[group])
	var control: PackedByteArray=first.native.control.duplicate();control.encode_s64(8,second.generation)
	check(label+"/control_only_generation_changed",control==second.native.control)
	for field in ["advanced_time_s","state_seq","sim_tick","revision","ledger","initial_sand_total_m3","nominal_upper_supply","wave_requests","wave_start_times","configuration","source_provenance"]:check(label+"/"+field,first[field]==second[field])
	var gravel: Dictionary=first.visual_extensions.gravel_v1.duplicate(true);gravel.source_generation=second.generation
	check(label+"/gravel_only_generation_changed",gravel==second.visual_extensions.gravel_v1)
func _initialize() -> void:
	var folder:=OS.get_cmdline_user_args()[0];var output:=folder.path_join("comparison.json")
	if FileAccess.file_exists(output):quit(2);return
	var input_paths:={"seed":folder.path_join("seed/data/seed.sandue"),"restored":folder.path_join("resume/data/restored.sandue"),"reference":folder.path_join("seed/data/continuation.sandue"),"resumed":folder.path_join("resume/data/continuation.sandue")};var values:={};var hashes:={}
	for key in input_paths:
		var loaded:=Codec.read_container(input_paths[key]);check("read:"+key,loaded.error.is_empty())
		if not loaded.error.is_empty():quit(1);return
		values[key]=loaded.checkpoint;hashes[key]={"path":input_paths[key],"sha256":FileAccess.get_sha256(input_paths[key])}
		check("validate:"+key,Codec.validate(values[key],values[key].configuration,true).is_empty())
	compare(values.seed,values.restored,"cold_initial");compare(values.reference,values.resumed,"cold_continued")
	check("advanced_live_wave",values.reference.advanced_time_s>values.seed.advanced_time_s and values.reference.native.fields.water!=values.seed.native.fields.water)
	check("visuals_enabled",values.seed.configuration.effects.foam_enabled and values.seed.configuration.effects.gravel_enabled)
	check("new_generation",values.restored.generation>values.seed.generation)
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"outcome":"fail" if failed else "pass","checks":checks,"inputs":hashes,"scope":"Separate engine processes; native fields/spare/material/foam/gravel exact, control and gravel metadata change only generation. All files validate with same actual source configuration."},"\t"));quit(1 if failed else 0)
