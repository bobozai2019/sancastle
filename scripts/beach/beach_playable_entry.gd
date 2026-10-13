extends "res://scripts/beach/beach_recovery_entry.gd"

## All playable layouts share main's GPU tools, collision, ledger and recovery.
@export_enum("main", "test1_capture", "test1_backwash") var scene_key := "main"
const CaptureLayout := preload("res://scripts/scenarios/test1_playable_layout.gd")

func _initialize_domain(target: SandWaterDomain) -> bool:
	if scene_key == "main":
		return super._initialize_domain(target)
	return CaptureLayout.initialize(target, scene_key)

func _ready() -> void:
	if not replay_checkpoint.is_empty() and replay_checkpoint.shadow.get("domain_id") != _domain_id():
		_fail("scene_checkpoint_mismatch")
		return
	super._ready()

func _domain_id() -> StringName:
	return &"main_beach" if scene_key == "main" else StringName(scene_key)

func _update_status() -> void:
	super._update_status()
	if status_label != null and scene_key != "main":
		var title := "test1 捕帧沙床" if scene_key == "test1_capture" else "test1 上滩回流"
		status_label.text = status_label.text.replace(Scenarios.NAMES[preset_index], title)

func restore_gpu_checkpoint_data(checkpoint: Dictionary) -> StringName:
	if checkpoint.get("shadow", {}).get("domain_id") != _domain_id():
		return &"scene_checkpoint_mismatch"
	return await super.restore_gpu_checkpoint_data(checkpoint)

func _render_begin_tick(level_m: float, wave_height_m: float, patch_data: PackedByteArray,
		patch_count: int, chunks: PackedInt32Array, command_ids: PackedInt32Array, token: int) -> void:
	if scene_key != "main":
		level_m = CaptureLayout.sea_level(scene_key, float(completed_ticks + 1) * SIM_DELTA) + wave_height_m
	super._render_begin_tick(level_m, wave_height_m, patch_data, patch_count, chunks, command_ids, token)

func _scene_switch_busy() -> bool:
	var service := get_node_or_null("/root/BeachScenes")
	return service != null and service.busy

func _unhandled_input(event: InputEvent) -> void:
	if not _scene_switch_busy():
		super._unhandled_input(event)

func _input(event: InputEvent) -> void:
	if _scene_switch_busy():
		gpu_brush = &""
		return
	super._input(event)

func _on_trigger_wave_pressed() -> void:
	if not _scene_switch_busy():
		super._on_trigger_wave_pressed()
