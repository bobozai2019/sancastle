extends SceneTree
# Schema fixtures, never replacements for missing originals. Native seed bytes
# come from the immutable G0 capture; identities/time are explicit test values.
const Codec=preload("res://scripts/simulation/unified_edit/checkpoint_codec.gd")
const Router=preload("res://scripts/simulation/unified_edit/checkpoint_router.gd")
const N=Router.NumericsSources
const Domain=preload("res://scripts/simulation/sand_water_domain.gd")
const SEED="D:/godot/project/sandcastle/test_output/wave_propagation/g0_main_isolated_02/main_initial.sandue"
const SEED_SHA="1d32d93f43b96cbd959cae9523167ffc787a6acf2c036eac0eb166fce6976330"
var output:=""
var checks: Array=[]
var rows: Array=[]
var failed:=false
func check(label: String,okay: bool,detail: String="") -> void:
	checks.append({"label":label,"pass":okay,"detail":detail});failed=failed or not okay;print("REBUILT_FIXTURE ",label," ",okay," ",detail)
func envelope(path: String,magic: String,value: Dictionary) -> void:
	var payload:=var_to_bytes(value);var file:=FileAccess.open(path,FileAccess.WRITE)
	file.store_buffer(magic.to_ascii_buffer());file.store_32(1);file.store_32(payload.size());file.store_buffer(Codec.Old.digest(payload));file.store_buffer(payload);file.flush();file.close()
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	if output.is_empty() or DirAccess.dir_exists_absolute(output):quit(2);return
	DirAccess.make_dir_recursive_absolute(output)
	check("immutable_native_seed",FileAccess.get_sha256(SEED)==SEED_SHA)
	var loaded:=Codec.read_container(SEED)
	check("seed_container",loaded.error.is_empty())
	if failed:finish();return
	var seed: Dictionary=loaded.checkpoint
	seed.generation=1001;seed.state_seq=4;seed.sim_tick=3;seed.revision=7;seed.advanced_time_s=PackedFloat32Array([.1])[0]
	for pair in [[8,seed.generation],[16,seed.state_seq],[24,seed.sim_tick],[40,seed.revision]]:seed.native.control.encode_s64(pair[0],pair[1])
	seed.native.control.encode_float(32,seed.advanced_time_s)
	if seed.visual_extensions.gravel_v1.enabled:
		seed.visual_extensions.gravel_v1.tick=seed.sim_tick;seed.visual_extensions.gravel_v1.revision=seed.revision;seed.visual_extensions.gravel_v1.source_generation=seed.generation
	var trust:=Router.Legacy.new();check("fixed_legacy_catalog",trust.initialize_catalog(Router.CATALOG,Router.CATALOG_SHA256).is_empty())
	var catalog: Dictionary=bytes_to_var(FileAccess.get_file_as_bytes(Router.CATALOG))
	for known in catalog.sources:
		var path:=output.path_join("rebuilt_"+known.format+(".sandgp" if known.format=="edit5_native3" else ".sandcp"))
		var value:=seed.duplicate(true)
		var error: StringName
		if known.format=="edit5_native3":
			value.erase("protocol_family");value.erase("source_provenance");value.version=5;value.configuration=known.configuration.duplicate(true);value.ledger_precision="approximate"
			error=Codec.Old.save(path,value)
		else:
			var domain:=Domain.new(256,.125);domain.domain_id=&"main_beach";domain.generation=seed.generation;domain.sim_tick=seed.sim_tick
			for name in ["rock","sand","water","sediment"]:domain.set(name,seed.native.fields[name].to_float32_array())
			for name in ["wetness","compaction"]:domain.set(name,Codec.UnitHalf.decode(seed.native.fields[name]).value)
			var obstacles:=PackedFloat32Array();obstacles.resize(65536)
			for i in 65536:obstacles[i]=float(seed.native.fields.obstacle[i])/255.0
			domain.obstacle=obstacles
			for key in seed.ledger:domain.set(key,seed.ledger[key])
			var native: Dictionary=seed.native.duplicate(true);native.erase("control");native.erase("histories");native.version=2
			var selection: Dictionary=seed.selection.duplicate(true);selection.sand_accounting="external_v1"
			value={"tick":seed.sim_tick,"preset_index":0,"highwater_id":0,"revision":seed.revision,"command_ids":PackedInt32Array(),"fields":{},"shadow":domain.snapshot(),"water_source_m3":seed.ledger.water_source_m3,"water_sink_m3":seed.ledger.water_sink_m3,"fixture_id":&"","structures":{},"enable_structures":false,"sand_cohesion_yield_height_m":seed.cohesion_yield_height_m,"wave_requests":[],"wave_highwater_id":0,"foam_history":native.foam["foam_%d"%native.foam.current_index].to_float32_array(),"gpu_beach_native":native,"gpu_beach_edit":{"version":4,"brush_schema":2,"configuration":known.configuration.duplicate(true),"prefix":[],"ledger":seed.ledger.duplicate(true),"selection":selection,"pending_count":0,"reserved_m3":0.0},"visual_extensions":seed.visual_extensions.duplicate(true),"local_front_history":seed.native.histories.get("local_front",PackedByteArray()).to_float32_array()}
			for name in ["water","momentum_x","momentum_z"]:value.fields[name]=native.fields[name].to_float32_array()
			error=Router.Legacy.Store.save(path,value,[],true)
		check("save_real_format:"+known.format,error.is_empty(),String(error))
		if not error.is_empty():continue
		var inspected:=trust.inspect_file(path);check("full_legacy_validation:"+known.format,inspected.error.is_empty(),String(inspected.error))
		rows.append({"format":known.format,"path":path,"sha256":FileAccess.get_sha256(path),"origin":"reconstructed_schema_fixture_not_original","original_fixture":known.fixture,"source_configuration_digest":Codec.Config.digest_data(known.configuration)})
	var native_catalog:=N._load_catalog()
	check("native_catalog",native_catalog.error.is_empty())
	if native_catalog.error.is_empty():
		for known in native_catalog.catalog.native_sources:
			if FileAccess.file_exists(known.fixture.path):continue
			var value:=seed.duplicate(true);value.configuration=known.configuration.duplicate(true)
			var error:=Codec.validate_pinned_source(value,known.configuration);check("rebuilt_native_source_full_validation",error.is_empty(),String(error))
			if not error.is_empty():continue
			var path:=output.path_join("rebuilt_consumer_native6.sandue");envelope(path,Codec.MAGIC,value)
			rows.append({"format":"native_v6","path":path,"sha256":FileAccess.get_sha256(path),"origin":"reconstructed_schema_fixture_not_original","original_fixture":known.fixture,"source_configuration_digest":Codec.Config.digest_data(known.configuration)})
	finish()
func finish() -> void:
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"outcome":"fail" if failed else "pass","checks":checks,"fixtures":rows,"seed":{"path":SEED,"sha256":SEED_SHA},"construction":"G0 raw native seed; synthesized generation1001/state_seq4/tick3/revision7/time0.1 and format envelopes. No original legacy simulation or command history recovered.","scope":"Reconstructed format fixtures under original complete source allowlists, not original missing files or GPU restore acceptance"},"\t"));quit(1 if failed else 0)
