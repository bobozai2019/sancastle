extends Resource

## Metres and dimensionless appearance controls for one decorative plant kind.
@export var label: String = ""
@export var depth_min_m: float = 0.0
@export var depth_max_m: float = 0.025
@export var height_min_m: float = 0.25
@export var height_max_m: float = 0.45
@export var bed_min_m: float = -8.0
@export var bed_max_m: float = 10.0
@export_range(0.0, 1.0) var density: float = 0.85
@export var flow_response: float = 0.5
@export var max_slope: float = 1.5
@export_range(0.0, 1.0) var patch_min: float = 0.35
@export_range(0.0, 1.0) var patch_max: float = 1.0
@export var response_hz: float = 6.0

func snapshot() -> Dictionary:
	return {"label":label,"depth_min_m":depth_min_m,"depth_max_m":depth_max_m,
		"height_min_m":height_min_m,"height_max_m":height_max_m,"bed_min_m":bed_min_m,
		"bed_max_m":bed_max_m,"density":density,"flow_response":flow_response,
		"max_slope":max_slope,"patch_min":patch_min,"patch_max":patch_max,"response_hz":response_hz}
