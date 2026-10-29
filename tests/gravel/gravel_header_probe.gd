extends SceneTree

func _initialize() -> void:
	var owner=load("res://scripts/beach/gravel_playable_entry.gd").new()
	var missing := {"gpu_beach_edit":null}
	var edit_ok: bool=owner._prepare_legacy_checkpoint(missing)==missing
	var loaded := preload("res://scripts/simulation/checkpoint_store.gd").load("res://test_output/gpu_gravel/lifecycle_1792037874_911/checkpoint.bin")
	var checkpoint: Dictionary=loaded.checkpoint
	checkpoint.shadow=null
	var codec_ok := preload("res://scripts/visual/gravel_checkpoint_codec.gd").validate(checkpoint)==&"gravel_state_invalid"
	owner.free()
	var path := "res://test_output/gpu_gravel/delivery_20261015/header_probe.json"
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify({"pass":edit_ok and codec_ok,"checks":[{"name":"null_edit_header_no_exception","pass":edit_ok},{"name":"null_shadow_extension_rejected","pass":codec_ok}]}))
	print("GRAVEL_HEADER ",edit_ok," ",codec_ok)
	quit(0 if edit_ok and codec_ok else 1)
