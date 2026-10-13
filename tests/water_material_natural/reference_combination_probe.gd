extends "res://tests/water_material_natural/reference_detail_probe.gd"

func _cases() -> Array:
	return ["baseline","sun215_exp192","sun215_exp192_frequency2","sun215_exp192_frequency2_gain192"]

func _azimuth(id: String,original: float) -> float:
	return original if id=="baseline" else 215.0

func _frequency(id: String) -> float:
	return 2.0 if "frequency2" in id else 1.0

func _exponent(id: String,original: float) -> float:
	return original if id=="baseline" else 192.0

func _gain(id: String,original: float) -> float:
	return 1.92 if "gain192" in id else original
