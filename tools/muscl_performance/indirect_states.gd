extends "res://tools/muscl_performance/variant_states.gd"

# Supplemental control capture for the same complete fixture trajectories.
# Full texture/SSBO archives remain separate and final captures include both.
func capture_render() -> void:
	var rd: RenderingDevice=owner.state.rd
	var result:={"decision":rd.buffer_get_data(owner.water.decision),"control":rd.buffer_get_data(owner.transport.control),"accepted_indirect":rd.buffer_get_data(owner.water.indirect)}
	for name in owner.water.muscl.buffers:result["muscl_"+name]=rd.buffer_get_data(owner.water.muscl.buffers[name])
	capture_received.call_deferred(result)
