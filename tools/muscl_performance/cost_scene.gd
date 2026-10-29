extends "res://tools/muscl_performance/scene_baseline.gd"

# Whole-tick timing retains the standard cached path. Unlike sparse stage
# timing, it adds only the existing production profile markers. Completion
# deltas identify actual simulated seconds for each measured GPU batch.
class CostTimeline:
	extends "res://scripts/simulation/unified_edit/diagnostics.gd"
	var pipeline_ref: WeakRef
	var generation:=0
	func mark(event: StringName, key: int=0, detail: Dictionary={}) -> void:
		var row:=detail.duplicate()
		row.generation=generation
		var p=pipeline_ref.get_ref()
		if p!=null:
			if event==&"settle_end":row.advanced_time_s=p.advanced_time_s
			if event==&"submit_end":
				row.water_record_us=p.water.last_recording_us
				row.record_seq=p.water.recorded_ticks
				row.standard_callable=p.water.coupled_recorder==Callable(p.coupled,"record")
				row.coupling_path="uncoupled" if not p.water.coupled_recorder.is_valid() else ("standard" if row.standard_callable else "custom")
		super.mark(event,key,row)

var cost_installed:=false

func _initialize() -> void:
	super._initialize()
	timing_off=false

func _process(delta: float) -> bool:
	if not cost_installed and diagnostic!=null and beach!=null and beach.ready_for_ticks:
		var p=beach.runtime.current
		var timeline:=CostTimeline.new();timeline.pipeline_ref=weakref(p)
		timeline.generation=beach.generation
		diagnostic=timeline;p.diagnostics=timeline;p.heights.diagnostics=timeline
		cost_installed=true
	return super._process(delta)
