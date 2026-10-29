extends SceneTree
# Independent actual-file audit, without production codecs or projection.
var checks: Array=[]
var failed:=false
func check(label: String,okay: bool) -> void:checks.append({"label":label,"pass":okay});failed=failed or not okay
func read(path: String) -> Dictionary:
	var raw:=FileAccess.get_file_as_bytes(path);var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(raw.slice(48))
	check(path+"/container",raw.size()>48 and raw.slice(0,8).get_string_from_ascii()=="SANDUE06" and raw.decode_u32(8)==1 and raw.decode_u32(12)==raw.size()-48 and hash.finish()==raw.slice(16,48))
	return bytes_to_var(raw.slice(48))
func _initialize() -> void:
	var folder:=OS.get_cmdline_user_args()[0];var output:=folder.path_join("independent_audit.json")
	if FileAccess.file_exists(output):quit(2);return
	var report: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("probe.json")));check("runtime_dispatch_and_io_passed",report.get("pass",false))
	var values:={}
	for label in report.files:
		check("file_identity:"+label,FileAccess.get_sha256(report.files[label].path)==report.files[label].sha256);values[label]=read(report.files[label].path)
	for pair in [["fo_source","fo_to_mc","rusanov_first_order_v1","muscl_mc_ssprk2_v1"],["mc_source","mc_to_fo","muscl_mc_ssprk2_v1","rusanov_first_order_v1"]]:
		var source: Dictionary=values[pair[0]];var actual: Dictionary=values[pair[1]]
		check(pair[1]+"/algorithm",source.configuration.environment.water_numerics.solver_id==pair[2] and actual.configuration.environment.water_numerics.solver_id==pair[3] and source.configuration.sources==actual.configuration.sources)
		for group in ["fields","spare","material","foam","histories"]:check(pair[1]+"/raw/"+group,source.native[group]==actual.native[group])
		var control: PackedByteArray=source.native.control.duplicate();control.encode_s64(8,actual.generation);check(pair[1]+"/control",control==actual.native.control)
		for key in ["state_seq","sim_tick","revision","advanced_time_s","ledger","initial_sand_total_m3"]:check(pair[1]+"/"+key,source[key]==actual[key])
		var gravel: Dictionary=source.visual_extensions.gravel_v1.duplicate(true);gravel.source_generation=actual.generation;check(pair[1]+"/gravel",gravel==actual.visual_extensions.gravel_v1)
		check(pair[1]+"/source_and_parent",actual.source_provenance.configuration==source.configuration and actual.source_provenance.policies.parent_provenance==source.source_provenance and actual.source_provenance.sha256==report.files[pair[0]].sha256)
	check("both_future_algorithms_advanced",values.mc_source.advanced_time_s>values.fo_to_mc.advanced_time_s and values.fo_continued.advanced_time_s>values.mc_to_fo.advanced_time_s)
	# Information for the next task: compare actual formal-entry initialization
	# to G0, before any experience candidate measurement or point selection.
	var seed:=read("D:/godot/project/sandcastle/test_output/wave_propagation/g0_main_isolated_02/main_initial.sandue")
	var current:=read("D:/godot/project/sandcastle/test_output/wave_propagation/g4_service_matrix_03/candidate_failure_main/baseline.sandue")
	var changed: Array=[]
	for field in seed.native.fields:
		if seed.native.fields[field]!=current.native.fields[field]:changed.append(field)
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"outcome":"fail" if failed else "pass","checks":checks,"auditor_sha256":FileAccess.get_sha256(get_script().resource_path),"formal_initialization_vs_g0":{"changed_fields":changed,"same_all_ten_native_fields":changed.is_empty(),"scope":"Information for G5 common initial state; no experience acceptance"},"scope":"Independent real-file MC/FO switch raw fields/clock/ledger/provenance audit"},"\t"));print("ALGORITHM_SWITCH_AUDIT ",not failed," changed_initial_fields=",changed);quit(1 if failed else 0)
