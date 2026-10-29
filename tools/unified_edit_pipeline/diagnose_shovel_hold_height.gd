extends "res://tools/unified_edit_pipeline/diagnose_shovel_stutter.gd"
# Diagnostic ablation: hold the genuine height consumer, then drain normally.
# This also bounds further readback captures after its two slots fill.
func _configured() -> void:
 scene.runtime.current.heights.hold_physics=true
 configured=true
func _observe() -> void:
 if phase=="drain":scene.runtime.current.heights.hold_physics=false
 super._observe()
func finish() -> void:
 observations.height_consumer_control="hold_physics until drain; once two height slots fill, captures/worker flow backpressures; not a pure shape-call-only ablation"
 super.finish()
