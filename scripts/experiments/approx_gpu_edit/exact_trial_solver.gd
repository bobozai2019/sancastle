extends "res://scripts/experiments/approx_gpu_edit/exact_dispatch_adapter.gd"

var brush_spirv: RDShaderSPIRV
var brush_sets: Array[RID] = []
var stable_fields := {}
var diagnostics := false
var trial_exact_policy := 3

func setup_brush() -> bool:
	brush_sets.append(RID()) # Lifecycle marker; inherited exact uniform sets are used.
	for field in ["sand","water","momentum_x","momentum_z"]:
		stable_fields[field] = _create_texture(RenderingDevice.DATA_FORMAT_R32_SFLOAT,PackedByteArray())
	return true

func dispatch_brush(command: Dictionary,_mode: int) -> bool:
	var adapted := {"generation":command.generation,"command_id":command.command_id,"kind":&"remove_sand" if command.kind == "dig" else &"place_sand","shape":&"circle" if command.start_xz_m == command.end_xz_m else &"swept_segment","start_xz_m":command.start_xz_m,"end_xz_m":command.end_xz_m,"radius_m":command.radius_m,"amount_m3":command.nominal_amount_m3,"strength":1.0,"seed":101,"sim_tick":command.requested_tick}
	adapted["transform"] = {"position_m":Vector3(command.start_xz_m.x,0,command.start_xz_m.y),"end_position_m":Vector3(command.end_xz_m.x,0,command.end_xz_m.y)}
	var bytes := Protocol.encode(adapted,command.command_id,state_revision,grid_size,cell_size_m,trial_exact_policy,1000.0,0.25)
	profile_passes = diagnostics
	var mark := "trial_%d_%d" % [command.generation,command.command_id]
	if diagnostics: rd.capture_timestamp(mark+"_start")
	var ok := dispatch_without_cpu_receipt(bytes)
	if diagnostics: rd.capture_timestamp(mark+"_end")
	profile_passes = false
	return ok

func publish_trial() -> bool:
	for field in stable_fields:
		if rd.texture_copy(current_texture(field),stable_fields[field],Vector3.ZERO,Vector3.ZERO,Vector3(grid_size,grid_size,1),0,0,0,0) != OK: return false
	return true

func release() -> void:
	for rid in stable_fields.values():
		if rid.is_valid(): rd.free_rid(rid)
	super.release()
