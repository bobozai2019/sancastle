extends SceneTree

# Offline release tool. Only the reviewed UI/consumer changes below may differ
# from the exact pre-interaction checkpoint; authority hashes stay byte-identical.
const Codec=preload("res://scripts/simulation/unified_edit/checkpoint_codec.gd")
const Sources=preload("res://scripts/simulation/unified_edit/consumer_checkpoint_sources.gd")
const ROOT="C:/Users/18205/.codex/visualizations/2026/10/18/01a14e1b-fc32-7803-a274-45d1b75ee085/prop_placement_20261019/"
const BASELINE=ROOT+"baseline_03/baseline.sandue"
const BASELINE_SHA="3ec5a12635623f396ee0d4a26ccbf46309695f18c9aeec9d99d87109b41b80ed"
const PREVIOUS_CATALOG=ROOT+"catalog_before.variant"
const PREVIOUS_SHA="ee2c2b862101110c323e0280bb2b97a2a2e345dddbfb3b08a4d7ee61b84c9991"
const ALLOWED=["res://scripts/beach/unified_playable_entry.gd","res://scripts/beach/floating_props_panel.gd","res://scripts/props/floating_props_service.gd","res://scripts/props/floating_prop.gd","res://scenes/main.tscn","res://scenes/components/floating_props.tscn","res://scenes/components/floating_props_panel.tscn"]
var current_path:=""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--current="):current_path=arg.trim_prefix("--current=")
	if FileAccess.get_sha256(BASELINE)!=BASELINE_SHA or FileAccess.get_sha256(PREVIOUS_CATALOG)!=PREVIOUS_SHA:push_error("source_identity");quit(1);return
	var old:=Codec.read_container(BASELINE);var current:=Codec.read_container(current_path)
	if not old.error.is_empty() or not current.error.is_empty():push_error("source_container");quit(1);return
	var catalog: Dictionary=bytes_to_var(FileAccess.get_file_as_bytes(PREVIOUS_CATALOG))
	var target: Dictionary=current.checkpoint.configuration.duplicate(true)
	var previous_sources: Dictionary=old.checkpoint.configuration.sources.duplicate()
	for path in Sources.SOURCES:previous_sources.erase(path)
	if previous_sources!=catalog.target_sources or Sources.parameters(target)!=Sources.parameters(old.checkpoint.configuration):push_error("unreviewed_prior_release_or_parameter_change");quit(1);return
	var hashes:={};var changed: Array=[]
	for path in target.sources:
		if path in Sources.SOURCES:continue
		var hash:=FileAccess.get_sha256(path)
		if hash.is_empty():push_error("missing_source:"+path);quit(1);return
		hashes[path]=hash
		if previous_sources.get(path)!=hash:
			if path not in ALLOWED:push_error("unreviewed_change:"+path);quit(1);return
			changed.append(path)
	for path in previous_sources:
		if not hashes.has(path):push_error("removed_source:"+path);quit(1);return
	catalog.schema=3;catalog.id="floating_props_consumer_v3"
	catalog.additional_sources=[{"configuration":old.checkpoint.configuration,"fixture":{"path":BASELINE,"sha256":BASELINE_SHA}}]
	catalog.target_sources=hashes;catalog.target_parameters=Sources.parameters(target)
	catalog.review.placement={"date":"2026-10-19","scope":"Three authored slots, consumer-only pickup/placement, new pose observation epochs; native-v3 and all authority products unchanged","changed":changed,"baseline_sha256":BASELINE_SHA,"previous_catalog_sha256":PREVIOUS_SHA}
	FileAccess.open(Sources.CATALOG,FileAccess.WRITE).store_buffer(var_to_bytes(catalog))
	print("PLACEMENT_CATALOG ",FileAccess.get_sha256(Sources.CATALOG)," changed=",changed.size());quit()
