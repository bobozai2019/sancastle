extends SceneTree

const Codec=preload("res://scripts/simulation/unified_edit/checkpoint_codec.gd")
const Sources=preload("res://scripts/simulation/unified_edit/consumer_checkpoint_sources.gd")
const BASELINE="res://test_output/floating_props/baseline_20261018_01/baseline.sandue"
const BASELINE_HASH="9c8a637e4ea9536b605201908b17484367b5c91c3522d041d5175f8160c9f38f"
const REVIEWED_TOOL_MODEL_SHA="8d5f10e0150f208653087daeebb16ac561a85ba72e426317af16f0214e6099af"
var current_path:=""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--current="):current_path=arg.trim_prefix("--current=")
	if FileAccess.get_sha256(BASELINE)!=BASELINE_HASH:push_error("baseline_identity_changed");quit(1);return
	var old:=Codec.read_container(BASELINE);var current:=Codec.read_container(current_path)
	if not old.error.is_empty() or not current.error.is_empty():push_error("invalid_source_container");quit(1);return
	var validated: Dictionary=old.checkpoint.duplicate(true)
	validated.configuration.configuration_hash=Codec.Config.stable_hash(validated.configuration)
	var error:=Codec.validate(validated,validated.configuration,false)
	if not error.is_empty():push_error(error);quit(1);return
	var target: Dictionary=current.checkpoint.configuration.duplicate(true)
	if FileAccess.get_sha256("res://scripts/simulation/unified_edit/tool_profile.gd")!=REVIEWED_TOOL_MODEL_SHA:push_error("unreviewed_tool_model_source");quit(1);return
	var registry: Dictionary=load("res://assets/unified_edit/default_catalog.tres").instantiate_registry()
	if not registry.error.is_empty():push_error(registry.error);quit(1);return
	target.profiles=registry.registry.catalog_snapshot()
	if Sources.parameters(old.checkpoint.configuration)!=Sources.parameters(target):push_error("non_source_semantics_changed");quit(1);return
	var hashes:={}
	for path in target.sources:
		if path in Sources.SOURCES:continue
		if not FileAccess.file_exists(path):push_error("missing_target_source:"+path);quit(1);return
		hashes[path]=FileAccess.get_sha256(path)
	var proof_path:="res://test_output/packed_parallel_20261018/pairs_final/probe.json"
	var proof: Variant=JSON.parse_string(FileAccess.get_file_as_string(proof_path))
	if not proof is Dictionary or not proof.get("pass",false):push_error("missing_authority_equivalence_evidence");quit(1);return
	var archive:=ZIPReader.new();var authority_hashes:={}
	if archive.open("res://test_output/packed_parallel_20261018/final_sources.zip")!=OK:push_error("missing_authority_source_archive");quit(1);return
	for path in ["scripts/simulation/unified_edit/water_packed_parallel.glsl","scripts/simulation/unified_edit/water_packed_topology.glsl"]:
		var hash: String=Codec.Old.digest(archive.read_file(path)).hex_encode()
		if FileAccess.get_sha256("res://"+path)!=hash:push_error("unreviewed_authority_source:"+path);quit(1);return
		authority_hashes["res://"+path]=hash
	archive.close()
	var velocity_proof_path:="res://test_output/velocity_prepare_parallel_20261018/verification.json"
	var velocity_proof: Variant=JSON.parse_string(FileAccess.get_file_as_string(velocity_proof_path))
	if not velocity_proof is Dictionary or not velocity_proof.get("pass_targeted_validation",false):push_error("missing_velocity_equivalence_evidence");quit(1);return
	for item in velocity_proof.numerical_checks.values():
		var evidence: String="res://test_output/velocity_prepare_parallel_20261018/"+item.path
		if not item.pass or FileAccess.get_sha256(evidence)!=item.sha256:push_error("velocity_evidence_identity");quit(1);return
	if archive.open("res://test_output/velocity_prepare_parallel_20261018/final_sources.zip")!=OK:push_error("missing_velocity_source_archive");quit(1);return
	for path in ["scripts/simulation/unified_edit/water_response.gd","scripts/simulation/unified_edit/water_velocity_prepare.glsl"]:
		var hash: String=Codec.Old.digest(archive.read_file(path)).hex_encode()
		if FileAccess.get_sha256("res://"+path)!=hash:push_error("unreviewed_velocity_source:"+path);quit(1);return
		authority_hashes["res://"+path]=hash
	archive.close()
	var catalog:={"schema":2,"id":"floating_props_consumer_v2","source_configuration":old.checkpoint.configuration,"fixture":{"path":BASELINE,"sha256":BASELINE_HASH},"target_sources":hashes,"target_parameters":Sources.parameters(target),"review":{"scope":"read-only probes, collision consumer, authored props and lifecycle; native-v3 field schema unchanged","tool_model":{"target_sha256":REVIEWED_TOOL_MODEL_SHA,"change":"Shared drainage-toggle task expands only policy2 speed admission; existing default policy3 and every declared profile value remain identical. Rebind derived model/profile identities under exact release-source pinning."},"authority_equivalence":{"path":proof_path,"sha256":FileAccess.get_sha256(proof_path),"products":authority_hashes},"report":"res://docs/湿区排水并行优化.md","note":"Target packed products matched final_sources.zip; every other changed authority/consumer source reviewed in C05/G6 reports. Regenerate only after explicit source review."}}
	catalog.review.velocity_equivalence={"path":velocity_proof_path,"sha256":FileAccess.get_sha256(velocity_proof_path),"checks":velocity_proof.numerical_check_count,"note":"Shared policy2 initialization optimization; exact product hashes match final archive and390 numerical/negative checks. Policy3 path unchanged."}
	FileAccess.open(Sources.CATALOG,FileAccess.WRITE).store_buffer(var_to_bytes(catalog))
	print("CATALOG_SHA256 ",FileAccess.get_sha256(Sources.CATALOG));quit()
