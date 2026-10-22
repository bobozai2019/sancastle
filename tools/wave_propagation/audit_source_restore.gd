extends SceneTree
# Independent container/raw audit. Deliberately imports no Codec or projector.
var checks: Array=[]
var failed:=false
func check(label: String,okay: bool) -> void:checks.append({"label":label,"pass":okay});failed=failed or not okay
func sha(raw: PackedByteArray) -> PackedByteArray:
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(raw);return hash.finish()
func read(path: String,magic: String) -> Dictionary:
	var raw:=FileAccess.get_file_as_bytes(path)
	check(path+"/header",raw.size()>=48 and raw.slice(0,8).get_string_from_ascii()==magic and raw.decode_u32(8)==1 and raw.decode_u32(12)==raw.size()-48)
	if raw.size()<48:return {}
	check(path+"/checksum",sha(raw.slice(48))==raw.slice(16,48))
	var value: Variant=bytes_to_var(raw.slice(48));check(path+"/dictionary",value is Dictionary)
	return value if value is Dictionary else {}
func leaf(value: Dictionary,path: String) -> Variant:
	var current: Variant=value
	for key in path.split("/"):
		if not current is Dictionary or not current.has(key):return null
		current=current[key]
	return current
func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size() not in [1,2]:quit(2);return
	var folder:=args[0];var expected_count:=7 if args.size()==1 else args[1].to_int()
	if expected_count<1 or expected_count>16:quit(2);return
	var output:=folder.path_join("independent_audit.json" if args.size()==1 else "independent_audit_release.json")
	if FileAccess.file_exists(output):quit(2);return
	var report: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("probe.json")))
	check("runtime_probe_passed",report.get("pass",false));check("externally_fixed_source_count",report.observations.migrations.size()==expected_count)
	for i in report.observations.migrations.size():
		var row: Dictionary=report.observations.migrations[i];var format: String=row.source.get("format","native_v6")
		var magic: String="SANDCP01" if format=="edit4_native2" else ("SANDGP05" if format=="edit5_native3" else "SANDUE06")
		check("source_pin:"+str(i),FileAccess.get_sha256(row.source.path)==row.source.sha256)
		check("saved_pin:"+str(i),FileAccess.get_sha256(row.saved.path)==row.saved.sha256)
		var source:=read(row.source.path,magic);var actual:=read(row.saved.path,"SANDUE06")
		if format=="edit4_native2":source=source.checkpoint
		var original: Dictionary=source.gpu_beach_native if format=="edit4_native2" else source.native
		var source_configuration: Dictionary=source.gpu_beach_edit.configuration if format=="edit4_native2" else source.configuration
		for group in ["fields","spare","material","foam"]:check("input_raw_%d/%s"%[i,group],actual.native[group]==original[group])
		check("native_layout:"+str(i),actual.native.version==3 and actual.native.current_index==0)
		check("saved_actual_mc:"+str(i),actual.configuration.environment.water_numerics.solver_id=="muscl_mc_ssprk2_v1")
		check("original_configuration:"+str(i),actual.source_provenance.configuration==source_configuration)
		check("real_input_provenance_sha:"+str(i),actual.source_provenance.sha256==row.source.sha256)
		var gravel: Dictionary=source.visual_extensions.gravel_v1.duplicate(true)
		if gravel.enabled:gravel.source_generation=actual.generation
		check("input_gravel_raw:"+str(i),actual.visual_extensions.gravel_v1==gravel)
		if format=="edit4_native2":
			check("input_ledger:"+str(i),actual.ledger==source.gpu_beach_edit.ledger)
			check("input_tick_revision:"+str(i),actual.sim_tick==source.tick and actual.revision==source.revision)
			check("explicit_old_clock:"+str(i),actual.advanced_time_s==PackedFloat32Array([float(source.tick)/30.0])[0] and actual.state_seq==0)
			check("input_prefix:"+str(i),actual.source_provenance.original_prefix==source.gpu_beach_edit.prefix)
			if actual.simulation.local_front_history:check("input_local_front:"+str(i),actual.native.histories.local_front==source.local_front_history.to_byte_array())
			var control:=PackedByteArray();control.resize(128);control.encode_u32(0,1);control.encode_s64(8,actual.generation);control.encode_s64(24,source.tick);control.encode_float(32,PackedFloat32Array([float(source.tick)/30.0])[0]);control.encode_s64(40,source.revision)
			check("explicit_old_control:"+str(i),actual.native.control==control)
		else:
			check("input_histories:"+str(i),actual.native.histories==original.histories)
			var control: PackedByteArray=original.control.duplicate();control.encode_s64(8,actual.generation)
			check("input_control_only_generation:"+str(i),actual.native.control==control)
			for key in ["state_seq","sim_tick","revision","advanced_time_s","ledger","initial_sand_total_m3","nominal_upper_supply"]:check("input_metadata_%d/%s"%[i,key],actual[key]==source[key])
		if format=="native_v6":
			check("parent_provenance:"+str(i),actual.source_provenance.policies.parent_provenance==source.source_provenance)
			for change in actual.source_provenance.policies.parameter_changes:
				check("explicit_parameter_mapping:%d/%s"%[i,change.path],leaf(source_configuration,change.path)==change.from and leaf(actual.configuration,change.path)==change.to)
		check("reconstruction_identity_present:"+str(i),row.source.has("origin") and row.source.origin in ["original_available","reconstructed_schema_fixture_not_original"])
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"outcome":"fail" if failed else "pass","checks":checks,"auditor_sha256":FileAccess.get_sha256(get_script().resource_path),"scope":"Independent exact input-vs-GPU-resave comparison, not a second call to the production projection"},"\t"));print("INDEPENDENT_SOURCE_AUDIT ",not failed," checks=",checks.size());quit(1 if failed else 0)
