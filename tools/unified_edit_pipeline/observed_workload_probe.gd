extends "res://tools/unified_edit_pipeline/workload_probe.gd"

# Additional observation only, kept separate from the frozen first matrix.
func _fixture(index: int) -> Dictionary:
	var value: Dictionary=super._fixture(index)
	if not hardware.has("command_chunks"):hardware.command_chunks={}
	var chunks: Array=[]
	if value.get("schema_version")==2:
		chunks=range(64)
	else:
		var a: Vector3=value.transform.position_m
		var b: Vector3=value.transform.get("end_position_m",a)
		var start:=Vector2(a.x,a.z);var end:=Vector2(b.x,b.z)
		var radius: float=value.radius_m
		var lo: Vector2=(start.min(end)-Vector2.ONE*(radius+0.25)+Vector2.ONE*16.0)/0.125
		var hi: Vector2=(start.max(end)+Vector2.ONE*(radius+0.25)+Vector2.ONE*16.0)/0.125
		var dirty:=Rect2i(Vector2i(floori(lo.x),floori(lo.y)),Vector2i(ceili(hi.x)-floori(lo.x)+1,ceili(hi.y)-floori(lo.y)+1))
		for chunk in 64:
			if dirty.intersects(Rect2i((chunk%8)*32,(chunk/8)*32,33,33)):chunks.append(chunk)
	hardware.command_chunks[str(value.command_id)]=chunks
	return value

func _observe_workload() -> void:
	super._observe_workload()
	if finalizing or trace.is_empty():return
	trace.back().merge({"window_focused":DisplayServer.window_is_focused(),"max_fps":Engine.max_fps,"low_processor_usage":OS.low_processor_usage_mode,"low_processor_sleep_us":OS.low_processor_usage_mode_sleep_usec})

func _collect_render() -> void:
	var device: RenderingDevice=preview.solver.rd
	var frame:=device.get_captured_timestamps_frame()
	if frame!=seen_capture:
		seen_capture=frame
		var starts:={}
		var spans: Array=[]
		for index in device.get_captured_timestamps_count():
			var label:=device.get_captured_timestamp_name(index)
			if label.ends_with("_start"):
				starts[label.trim_suffix("_start")]={"gpu_ns":device.get_captured_timestamp_gpu_time(index),"cpu_us":device.get_captured_timestamp_cpu_time(index)}
			elif label.ends_with("_end"):
				var key:=label.trim_suffix("_end")
				if starts.has(key):
					spans.append({"label":key,"group":PerfPanel._stage_for(key),"gpu_ns":device.get_captured_timestamp_gpu_time(index)-int(starts[key].gpu_ns),"cpu_marker_us":device.get_captured_timestamp_cpu_time(index)-int(starts[key].cpu_us)})
					starts.erase(key)
		if not spans.is_empty():gpu_samples.append({"frame":frame,"spans":spans})
	call_deferred("_collected")
