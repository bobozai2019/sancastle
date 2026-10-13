extends "res://scripts/simulation/edit_validation/gpu_water_editor.gd"

# Experimental submission revision; GPU control/receipt still checks candidate.
# No CPU receipt or exact inventory claim. Read status only at diagnostic boundaries.
func dispatch_without_cpu_receipt(data: PackedByteArray) -> bool:
	if receipt_pending or publication_pending or data.size() != 128 or data.decode_u32(80) != grid_size:
		return false
	if not _supports_water_policy(data.decode_u32(84)):
		return false
	edit_window = Rect2i(0, 0, grid_size, grid_size)
	if local_dispatch:
		var a := Vector2(data.decode_float(48), data.decode_float(52))
		var b := a if data.decode_u32(44) == 0 else Vector2(data.decode_float(56), data.decode_float(60))
		var radius := data.decode_float(64)
		var cell_size := data.decode_float(76)
		if a.is_finite() and b.is_finite() and is_finite(radius) and radius > 0.0 and is_finite(cell_size) and cell_size > 0.0:
			# Only an enclosing rectangle is calculated on CPU; weights and reductions stay on GPU.
			# Two extra cells enclose float32 boundary rounding and cell-center conversion.
			var lo := (a.min(b) - Vector2.ONE * radius) / cell_size + Vector2.ONE * (grid_size * 0.5)
			var hi := (a.max(b) + Vector2.ONE * radius) / cell_size + Vector2.ONE * (grid_size * 0.5)
			var x0 := clampi(int(floor(lo.x)) - 2, 0, grid_size - 1)
			var z0 := clampi(int(floor(lo.y)) - 2, 0, grid_size - 1)
			var x1 := clampi(int(ceil(hi.x)) + 2, 0, grid_size - 1)
			var z1 := clampi(int(ceil(hi.y)) + 2, 0, grid_size - 1)
			edit_window = Rect2i(x0, z0, x1 - x0 + 1, z1 - z0 + 1)
	var control := PackedByteArray()
	control.resize(64)
	control.fill(0)
	control.encode_s64(32, owner_generation)
	control.encode_s64(40, state_revision)
	if rd.buffer_update(command_buffer, 0, data.size(), data) != OK or rd.buffer_update(control_buffer, 0, 64, control) != OK:
		return false
	receipt_pending = true
	settlement_authorized = false
	active_ticket = data.decode_s64(0)
	_dispatch_edit(0)
	_dispatch_edit(1, 0)
	if data.decode_u32(40) == 0:
		for iteration in 4:
			_dispatch_edit(1, 1)
			_dispatch_edit(2)
			_dispatch_edit(1, 2)
	else:
		_dispatch_edit(2)
	_dispatch_edit(1, 3)
	_dispatch_extra_candidate(data)
	_dispatch_edit(3)
	_dispatch_extra_commit(0)
	if inject_receipt_failure_once:
		inject_receipt_failure_once = false
		_rollback_command()
		receipt_pending = false
		return false
	receipt_pending = false
	publication_pending = false
	state_revision += 1
	return true
