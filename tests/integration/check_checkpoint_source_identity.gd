extends SceneTree

func _initialize() -> void:
	var path := OS.get_cmdline_user_args()[0]
	var loaded := preload("res://scripts/simulation/checkpoint_store.gd").load(path)
	if not loaded.error.is_empty():
		print("IDENTITY_ERROR ", loaded.error)
		quit(1)
		return
	var differences := []
	for source in loaded.checkpoint.gpu_beach_edit.configuration.sources:
		var expected: String = loaded.checkpoint.gpu_beach_edit.configuration.sources[source]
		var actual := FileAccess.get_sha256(source)
		if expected != actual: differences.append({"path": source, "expected": expected, "actual": actual})
	print("CHECKPOINT_SOURCE_DIFFERENCES ", JSON.stringify(differences))
	quit(0)
