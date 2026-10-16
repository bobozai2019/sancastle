extends "res://tests/shape_brushes/original_retention_probe.gd"

var log_done:=false
var log_bytes:=PackedByteArray()
var hash_done:=false
var hash_bytes:=PackedByteArray()
var calibration := {}

func _retention_scene_path() -> String:
	return "res://tests/shape_brushes/stage_log_retention_lab.tscn"

func log_result(bytes: PackedByteArray) -> void: call_deferred("log_received",bytes)
func log_received(bytes: PackedByteArray) -> void: log_bytes=bytes;log_done=true
func hash_result(bytes: PackedByteArray) -> void: call_deferred("hash_received",bytes)
func hash_received(bytes: PackedByteArray) -> void: hash_bytes=bytes;hash_done=true
func calibration_result(bytes: PackedByteArray, binding: int) -> void: call_deferred("calibration_received",bytes,binding)
func calibration_received(bytes: PackedByteArray, binding: int) -> void: calibration[binding]=bytes
func read_log() -> void:
	var error: Error=preview.solver.rd.buffer_get_data_async(preview.trace_buffer,log_result)
	if error!=OK: call_deferred("log_received",PackedByteArray())
	error=preview.solver.rd.buffer_get_data_async(preview.hash_buffer,hash_result)
	if error!=OK: call_deferred("hash_received",PackedByteArray())
	var images: Array[RID]=preview.snapshot_inputs.duplicate();images.append_array(preview.trace_images)
	for binding in images.size(): preview.solver.rd.texture_get_data_async(images[binding],0,calibration_result.bind(binding))

func capture(tick: int) -> void:
	await super.capture(tick)
	if tick!=target_ticks: return
	RenderingServer.call_on_render_thread(read_log)
	var deadline:=Time.get_ticks_msec()+30000
	while (not log_done or not hash_done or calibration.size()!=12) and Time.get_ticks_msec()<deadline: await process_frame
	_check("stage_log_complete_readback",log_done and log_bytes.size()==preview.TRACE_MAX_EVENTS*preview.TRACE_EVENT_BYTES)
	_check("stage_hash_complete_readback",hash_done and hash_bytes.size()==preview.TRACE_MAX_EVENTS*preview.HASH_EVENT_BYTES)
	_check("stage_hash_calibration_complete",calibration.size()==12)
	var file:=FileAccess.open(output.path_join("stage_log.bin"),FileAccess.WRITE)
	file.store_buffer(log_bytes.slice(0,preview.trace_event_count*preview.TRACE_EVENT_BYTES));file.close()
	file=FileAccess.open(output.path_join("stage_hash.bin"),FileAccess.WRITE)
	file.store_buffer(hash_bytes.slice(0,preview.trace_event_count*preview.HASH_EVENT_BYTES));file.close()
	file=FileAccess.open(output.path_join("stage_log_identity.json"),FileAccess.WRITE)
	var identity: Dictionary=preview.trace_identity.duplicate(true)
	identity["events"]=preview.trace_event_count;identity["path"]=output.path_join("stage_log.bin")
	identity["bytes"]=preview.trace_event_count*preview.TRACE_EVENT_BYTES;identity["sha256"]=FileAccess.get_sha256(identity.path)
	identity["hash_path"]=output.path_join("stage_hash.bin");identity["hash_bytes"]=preview.trace_event_count*preview.HASH_EVENT_BYTES;identity["hash_sha256"]=FileAccess.get_sha256(identity.hash_path)
	var inputs := []
	for binding in 12:
		var path:=output.path_join("calibration_binding_%02d.bin"%binding)
		file=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(calibration[binding]);file.close()
		inputs.append({"binding":binding,"path":path,"bytes":calibration[binding].size(),"sha256":FileAccess.get_sha256(path)})
	identity["calibration"]=inputs
	file=FileAccess.open(output.path_join("stage_log_identity.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(identity,"\t"));file.close()

func _retention_resources_released() -> bool:
	_check("stage_log_pool_released",preview.trace_owned.is_empty() and preview.snapshot_inputs.is_empty())
	return preview.gpu_release_done
