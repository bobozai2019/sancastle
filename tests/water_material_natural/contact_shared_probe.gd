extends "res://tests/water_material_natural/optics_layer_dry_probe.gd"

func _lighting_sweep(before: Dictionary) -> void:
	# Shared-surface profile is the only variable; use the same layered dry
	# attribution as T03, including bare bed and water-only depth labels.
	await super._lighting_sweep(before)
	var file:=FileAccess.open(output+"/contact_shared_effective.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(preview.effective_foam,"\t"));file.close()
