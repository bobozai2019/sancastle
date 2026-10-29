extends "res://tests/edit_validation/beach_lab_entry.gd"

var cost_released := false

func _render_release() -> void:
	super._render_release()
	call_deferred("_cost_release_done")

func _cost_release_done() -> void:
	cost_released=true

# Preserve the original CPU shadow synchronization and absolute patch path.
# Share the selected physical slope implementation with the GPU candidate.
func _create_material_coupler() -> SandcastleGpuMaterialCoupler:
	if "--beach-staged-slope" in OS.get_cmdline_user_args():
		return preload("res://scripts/simulation/edit_validation/staged_slope_coupler.gd").new()
	return super._create_material_coupler()
