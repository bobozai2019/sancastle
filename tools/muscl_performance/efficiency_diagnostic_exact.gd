extends "res://tests/integration/water_execution_exact_probe.gd"

const Observer=preload("res://tools/muscl_performance/efficiency_diagnostic.gd")
var use_diagnostic:=false
var diagnostic_rows: Array=[]

func fixture(spec: Dictionary, original: bool) -> Array:
	use_diagnostic=not original
	return await super.fixture(spec,original)

func prepare_test_tick(spec: Dictionary, iteration: int) -> void:
	super.prepare_test_tick(spec,iteration)
	if not use_diagnostic:return
	var recorder=owner.water.muscl
	if recorder.diagnostic==null:
		var observer:=Observer.new()
		observer.retry_cache_source=recorder.buffers.retry_cache
		check(spec.name+"_observer_initialized",observer.initialize(owner.state.rd))
		observer.stride=1;observer.enabled=true
		recorder.diagnostic=observer

func capture_render() -> void:
	if use_diagnostic:
		diagnostic_rows.append(owner.water.muscl.diagnostic.snapshot())
		DirAccess.make_dir_recursive_absolute(output)
		FileAccess.open(output.path_join("diagnostic_exact.json"),FileAccess.WRITE).store_string(JSON.stringify(diagnostic_rows,"\t"))
	super.capture_render()
