extends "res://tools/unified_edit_pipeline/diagnose_shovel_stutter.gd"

const Diagnostics=preload("res://scripts/simulation/unified_edit/diagnostics.gd")
const StageObserver=preload("res://tools/unified_edit_pipeline/shovel_stage_observer.gd")
const WaterObserver=preload("res://tools/unified_edit_pipeline/shovel_water_observer.gd")
var timeline:=Diagnostics.new()
var detail_gpu:=false
var water_only:=false
var manual:=false
var wet:=false
var duration_s:=30.0
var hold_height:=false
var marker_down:=false
var probe_sources: Dictionary={}

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg=="--water-detail":detail_gpu=true;sampling=true
		if arg=="--water-only":water_only=true;sampling=true
		if arg=="--manual":manual=true
		if arg=="--wet":wet=true
		if arg=="--hold-height":hold_height=true
		if arg.begins_with("--duration="):duration_s=clampf(float(arg.trim_prefix("--duration=")),5.0,300.0)
	for path in ["res://tools/unified_edit_pipeline/diagnose_shovel_latency.gd","res://tools/unified_edit_pipeline/diagnose_shovel_stutter.gd","res://tools/unified_edit_pipeline/current_cost_probe.gd","res://tools/unified_edit_pipeline/shovel_stage_observer.gd","res://tools/unified_edit_pipeline/shovel_water_observer.gd"]:probe_sources[path]=FileAccess.get_sha256(path)
	super._initialize()

func _configure_render() -> void:
	var owner=scene.runtime.current;device=owner.state.rd
	owner.diagnostics=timeline;owner.heights.diagnostics=timeline
	if detail_gpu or water_only:
		observer=Observer.new() if water_only else StageObserver.new();observer.adopt(owner.executor)
		var water_observer:=WaterObserver.new();water_observer.adopt(observer.response);observer.response=water_observer
		water_observer.sparse=water_only
		# The coarse decorator delegates record() to its retained executor.
		if water_only:observer.original.response=water_observer
		owner.executor=observer
	elif sampling:
		observer=Observer.new();observer.adopt(owner.executor);owner.executor=observer
	owner.state.profile_passes=sampling
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),sampling)
	call_deferred("_configured")

func _configured() -> void:
	scene.runtime.current.heights.hold_physics=hold_height
	super._configured()

func _target(domain) -> bool:
	if not wet:return super._target(domain)
	var best_score:=-INF;var found:=false
	for z in range(40,217,16):
		for x in range(32,225,16):
			var minimum:=INF;var maximum:=-INF;var min_sand:=INF;var obstruction:=false
			for dz in range(-20,21):
				for dx in range(-16,17):
					var i: int=(z+dz)*256+x+dx
					minimum=minf(minimum,domain.water[i]);maximum=maxf(maximum,domain.water[i]);min_sand=minf(min_sand,domain.sand[i]);obstruction=obstruction or domain.obstacle[i]!=0
			var score:=-absf((maximum+minimum)*0.5-0.15)
			if minimum>0.01 and maximum<0.8 and not obstruction and min_sand>0.05 and score>best_score:
				best_score=score;found=true;start_point=Vector2((x+.5)*.125-16,(z+.5)*.125-16)
				target_witness={"cell":Vector2i(x,z),"water_min_m":minimum,"water_max_m":maximum,"sand_min_m":min_sand,"checked_cell_rect":Rect2i(x-16,z-20,33,41),"mode":"initial_wet_footprint"}
	return found

func _exercise() -> void:
	if not manual:
		await super._exercise();return
	phase="manual_live";scene.playing=true
	DisplayServer.window_set_title("Shovel trace: use normally; F8 marks stutter; auto-save after "+str(duration_s)+"s")
	var until:=Time.get_ticks_usec()+int(duration_s*1000000.0)
	while Time.get_ticks_usec()<until:await process_frame
	scene.input.finish()

func _observe() -> void:
	if phase=="drain" and hold_height:scene.runtime.current.heights.hold_physics=false
	super._observe()
	var down:=Input.is_key_pressed(KEY_F8)
	if down and not marker_down:timeline.mark(&"user_marker")
	marker_down=down

func finish() -> void:
	observations.timeline=timeline.snapshot()
	observations.packed_comparison={"reference_packed":"--reference-packed" in OS.get_cmdline_user_args(),"packed_phases":"--packed-phases" in OS.get_cmdline_user_args()}
	observations.diagnostic_options={"manual":manual,"duration_s":duration_s,"wet":wet,"hold_height":hold_height,"water_detail":detail_gpu,"water_only":water_only,"sampling":sampling,"note":"water_only samples the first response in each process frame. hold_height also backpressures height captures; it is not a shape-only ablation. CPU callbacks are not GPU completion timestamps."}
	var sources: Dictionary=hardware.get("configuration",{}).get("sources",{}).duplicate(true)
	sources.merge(probe_sources)
	var changed: Array=[]
	for path in sources:
		if FileAccess.get_sha256(path)!=sources[path]:changed.append(path)
	observations.source_integrity={"checked":sources.size(),"changed":changed,"probe_sources":probe_sources}
	check("source_hashes_unchanged",not sources.is_empty() and changed.is_empty())
	check("trace_not_truncated",observations.timeline.dropped==0)
	super.finish()
