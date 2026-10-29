extends "res://scripts/simulation/gpu_shallow_solver.gd"

## W07 route probe only. Keep all physics passes and accounting in the base
## solver; compare synchronous 1 KiB ledger + 4 KiB CFL readbacks against the
## production async path on the same reference scene and wave sequence.
var sync_readback_calls := 0
var sync_readback_us := 0


func request_data(field: String, callback: Callable) -> Error:
	if field not in [FIELD_TIDE_DELTA, FIELD_CFL_TILES]:
		return super.request_data(field, callback)
	var rid := current_texture(field)
	if rd == null or not rid.is_valid() or not callback.is_valid():
		return ERR_UNAVAILABLE
	var started := Time.get_ticks_usec()
	var data := rd.texture_get_data(rid, 0)
	sync_readback_us += Time.get_ticks_usec() - started
	sync_readback_calls += 1
	var expected := grid_size * 4 if field == FIELD_TIDE_DELTA else \
		grid_size * grid_size / 16
	if data.size() != expected:
		return ERR_INVALID_DATA
	callback.call(data)
	return OK
