extends "res://tests/integration/unified_edit_playable_probe.gd"

const Router=preload("res://scripts/simulation/unified_edit/checkpoint_router.gd")
const Baseline="res://test_output/floating_props/baseline_20261018_01/baseline.sandue"

func _write_test_container(path: String, value: Dictionary) -> void:
	var bytes:=var_to_bytes(value);var file:=FileAccess.open(path,FileAccess.WRITE)
	file.store_buffer(Codec.MAGIC.to_ascii_buffer());file.store_32(1);file.store_32(bytes.size());file.store_buffer(Codec.Old.digest(bytes));file.store_buffer(bytes);file.close()

func _run() -> void:
	orphan_baseline=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT));DisplayServer.window_set_size(Vector2i(1280,720))
	scene=load("res://scenes/main.tscn").instantiate();scene.playing=false;root.add_child(scene)
	var deadline:=Time.get_ticks_msec()+90000
	while (scene._booting or not scene.ready_for_ticks) and scene.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check("formal_main_migration_target_ready",not scene._booting and scene.ready_for_ticks)
	if scene._booting:await _close();return
	var props=scene.floating_props;var before: Dictionary=props.saved.duplicate(true);var generation: int=props.generation;var owner: int=props.owner_token
	var raw:=Codec.read_container(Baseline);var file_hash:=FileAccess.get_sha256(Baseline)
	FileAccess.open(output.get_base_dir()+"/source_canonical.bin",FileAccess.WRITE).store_buffer(var_to_bytes(scene.Config.canonical(raw.checkpoint.configuration)))
	FileAccess.open(output.get_base_dir()+"/source_canonical.json",FileAccess.WRITE).store_string(JSON.stringify(scene.Config.canonical(raw.checkpoint.configuration)))
	observations.configuration_diagnostics={"target":scene.Config.validate(scene.configuration,true),"source":scene.Config.validate(raw.checkpoint.configuration),"strict":Codec.load(Baseline,scene.configuration).error,"source_hash":raw.checkpoint.configuration.configuration_hash,"source_actual_hash":scene.Config.stable_hash(raw.checkpoint.configuration),"target_hash":scene.configuration.configuration_hash,"target_actual_hash":scene.Config.stable_hash(scene.configuration)}
	check("strict_codec_rejects_old_configuration",Codec.load(Baseline,scene.configuration).error==&"checkpoint_configuration_mismatch")
	var projected:=Router.load_file(Baseline,scene.configuration)
	check("known_source_projects_without_header_change",projected.error.is_empty() and projected.checkpoint.version==6 and projected.checkpoint.native.version==3)
	if not projected.error.is_empty():observations.migration_error=projected.error;await _close();return
	check("native_fields_ledgers_and_clock_preserved",projected.checkpoint.native==raw.checkpoint.native and projected.checkpoint.ledger==raw.checkpoint.ledger and projected.checkpoint.advanced_time_s==raw.checkpoint.advanced_time_s and projected.checkpoint.state_seq==raw.checkpoint.state_seq)
	check("known_source_provenance_and_target_pinned",projected.checkpoint.configuration==scene.configuration and projected.checkpoint.source_provenance.configuration==raw.checkpoint.configuration and projected.checkpoint.source_provenance.sha256==file_hash and projected.checkpoint.source_provenance.policies.migration=="floating_props_consumer_v3")
	var unknown: Dictionary=raw.checkpoint.duplicate(true);unknown.configuration=scene.configuration.duplicate(true);unknown.configuration.environment.unreviewed_test_source=true;unknown.configuration.configuration_hash=scene.Config.stable_hash(unknown.configuration)
	var unknown_path:=output.get_base_dir()+"/unknown.sandue"
	check("unknown_source_fixture_is_structurally_valid",Codec.save(unknown_path,unknown,unknown.configuration).is_empty())
	check("unknown_native_source_rejected",Router.load_file(unknown_path,scene.configuration).error==&"unknown_native_source_configuration")
	var altered_target: Dictionary=scene.configuration.duplicate(true);altered_target.environment.unreviewed_test_target=true;altered_target.configuration_hash=scene.Config.stable_hash(altered_target)
	check("unreviewed_target_rejected",Router.load_file(Baseline,altered_target).error==&"unreviewed_consumer_target_configuration")
	var altered_data: Dictionary=scene.configuration.duplicate(true);var changed_profile: Dictionary=altered_data.profiles.dig_v1
	changed_profile.defaults.radius_m+=0.125
	var unsigned: Dictionary=changed_profile.duplicate(true);unsigned.erase("profile_hash")
	changed_profile.profile_hash=JSON.stringify(unsigned,"",true).sha256_text();altered_data.configuration_hash=scene.Config.stable_hash(altered_data)
	check("changed_profile_data_target_is_structurally_valid",scene.Config.validate(altered_data,true).is_empty())
	check("changed_declared_profile_data_still_rejected",Router.load_file(Baseline,altered_data).error==&"unreviewed_consumer_target_configuration")
	var cross: Dictionary=raw.checkpoint.duplicate(true);cross.domain_id="test1_capture"
	var cross_path:=output.get_base_dir()+"/cross_domain.sandue";_write_test_container(cross_path,cross)
	check("cross_domain_rejected",Router.load_file(cross_path,scene.configuration).error==&"checkpoint_domain_mismatch")
	var corrupted:=FileAccess.get_file_as_bytes(Baseline);corrupted[corrupted.size()-1]^=1
	var corrupt_path:=output.get_base_dir()+"/corrupted.sandue";FileAccess.open(corrupt_path,FileAccess.WRITE).store_buffer(corrupted)
	check("corrupted_source_rejected",Router.load_file(corrupt_path,scene.configuration).error==&"checksum_mismatch")
	check("rejections_do_not_touch_props",props.generation==generation and props.owner_token==owner and props.saved==before)
	var error: StringName=await scene.restore_gpu_checkpoint(Baseline);observations.restore_error=error
	check("known_source_actual_restore_succeeds",error.is_empty())
	check("migration_resets_props_on_new_generation",props.generation>generation and props.owner_token==owner+1 and props.admitted_time_s==0 and props.actual_time.values().all(func(v):return v==0.0) and props.holds.has(&"user"))
	var save_path:=output.get_base_dir()+"/migrated.sandue"
	# One process notification refreshes ready_for_ticks after the transition.
	await process_frame
	check("migrated_current_checkpoint_can_be_saved",(await scene.save_gpu_checkpoint(save_path)).is_empty())
	var saved:=Codec.load(save_path,scene.configuration)
	check("migration_provenance_survives_next_save",saved.error.is_empty() and saved.checkpoint.source_provenance.policies.migration=="floating_props_consumer_v3")
	check("archival_input_unchanged",FileAccess.get_sha256(Baseline)==file_hash and file_hash=="9c8a637e4ea9536b605201908b17484367b5c91c3522d041d5175f8160c9f38f")
	observations.sources=scene.configuration.sources.duplicate(true);observations.provenance=projected.checkpoint.source_provenance
	await _close()

func finish() -> void:
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"checks":checks,"observations":observations,"scope":"G5 exact known native-v6 source migration, current target source pinning, raw-field preservation, negative inputs and real main restore/save. No broad old-source compatibility."},"\t"));quit(1 if failed else 0)
