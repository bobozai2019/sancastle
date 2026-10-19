extends "res://tests/floating_props/lifecycle_probe.gd"

const Router=preload("res://scripts/simulation/unified_edit/checkpoint_router.gd")
const Known=preload("res://scripts/simulation/unified_edit/consumer_checkpoint_sources.gd")
const BASELINE="C:/Users/18205/.codex/visualizations/2026/10/18/01a14e1b-fc32-7803-a274-45d1b75ee085/prop_placement_20261019/baseline_03/baseline.sandue"

func _run() -> void:
	orphan_baseline=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	scene=load("res://scenes/main.tscn").instantiate();scene.playing=false;root.add_child(scene);props=scene.get_node("FloatingProps/Service")
	var deadline:=Time.get_ticks_msec()+90000
	while scene._booting and Time.get_ticks_msec()<deadline:await process_frame
	await _wait_paused()
	var original:=Codec.read_container(BASELINE)
	var loaded:=Router.load_file(BASELINE,scene.configuration)
	check("reviewed_previous_release_migrates",loaded.error.is_empty())
	if not loaded.error.is_empty():observations.error=loaded.error;await _close();return
	check("all_native_bytes_preserved",loaded.checkpoint.native==original.checkpoint.native)
	check("ledger_and_actual_time_preserved",loaded.checkpoint.ledger==original.checkpoint.ledger and loaded.checkpoint.advanced_time_s==original.checkpoint.advanced_time_s)
	check("previous_release_fixture_pinned",loaded.checkpoint.source_provenance.trusted_fixture.sha256==FileAccess.get_sha256(BASELINE) and loaded.checkpoint.source_provenance.policies.migration=="floating_props_consumer_v3")
	var unknown: Dictionary=original.checkpoint.duplicate(true)
	unknown.configuration.environment.unreviewed_ui_change=true;unknown.configuration.configuration_hash=scene.Config.stable_hash(unknown.configuration)
	check("unregistered_configuration_rejected",Known.project(unknown,scene.configuration,BASELINE).error==&"unknown_native_source_configuration")
	check("previous_release_restore",(await scene.restore_gpu_checkpoint(BASELINE)).is_empty())
	check("restore_has_authored_three",props.world_registry().size()==3 and props.last_error.is_empty())
	await _close()
