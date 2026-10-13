extends SceneTree

const SCENE := preload("res://scenes/sand_coupled_fixture.tscn")
const Store := preload("res://scripts/simulation/checkpoint_store.gd")
const OUT := "res://test_output/sandcastle_visual_reconstruction_phase2/验收/S06_coupled_checkpoint.json"
const SAVE_TICK := 900
const END_TICK := 2700
const FIELDS := ["sand", "sediment", "wetness", "compaction", "water",
	"momentum_x", "momentum_z", "foam_history"]

var original: Node3D
var restored: Node3D
var received := {}
var frames := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	original = SCENE.instantiate()
	root.add_child(original)
	while not original.ready_for_ticks and original.last_error.is_empty() and frames < 10000:
		await process_frame
		frames += 1
	if not original.ready_for_ticks:
		_fail("initial fixture: " + original.last_error)
		return
	var wave: Dictionary = {"domain_id": original.shadow_domain.domain_id,
		"generation": original.generation, "request_id": 1,
		"start_tick": original.completed_ticks + 8,
		"profile_id": &"test_packet", "amplitude_m": 0.20,
		"duration_s": 5.0, "seed": 53021}
	if not original.request_wave(wave).ok:
		_fail("wave request")
		return
	while original.completed_ticks < SAVE_TICK and original.last_error.is_empty() and frames < 100000:
		await process_frame
		frames += 1
	if not original.last_error.is_empty():
		_fail("pre-save tick: " + original.last_error)
		return
	original.playing = false
	while original.tick_pending:
		await process_frame
	if original.support_loss_events.size() != 1:
		_fail("automatic support event absent")
		return
	var path := "user://s06_coupled_" + str(Time.get_ticks_usec()) + ".sandcp"
	var save_error: StringName = original.request_checkpoint_save(path)
	if not save_error.is_empty():
		_fail("save admission: " + String(save_error))
		return
	while original.last_save_path.is_empty() and original.last_save_error.is_empty() and frames < 110000:
		await process_frame
		frames += 1
	if original.last_save_path.is_empty():
		_fail("save completion: " + String(original.last_save_error))
		return
	var loaded: Dictionary = Store.load(path)
	if not loaded.error.is_empty() or loaded.checkpoint.support_loss_events.size() != 1:
		_fail("load: " + String(loaded.error))
		return
	restored = SCENE.instantiate()
	restored.generation = original.generation + 1
	restored.replay_checkpoint = loaded.checkpoint
	restored.replay_prefix_commands = loaded.prefix_commands
	restored.replay_target_tick = END_TICK
	root.add_child(restored)
	while not restored.ready_for_ticks and restored.last_error.is_empty() and frames < 120000:
		await process_frame
		frames += 1
	if not restored.ready_for_ticks or restored.support_loss_events.size() != 1 or \
			restored.support_loss_events[0].generation != restored.generation:
		_fail("restore setup: " + restored.last_error)
		return
	original.playing = true
	while (original.completed_ticks < END_TICK or restored.completed_ticks < END_TICK) and \
			original.last_error.is_empty() and restored.last_error.is_empty() and frames < 300000:
		await process_frame
		frames += 1
	original.playing = false
	while original.tick_pending or restored.tick_pending:
		await process_frame
	if original.completed_ticks != END_TICK or restored.completed_ticks != END_TICK:
		_fail("continuation tick mismatch")
		return
	RenderingServer.call_on_render_thread(_read.bind(original, "original"))
	RenderingServer.call_on_render_thread(_read.bind(restored, "restored"))
	while received.size() < FIELDS.size() * 2 and frames < 310000:
		await process_frame
		frames += 1
	var equal := {}
	for field in FIELDS:
		equal[field] = received.get("original_" + field, PackedByteArray()) == \
			received.get("restored_" + field, PackedByteArray())
		if not equal[field]:
			_fail("GPU field differs after restart: " + field)
			return
	var report := {"save_tick": loaded.checkpoint.tick, "end_tick": END_TICK,
		"continuation_seconds": float(END_TICK - loaded.checkpoint.tick) / 30.0,
		"support_event": restored.support_loss_events[0],
		"equal_gpu_fields": equal,
		"original_revision": original.solver.state_revision,
		"restored_revision": restored.solver.state_revision}
	var file := FileAccess.open(ProjectSettings.globalize_path(OUT), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("PASS: S06 coupled checkpoint " + JSON.stringify(report))
	quit(0)


func _read(source: Node3D, prefix: String) -> void:
	var rd := RenderingServer.get_rendering_device()
	var data := {}
	for field in FIELDS:
		var texture: RID = source.foam_field.current_texture() if field == \
			"foam_history" else source.solver.current_texture(field)
		data[prefix + "_" + field] = rd.texture_get_data(texture, 0)
	call_deferred("_receive", data)


func _receive(data: Dictionary) -> void:
	received.merge(data)


func _fail(reason: String) -> void:
	push_error("FAIL: S06 coupled checkpoint " + reason)
	quit(1)
