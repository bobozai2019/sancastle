extends "res://tests/water_material_natural/reference_detail_probe.gd"

func _cases() -> Array:
	return ["baseline","sun215","sun215_exp96","sun215_exp192","sun215_frequency2"]

func _azimuth(id: String,original: float) -> float:
	return original if id=="baseline" else 215.0

func _frequency(id: String) -> float:
	return 2.0 if id=="sun215_frequency2" else 1.0

func _exponent(id: String,original: float) -> float:
	return 96.0 if id=="sun215_exp96" else (192.0 if id=="sun215_exp192" else original)
