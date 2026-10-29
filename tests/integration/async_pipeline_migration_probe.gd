extends "res://tests/integration/async_pipeline_restore_probe.gd"

const Migration=preload("res://scripts/simulation/edit_validation/frame_pipeline/async_legacy_migration.gd")
const LegacyStore=preload("res://scripts/simulation/checkpoint_store.gd")

func legacy_idle() -> bool:
	var deadline:=Time.get_ticks_msec()+60000
	while Time.get_ticks_msec()<deadline and preview.last_error.is_empty():
		if not preview.busy and not preview.input_running and not preview.input_scheduler.pumping and preview.command_queue.pending.is_empty() and not preview.gravel_drop_pending and not preview.collision_proxy.staging_texture.is_valid() and preview.collision_proxy.pending_revisions.is_empty() and not preview.collision_proxy.has_prepare_in_flight():return true
		await process_frame
	return false

func start_scene(enabled: bool) -> bool:
	preview=load(scene_path).instantiate()
	preview.async_pipeline_enabled=enabled;preview.playing=false
	root.add_child(preview)
	var deadline:=Time.get_ticks_msec()+60000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	return preview.ready_for_ticks and preview.last_error.is_empty()

func dispose_scene() -> void:
	await preview.get_node("Interface/PerformancePanel").stop_sampling()
	await preview.shutdown()
	check("migration_scene_released",preview.gpu_release_done and preview.solver.rd==null and preview.collision_proxy.rd==null)
	preview.queue_free();await process_frame;await RenderingServer.frame_post_draw;await process_frame

func _run() -> void:
	var base:=output.get_basename()
	check("migration_real_old_scene_ready",await start_scene(false))
	var source_sha:=""
	var old:={}
	var old_boundary:=false
	var next_wave:=0.0
	if preview.ready_for_ticks:
		check("migration_old_idle",await legacy_idle())
		for i in 2:
			var result: Dictionary=await preview.apply_gpu_command(command(1300+i,Vector3(-2,0,0),i==0))
			check("migration_real_old_edit_%d"%i,result.get("status")==1)
			check("migration_old_edit_settled_%d"%i,await legacy_idle())
		check("migration_real_old_shape_begin",(await preview.begin_shape_stroke(901)).is_empty())
		var brush:=Brush.make_command(&"wall_v1",{"height_m":0.2,"bottom_width_m":1.0,"top_width_m":0.5},Vector2(-2,-0.25),Vector2(-2,0.25),preview.domain.domain_id,preview.generation,preview.command_queue.last_command_id+1,901,0,preview.completed_ticks,preview.shape_baseline_token)
		brush.material_profile_id=&"molded_v1"
		check("migration_real_old_shape_admission",preview.input_scheduler.submit(brush).is_empty())
		preview.input_running=true;preview.call_deferred("_drain_input")
		check("migration_real_old_shape_complete",await legacy_idle())
		check("migration_real_old_shape_end",(await preview.end_shape_stroke()).is_empty())
		check("migration_real_old_gravel",(await preview.drop_gravel(Vector2(1,1),2)).get("active_count")==514)
		preview._start_tick()
		var deadline:=Time.get_ticks_msec()+60000
		while preview.completed_ticks<1 and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
		check("migration_real_old_water",preview.completed_ticks==1 and await legacy_idle())
		old_boundary=preview.solver.prescribed_tide_boundary
		check("migration_real_old_wave_admitted",preview.request_wave({"domain_id":preview.domain.domain_id,"generation":preview.generation,"request_id":preview.wave_highwater_id+1,"start_tick":preview.completed_ticks+1,"profile_id":&"test_packet","amplitude_m":0.08,"duration_s":2.0,"seed":91}).ok)
		next_wave=preview._wave_height_at_tick(preview.completed_ticks+1)
		check("migration_wave_fixture_nonzero",next_wave>0.0)
		preview._apply_brush_selection({"tool":"wall_v1","parameters":{"height_m":0.2,"bottom_width_m":1.0,"top_width_m":0.5},"dig_amount_m3":0.03,"fill_amount_m3":0.04})
		check("migration_real_old_save",(await preview.save_gpu_checkpoint(base+".sandcp")).is_empty())
		var loaded:=LegacyStore.load(base+".sandcp")
		check("migration_original_decoder_load",loaded.error.is_empty())
		if loaded.error.is_empty():
			old=loaded.checkpoint
			check("migration_real_old_versions",old.gpu_beach_edit.version==4 and old.gpu_beach_native.version==2 and old.gpu_beach_edit.prefix.size()>=3)
			check("migration_real_old_material",old.gpu_beach_native.material.ever_used and old.visual_extensions.gravel_v1.active_count==514)
			source_sha=FileAccess.get_sha256(base+".sandcp")
	await dispose_scene()
	check("migration_new_scene_ready",await start_scene(true))
	if preview.ready_for_ticks and not old.is_empty():
		var migrated:=Migration.convert(preview,old)
		check("migration_old_full_validation",migrated.error.is_empty())
		if not migrated.error.is_empty():print("MIGRATION_ERROR ",migrated.error)
		if migrated.error.is_empty():
			var fresh: Dictionary=migrated.checkpoint
			check("migration_configuration_only_mode_diff",old.gpu_beach_edit.configuration==Migration.legacy_configuration(preview.source_signature))
			check("migration_new_versions",fresh.version==5 and fresh.native.version==3 and fresh.ledger_precision=="approximate")
			check("migration_boundary_matches_observed_old",fresh.simulation.prescribed_tide_boundary==old_boundary)
			check("migration_no_fake_prefix",not fresh.has("prefix") and not fresh.has("gpu_beach_edit") and fresh.state_seq==0 and fresh.native.control.decode_u32(72)==0 and fresh.native.control.decode_u32(76)==0)
			var bad:=old.duplicate(true);bad.gpu_beach_edit.version=99
			check("migration_unknown_version_rejected",not Migration.convert(preview,bad).error.is_empty())
			bad=old.duplicate(true);bad.gpu_beach_edit.configuration.engine_executable_sha256="0".repeat(64)
			check("migration_signature_mismatch_rejected",not Migration.convert(preview,bad).error.is_empty())
			bad=old.duplicate(true);bad.gpu_beach_edit.prefix[0].receipt_raw[0]^=1
			check("migration_raw_receipt_corruption_rejected",not Migration.convert(preview,bad).error.is_empty())
			bad=old.duplicate(true);bad.gpu_beach_edit.ledger.sand_source_m3+=1.0
			check("migration_exact_old_ledger_still_required",not Migration.convert(preview,bad).error.is_empty())
			var original_solver=preview.solver
			check("migration_bad_api_rejects",not (await preview.restore_gpu_checkpoint_data(bad)).is_empty())
			check("migration_bad_keeps_active",preview.solver==original_solver and preview.generation==1 and preview.input_scheduler.accepting and preview.ready_for_ticks)
			var historical:="res://test_output/gravel_drop_20261016_v2/"+("test1_backwash" if scene_path.ends_with("test1_backwash.tscn") else "main")+".sandcp"
			check("migration_historical_fixture_available",FileAccess.file_exists(historical))
			var historical_error: StringName=await preview.restore_gpu_checkpoint(historical)
			check("migration_incompatible_historical_rejected",not historical_error.is_empty())
			check("migration_historical_keeps_active",preview.solver==original_solver and preview.generation==1 and preview.input_scheduler.accepting and preview.ready_for_ticks)
			var error: StringName=await preview.restore_gpu_checkpoint(base+".sandcp")
			check("migration_public_old_file_restore",error.is_empty())
			if not error.is_empty():print("MIGRATION_RESTORE_ERROR ",error)
			if error.is_empty():
				var restored:=await capture("migration_capture_restored")
				same_native("migration_exact",fresh,restored,true)
				check("migration_real_collision",collision_matches(fresh))
				check("migration_no_replay_retained",preview.gpu_prefix.is_empty() and preview.command_queue.applied_log.is_empty() and preview.async_controller.accepted_commands==0)
				check("migration_generation_and_highwater",preview.generation>old.shadow.generation and preview.command_queue.last_command_id==old.highwater_id and preview.ticket_id==fresh.ticket_id)
				check("migration_profile_selection",preview._capture_brush_selection()==old.gpu_beach_edit.selection.brush)
				check("migration_nondefault_brush_parameters",preview._capture_brush_selection().tool=="wall_v1" and preview._capture_brush_selection().dig_amount_m3==0.03 and preview._capture_brush_selection().fill_amount_m3==0.04)
				check("migration_provenance",preview.async_last_migration.validated_prefix_count==old.gpu_beach_edit.prefix.size())
				check("migration_continue_input",preview.input_scheduler.submit(command(1400)).is_empty())
				preview._start_tick()
				check("migration_continue_water",await idle() and preview.completed_ticks==old.tick+1 and preview.async_controller.state_seq>0)
				await restored_tools()
				check("migration_new_save",(await preview.save_gpu_checkpoint(base+"_new.sandgp")).is_empty())
				var saved_new:=Snapshot.load(base+"_new.sandgp",preview.source_signature)
				check("migration_new_decoder",saved_new.error.is_empty())
				check("migration_next_wave_matches_old",saved_new.error.is_empty() and absf(saved_new.checkpoint.native.control.decode_float(100)-next_wave)<0.000001)
				check("migration_original_file_unchanged",source_sha==FileAccess.get_sha256(base+".sandcp"))
				evidence={"source_file_sha256":source_sha,"source_versions":[4,2],"source_prefix_count":old.gpu_beach_edit.prefix.size(),"source_current_index":old.gpu_beach_native.current_index,"source_boundary_observed":old_boundary,"next_wave_old":next_wave,"next_wave_new":saved_new.checkpoint.native.control.decode_float(100),"historical_fixture":historical,"historical_sha256":FileAccess.get_sha256(historical),"historical_error":String(historical_error),"configuration":preview.source_signature,"provenance":preview.async_last_migration,"verifications":preview.beach_restore_verifications,"domain_id":String(preview._domain_id()),"loaded_scripts":loaded_code()}
	check("migration_runtime_healthy",preview.last_error.is_empty())
	await dispose_scene()
	var log_text:=FileAccess.get_file_as_string(base+".log")
	check("migration_no_engine_errors",not log_text.is_empty() and not log_text.contains("SCRIPT ERROR:") and not log_text.contains("\nERROR:"))
	var file:=FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":not failed,"checks":checks,"evidence":evidence},"\t"));file.close()
	quit(1 if failed else 0)
