extends "res://tools/unified_edit_pipeline/diagnose_shovel_stutter.gd"
const StageObserver=preload("res://tools/unified_edit_pipeline/shovel_stage_observer.gd")
func _configure_render() -> void:
 var owner=scene.runtime.current;device=owner.state.rd
 observer=StageObserver.new();observer.adopt(owner.executor);owner.executor=observer
 owner.state.profile_passes=true
 RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
 call_deferred("_configured")
