extends "res://tests/integration/unified_edit_initialization_probe.gd"

func _initialize() -> void:
	super._initialize()
	output=output.path_join("lifecycle.json")

func finish() -> void:
	observations.numerics=pipeline._configuration.get("environment",{}).get("water_numerics",{})
	super.finish()
