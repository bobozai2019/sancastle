extends "res://tests/integration/async_pipeline_delivery_probe.gd"

const Domain=preload("res://scripts/simulation/sand_water_domain.gd")
const Front=preload("res://tests/visual_water_alignment/prototypes/reference_local_front_field.gd")
const Foam=preload("res://scripts/visual/gpu_foam_field.gd")
const Capture=preload("res://scripts/simulation/edit_validation/frame_pipeline/async_checkpoint_capture.gd")
var fixture_solver
var fixture_front
var fixture_foam
var fixture_registered:=false
var fixture_done:=false
var fixture_ok:=false
var fixture_bytes:=PackedByteArray()
var fixture_released:=false
var front_evidence:={}

func _fixture_render() -> void:
	var domain=Domain.new(256,0.125);domain.domain_id=preview.domain.domain_id;domain.generation=preview.generation
	for z in 256:domain.water[z*256+255]=0.01+0.0007*float((z*17+3)%29)
	fixture_solver=preview._create_solver()
	fixture_ok=fixture_solver.initialize(RenderingServer.get_rendering_device(),domain,preview.spirvs[0],preview.spirvs[1],preview.spirvs[2],preview.spirvs[3],preview.spirvs[4],preview.spirvs[5],preview.spirvs[6],preview.spirvs[7])
	if fixture_ok:
		fixture_foam=Foam.new()
		fixture_ok=fixture_foam.initialize(fixture_solver,preview.spirvs[17],PackedFloat32Array(),domain.rock,false)
	if fixture_ok:
		fixture_front=Front.new()
		fixture_ok=fixture_front.initialize(fixture_solver,fixture_foam,preview.local_front_x_spirv,preview.local_front_z_spirv) and fixture_front.dispatch(fixture_solver,fixture_foam,true)
	if fixture_ok:fixture_ok=fixture_front.request_data(_fixture_arrived)==OK
	call_deferred("_fixture_registration")

func _fixture_registration() -> void:fixture_registered=true
func _fixture_arrived(bytes: PackedByteArray) -> void:call_deferred("_fixture_record",bytes)
func _fixture_record(bytes: PackedByteArray) -> void:fixture_bytes=bytes;fixture_done=true

func _fixture_release_render() -> void:
	if fixture_front!=null:fixture_front.release()
	if fixture_foam!=null:fixture_foam.release()
	if fixture_solver!=null:fixture_solver.release()
	call_deferred("_fixture_release_done")
func _fixture_release_done() -> void:fixture_released=true

func front_stats(bytes: PackedByteArray) -> Dictionary:
	var stats:={"minimum_r":INF,"maximum_r":-INF,"minimum_g":INF,"maximum_g":-INF,"over_255":0,"nonfinite":0,"negative":0,"samples":[]}
	var values:=bytes.to_float32_array()
	for i in values.size()/2:
		var r: float=values[i*2];var g: float=values[i*2+1]
		stats.minimum_r=minf(stats.minimum_r,r);stats.maximum_r=maxf(stats.maximum_r,r)
		stats.minimum_g=minf(stats.minimum_g,g);stats.maximum_g=maxf(stats.maximum_g,g)
		if not is_finite(r) or not is_finite(g):stats.nonfinite+=1
		if r<0 or g<0:stats.negative+=1
		if r>255:
			stats.over_255+=1
			if stats.samples.size()<8:stats.samples.append({"cell":i,"r":r,"g":g,"r_bits":bytes.decode_u32(i*8)})
	return stats

func _run() -> void:
	preview=load("res://scenes/playable/test1_capture.tscn").instantiate();preview.playing=false;root.add_child(preview)
	var end:=Time.get_ticks_msec()+60000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<end:await process_frame
	check("front_ready",preview.ready_for_ticks and preview.last_error.is_empty())
	if preview.ready_for_ticks:
		var baseline: Dictionary=await preview.capture_async_checkpoint_data()
		check("front_baseline",baseline.error.is_empty())
		RenderingServer.call_on_render_thread(_fixture_render)
		while not fixture_registered or (fixture_ok and not fixture_done):await process_frame
		check("front_original_shader_fixture",fixture_ok and fixture_bytes.size()==65536*8)
		if fixture_ok:
			var stats:=front_stats(fixture_bytes)
			print("FRONT_ORIGINAL_GPU ",JSON.stringify(stats))
			check("front_fixture_roundoff_observed",stats.over_255>0 and stats.maximum_r<255.01 and stats.nonfinite==0 and stats.negative==0)
			var fixture: Dictionary=baseline.checkpoint.duplicate(true)
			fixture.native.histories.local_front=fixture_bytes
			var error: StringName=Snapshot.validate(fixture,preview.source_signature)
			check("front_original_output_accepted",error.is_empty())
			for fault in ["nan_r","inf_r","negative_r","outside_r","negative_g","inf_g"]:
				var invalid: Dictionary=fixture.duplicate(true)
				var offset:=4 if fault.ends_with("_g") else 0
				var value: float=NAN if fault=="nan_r" else (INF if fault.begins_with("inf") else (-0.00001 if fault.begins_with("negative") else 255.01))
				invalid.native.histories.local_front.encode_float(offset,value)
				check("front_reject_"+fault,Snapshot.validate(invalid,preview.source_signature)==&"invalid_pipeline_local_front")
			if error.is_empty():
				check("front_restore_raw_history",(await preview.restore_gpu_checkpoint_data(fixture)).is_empty())
				var roundtrip: Dictionary=await preview.capture_async_checkpoint_data()
				check("front_roundtrip_byte_exact",roundtrip.error.is_empty() and roundtrip.checkpoint.native.histories.local_front==fixture_bytes)
			front_evidence.fixture={"stats":stats,"raw_sha256":digest(fixture_bytes),"codec_error":String(error),"input":"only x=255 has water; all contributing q.x=255, exact centroid=255; per-row depths=0.01+0.0007*((z*17+3)%29)","original_x_spirv_sha256":digest(preview.local_front_x_spirv.get_stage_bytecode(RenderingDevice.SHADER_STAGE_COMPUTE)),"original_z_spirv_sha256":digest(preview.local_front_z_spirv.get_stage_bytecode(RenderingDevice.SHADER_STAGE_COMPUTE))}
			RenderingServer.call_on_render_thread(_fixture_release_render)
			while not fixture_released:await process_frame
			check("front_fixture_released",fixture_solver.rd==null and fixture_front.rd==null and fixture_foam.rd==null)
			await mixed_block(1)
			var actual=Capture.new(preview)
			var captured: Dictionary=await actual.capture()
			var natural:=front_stats(actual.metadata.native.histories.local_front)
			print("FRONT_NATURAL ",captured.error," ",JSON.stringify(natural))
			check("front_natural_capture",captured.error.is_empty())
			front_evidence.natural={"stats":natural,"codec_error":String(captured.error),"tick":preview.completed_ticks,"state_seq":preview.async_controller.state_seq}
		front_evidence.configuration=preview.source_signature;front_evidence.loaded_scripts=loaded_code()
	await preview.shutdown()
	check("front_shutdown",preview.gpu_release_done and preview.solver.rd==null)
	preview.queue_free();await process_frame
	var log_text:=FileAccess.get_file_as_string(output.get_basename()+".log")
	check("front_no_engine_errors",not log_text.contains("SCRIPT ERROR:") and not log_text.contains("\nERROR:"))
	var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify({"pass":not failed,"checks":checks,"evidence":front_evidence},"\t"));file.close()
	quit(1 if failed else 0)
