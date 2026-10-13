extends SceneTree

func _init() -> void:
	var source := "res://tests/fixtures/gpu_edit_validation/compact_encoding/"
	for size in [64, 256]:
		var domain = preload("res://scripts/simulation/sand_water_domain.gd").new(size, 0.125)
		domain.apply_tool({"command_id": 1, "kind": &"compact", "shape": &"circle",
			"position_m": Vector3.ZERO, "radius_m": 0.75, "strength": 0.8})
		var image := Image.create_from_data(size, size, false, Image.FORMAT_RF, domain.compaction.to_byte_array())
		image.convert(Image.FORMAT_RH)
		var expected := image.get_data()
		var gpu := FileAccess.get_file_as_bytes(source + "mixed_compact_%d_compaction.bin" % size)
		var max_ratio := 0.0
		var differing := 0
		var lower := 0
		for i in domain.compaction.size():
			var value: float = domain.compaction[i]
			var actual := gpu.decode_half(i * 2)
			if value != actual:
				differing += 1
				if actual < value: lower += 1
				var ulp := pow(2.0, floor(log(absf(value)) / log(2.0)) - 10.0)
				max_ratio = maxf(max_ratio, absf(actual - value) / ulp)
		print(JSON.stringify({"grid": size, "Godot_RH_exact_match": expected == gpu,
			"different_from_float32_cells": differing, "below_float32_cells": lower, "max_ulp16_ratio": max_ratio}))
		var file := FileAccess.open("user://compact_%d_cpu_R16.bin" % size, FileAccess.WRITE)
		file.store_buffer(expected)
	quit()
