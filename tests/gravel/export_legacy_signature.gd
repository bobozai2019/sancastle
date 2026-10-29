extends SceneTree
func _initialize() -> void:
	var loaded := preload("res://scripts/simulation/checkpoint_store.gd").load("res://test_output/gpu_gravel/baseline_20261015/main_checkpoint.bin")
	if not loaded.error.is_empty(): quit(1); return
	FileAccess.open("res://assets/gravel/legacy_configuration_20261015.bin",FileAccess.WRITE).store_buffer(var_to_bytes(loaded.checkpoint.gpu_beach_edit.configuration))
	quit()
