extends "res://tools/muscl_performance/scene_baseline.gd"

var prop_rows: Array=[]
var last_prop_frame:=-1

func _initialize() -> void:
	super._initialize()
	scene_path="res://scenes/main.tscn"

func _process(delta: float) -> bool:
	var result: bool=super._process(delta)
	if phase!="live" or beach==null or beach.floating_props==null:return result
	var props=beach.floating_props
	var frame:=Engine.get_process_frames()
	if frame-last_prop_frame<15:return result
	last_prop_frame=frame
	prop_rows.append({"frame":frame,"generation":beach.generation,"props_generation":props.generation,"active":props.active,"error":props.last_error,"sample_generation":props.latest_sample.get("generation",-1),"sample_seq":props.latest_sample.get("captured_state_seq",-1),"sample_tick":props.latest_sample.get("captured_tick",-1),"sample_time_s":props.latest_sample.get("captured_time_s",-1.0),"simulation_time_s":beach.runtime.current.advanced_time_s,"holds":props.holds.duplicate()})
	return result

func run() -> void:
	await super.run()
	var sampled:=0
	var generations_ok:=true
	var errors: Array=[]
	var first_time: float=INF
	var last_time: float=-INF
	for row in prop_rows:
		if not String(row.error).is_empty():errors.append(row.error)
		generations_ok=generations_ok and row.generation==row.props_generation and row.active
		if row.sample_seq>=0:
			sampled+=1
			generations_ok=generations_ok and row.sample_generation==row.generation
			first_time=minf(first_time,row.sample_time_s);last_time=maxf(last_time,row.sample_time_s)
	var passed: bool=sampled>1 and generations_ok and errors.is_empty() and last_time>first_time
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"pass":passed,"samples":prop_rows,"valid_samples":sampled,"generations_ok":generations_ok,"errors":errors,"sample_time_range":[first_time,last_time],"scope":"Normal main scheduling, standard full scene, active props receive same-generation completed public Probe samples; no direct simulation writes"},"\t"))
	quit(0 if passed else 1)
