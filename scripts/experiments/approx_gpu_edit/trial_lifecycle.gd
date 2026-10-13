extends "res://assets/water_material_natural_candidate/compiled_worker_entry.gd"

# Isolated copies of reference_preview lifecycle methods.
# No collision setup, dirty-height readback, hover prefetch or exact ledger assertion.

func _render_setup(domain: SandWaterDomain, token: int) -> void:
	if closing or token != generation:
		return
	if prototype_fixed_substeps > 0 and not prototype_batched_ledger_bookkeeping:
		call_deferred("_fail", "fixed substeps require batched ledger bookkeeping")
		return
	if prototype_batched_ledger_bookkeeping:
		if prototype_ledger_batch_ticks < 1 or prototype_sync_boundary_readback:
			call_deferred("_fail", "batched ledger mode requires batch capture")
			return
	solver = _create_solver()
	var initial_qx: PackedFloat32Array = replay_checkpoint.fields["momentum_x"] if \
			not replay_checkpoint.is_empty() else PackedFloat32Array()
	var initial_qz: PackedFloat32Array = replay_checkpoint.fields["momentum_z"] if \
			not replay_checkpoint.is_empty() else PackedFloat32Array()
	if not solver.initialize(RenderingServer.get_rendering_device(), domain,
			spirvs[0], spirvs[1], spirvs[2], spirvs[3], spirvs[4], spirvs[5], spirvs[6], spirvs[7],
			initial_qx, initial_qz):
		call_deferred("_fail", "GPU shallow solver initialization failed")
		return
	if not replay_checkpoint.is_empty():
		solver.water_source_m3 = replay_checkpoint.water_source_m3
		solver.water_sink_m3 = replay_checkpoint.water_sink_m3
	if prototype_batched_ledger_bookkeeping:
		tide_ledger_settled_ticks = completed_ticks
	if prototype_ledger_ring_capacity > 0:
		tide_ledger_ring = TideLedgerRing.new()
		if not tide_ledger_ring.initialize(solver.rd, tide_ledger_ring_spirv,
				solver.current_texture("tide_delta"), GRID_SIZE,
				prototype_ledger_ring_capacity):
			call_deferred("_fail", "tide ledger ring initialization failed")
			return
	if prototype_ledger_batch_ticks > 0:
		tide_ledger_batches = TideLedgerBatches.new()
		if not tide_ledger_batches.initialize(solver.rd, tide_ledger_ring_spirv,
				solver.current_texture("tide_delta"), GRID_SIZE,
				prototype_ledger_batch_ticks, _on_tide_ledger_batch):
			call_deferred("_fail", "tide ledger batches initialization failed")
			return
	if fixture_id in [WaterFixture.FIXTURE_ID, SandFixture.COUPLED_FIXTURE_ID] and \
			enable_phase2_foam:
		foam_field = _create_foam_field()
		var initial_foam: PackedFloat32Array = replay_checkpoint.get("foam_history",
			PackedFloat32Array())
		var initial_bed := PackedFloat32Array()
		initial_bed.resize(GRID_SIZE * GRID_SIZE)
		for cell in initial_bed.size():
			initial_bed[cell] = shadow_domain.rock[cell] + shadow_domain.sand[cell]
		if not foam_field.initialize(solver, spirvs[17], initial_foam, initial_bed,
				prototype_front_band_foam_source):
			call_deferred("_fail", "GPU foam field initialization failed")
			return
	if prototype_rise_front_field:
		rise_front_field = RiseFrontField.new()
		if foam_field == null or not rise_front_field.initialize(solver, foam_field,
				rise_front_spirv, rise_front_anchor_spirv):
			call_deferred("_fail", "GPU rise front field initialization failed")
			return
	if prototype_local_front_field:
		local_front_field = LocalFrontField.new()
		var initial_front: PackedFloat32Array = replay_checkpoint.get(
			"local_front_history", PackedFloat32Array())
		if foam_field == null or not local_front_field.initialize(solver, foam_field,
				local_front_x_spirv, local_front_z_spirv, initial_front):
			call_deferred("_fail", "GPU local front field initialization failed")
			return
	if prototype_front_band_foam_source:
		if local_front_field == null or not foam_field.configure_uniforms(solver,
				local_front_field.texture):
			call_deferred("_fail", "GPU front-band foam uniforms failed")
			return
	if prototype_contact_history_field:
		contact_history_field = ContactHistoryField.new()
		if not contact_history_field.initialize(solver, foam_field,
				local_front_field, contact_history_spirv):
			call_deferred("_fail", "GPU contact history field initialization failed")
			return
	sand_audit = SandAudit.new()
	if not sand_audit.initialize(solver, spirvs[9]):
		call_deferred("_fail", "GPU sand audit initialization failed")
		return
	if enable_erosion:
		sediment_coupler = SedimentCoupler.new()
		if not sediment_coupler.initialize(solver, spirvs[10], spirvs[11]):
			call_deferred("_fail", "GPU sediment coupler initialization failed")
			return
		material_coupler = _create_material_coupler()
		material_coupler.cohesion_yield_height_m = sand_cohesion_yield_height_m
		if not material_coupler.initialize(solver, sediment_coupler.dirty_max_texture,
				spirvs[12], spirvs[13], spirvs[14]):
			call_deferred("_fail", "GPU material coupler initialization failed")
			return
	if enable_structures:
		obstacle_remap = ObstacleRemap.new()
		if not obstacle_remap.initialize(solver, spirvs[15], spirvs[16]):
			call_deferred("_fail", "GPU obstacle remap initialization failed")
			return
	_publish_textures()
	call_deferred("_mark_ready", token)

func _render_finish_tick(data: PackedByteArray, revision: int,
		substeps: int, token: int) -> void:
	if closing or token != generation:
		return
	if profile_tick_timing:
		profile_render_finish_us = Time.get_ticks_usec()
	var post_substep := _dispatch_coupled_substep if enable_erosion else Callable()
	## Skipping the reset while a summary is in flight is safe: the texture is an
	## atomic max, so the pending readback then carries the worst of both ticks.
	## Either way this tick is now covered by an outstanding summary.
	if enable_erosion:
		sediment_coupler.clear_dirty_max()
		dirty_ticks_covered += 1
	var step_ok: bool = solver.call("dispatch_tick_fixed", SIM_DELTA,
		substeps, revision, post_substep) if prototype_fixed_substeps > 0 else \
		solver.dispatch_tick_with_cfl(SIM_DELTA, data, revision, post_substep)
	if not step_ok:
		call_deferred("_fail", "GPU shallow tick failed")
		return
	if prototype_front_band_foam_source and (local_front_field == null or
			not local_front_field.dispatch(solver, foam_field, true)):
		call_deferred("_fail", "GPU pre-foam local front tick failed")
		return
	if foam_field != null and not foam_field.dispatch(solver, SIM_DELTA):
		call_deferred("_fail", "GPU foam tick failed")
		return
	if rise_front_field != null and not rise_front_field.dispatch(solver, foam_field):
		call_deferred("_fail", "GPU rise front tick failed")
		return
	if local_front_field != null and not prototype_front_band_foam_source and \
			not local_front_field.dispatch(solver, foam_field):
		call_deferred("_fail", "GPU local front tick failed")
		return
	if contact_history_field != null and not contact_history_field.dispatch(solver,
			foam_field, SIM_DELTA):
		call_deferred("_fail", "GPU contact history tick failed")
		return
	if completed_ticks == 0 or (completed_ticks + 1) % 30 == 0:
		var audit_error := solver.request_audit_tiles(_on_debug_audit.bind(token))
		if audit_error != OK:
			call_deferred("_fail", "debug audit request failed: %d" % audit_error)
			return
		_request_sand_audit_render(token)
	_publish_textures()
	if profile_tick_timing:
		profile_render_finish_submit_us = Time.get_ticks_usec()
	call_deferred("_tick_finished", substeps, solver.water_source_m3,
		solver.water_sink_m3, token)

func _record_sand_audit(data: PackedByteArray, revision: int,
		ledger: Dictionary, token: int) -> void:
	if closing or token != generation or sand_audit == null:
		return
	var result: Dictionary = sand_audit.decode(data)
	if not result.get("valid", false):
		_fail("GPU sand audit data invalid at revision %d" % revision)
		return
	if result.invalid_cells != 0 or result.negative_cells != 0:
		_fail("GPU sand audit found invalid/negative cells at revision %d" % revision)
		return
	var current_total: float = result.sand_m3 + result.sediment_m3 + ledger.inventory_m3
	var closure := absf(current_total - initial_sand_total_m3 - \
		ledger.source_m3 + ledger.sink_m3)
	if revision > audit_sand_revision:
		audit_sand_m3 = result.sand_m3
		audit_sediment_m3 = result.sediment_m3
		audit_sand_total_m3 = current_total
		audit_sand_closure_m3 = closure
		audit_sand_invalid_cells = result.invalid_cells
		audit_sand_negative_cells = result.negative_cells
		audit_sand_revision = revision
		_update_status()
	if sand_audit_refresh_required and not playing and not tick_pending:
		sand_audit_refresh_required = false
		RenderingServer.call_on_render_thread(_request_sand_audit_render.bind(token))
