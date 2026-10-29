extends "res://tools/wave_propagation/audit_source_restore.gd"
# Only the independent bytes/checksum reader is inherited; no production Codec.
func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=1:quit(2);return
	var folder: String=args[0];var output:=folder.path_join("independent_native_audit.json")
	if FileAccess.file_exists(output):quit(2);return
	var report: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("diagnosis.json")))
	check("formal_runtime_passed",report.get("pass",false));check("one_formal_case",report.cases.size()==1)
	var pins: Array=report.cases[0].containers
	check("three_native_captures",pins.size()==3)
	for row in pins:check("native_pin:"+row.label,FileAccess.get_sha256(row.path)==row.sha256)
	var before:=read(folder.path_join("before_restore.sandue"),"SANDUE06")
	var after:=read(folder.path_join("after_restore.sandue"),"SANDUE06")
	var final:=read(folder.path_join("final.sandue"),"SANDUE06")
	if not before.is_empty() and not after.is_empty() and not final.is_empty():
		check("new_generation",after.generation>before.generation)
		check("same_complete_configuration",before.configuration==after.configuration)
		for group in ["fields","spare","material","foam","histories"]:check("restored_exact:"+group,before.native[group]==after.native[group])
		var control: PackedByteArray=before.native.control.duplicate();control.encode_s64(8,after.generation)
		check("control_generation_only",control==after.native.control)
		for key in ["state_seq","sim_tick","revision","advanced_time_s","ledger","initial_sand_total_m3","nominal_upper_supply","wave_highwater_id","wave_start_times","wave_requests","simulation"]:check("restored_metadata:"+key,before[key]==after[key])
		var gravel: Dictionary=before.visual_extensions.gravel_v1.duplicate(true)
		if gravel.enabled:gravel.source_generation=after.generation
		check("gravel_raw_generation_only",gravel==after.visual_extensions.gravel_v1)
		check("continued_after_restore",final.advanced_time_s>after.advanced_time_s and final.sim_tick>after.sim_tick and final.revision>after.revision)
		check("final_time",final.advanced_time_s>=report.requested_time_s-.0001)
		for value in [before,after,final]:
			check("native3_slot0",value.native.version==3 and value.native.current_index==0)
			check("actual_MC",value.configuration.environment.water_numerics.solver_id=="muscl_mc_ssprk2_v1")
			for field in ["rock","sand","water","momentum_x","momentum_z","sediment"]:
				var raw: PackedByteArray=value.native.fields[field]
				var valid:=raw.size()==262144
				for amount in raw.to_float32_array():valid=valid and is_finite(amount) and (amount>=0.0 if field in ["sand","water","sediment"] else true)
				check("native_finite:"+str(value.sim_tick)+":"+field,valid)
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"outcome":"fail" if failed else "pass","checks":checks,"auditor_sha256":FileAccess.get_sha256(get_script().resource_path),"scope":"Independent container checksum, raw before-vs-restored state and continued final native. No production Codec/projector import."},"\t"));quit(1 if failed else 0)
