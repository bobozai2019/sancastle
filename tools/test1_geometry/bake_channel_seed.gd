extends SceneTree

# Offline resource bake only. Preserve unrelated material/metadata fields.
func _initialize() -> void:
	var manifest_path := "res://assets/unified_edit/presentation/test1_geometry.json"
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	var seed_path: String = document.metadata.seed.path
	var seed: Dictionary = bytes_to_var(FileAccess.get_file_as_bytes(seed_path))
	var state := FileAccess.get_file_as_bytes("res://assets/test1_geometry/initial_state.f32").to_float32_array()
	assert(state.size() == 65536 * 5 and seed.sim_tick == 0)
	for i in 65536:
		seed.sand[i] = state[i*5]
		seed.water[i] = state[i*5+1]
		seed.obstacle[i] = state[i*5+4]
		seed.wetness[i] = 1.0 if seed.water[i] > 0.001 else 0.0
	for key in ["flux_left","flux_right","flux_up","flux_down"]: seed[key].fill(0.0)
	FileAccess.open(seed_path, FileAccess.WRITE).store_buffer(var_to_bytes(seed))
	document.metadata.seed.sha256 = FileAccess.get_sha256(seed_path)
	document.metadata.scene.sha256 = FileAccess.get_sha256(document.metadata.scene.path)
	document.metadata["terrain_adaptation"] = {"path":"res://assets/test1_geometry/initial_state.json", "sha256":FileAccess.get_sha256("res://assets/test1_geometry/initial_state.json")}
	FileAccess.open(manifest_path, FileAccess.WRITE).store_string(JSON.stringify(document, "\t")+"\n")
	print("CHANNEL_SEED_BAKED ", document.metadata.seed.sha256)
	quit()
