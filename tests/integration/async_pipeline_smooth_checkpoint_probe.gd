extends "res://tests/integration/async_pipeline_delivery_probe.gd"

const Capture=preload("res://scripts/simulation/edit_validation/frame_pipeline/async_checkpoint_capture.gd")
var smooth_evidence:={}

func material_diagnostics(snapshot: Dictionary) -> Dictionary:
	var result:={"current":{},"spare":{}}
	for group in ["current","spare"]:
		var sand: PackedFloat32Array=(snapshot.native.fields.sand if group=="current" else snapshot.native.spare.sand).to_float32_array()
		var support: PackedFloat32Array=snapshot.native.material[group+"_support"].to_float32_array()
		var bad:=0;var tagged:=0;var samples:=[]
		for i in 65536:
			var tag: float=support[i*2];var reference: float=support[i*2+1]
			if tag>0:tagged+=1
			if tag<0 or tag>sand[i] or (reference!=sand[i] if tag>0 else reference!=0):
				bad+=1
				if samples.size()<8:samples.append({"cell":i,"sand":sand[i],"tag":tag,"reference":reference})
		result[group]={"invalid":bad,"tagged":tagged,"samples":samples}
	result.pair_equal=snapshot.native.material.current_support==snapshot.native.material.spare_support
	return result

func _run() -> void:
	preview=load(scene_path).instantiate();preview.playing=false;root.add_child(preview)
	var end:=Time.get_ticks_msec()+60000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<end:await process_frame
	check("smooth_ready",preview.ready_for_ticks and preview.async_pipeline_enabled and preview.last_error.is_empty())
	if preview.ready_for_ticks:
		await controlled_tool(0)
		var before_job=Capture.new(preview)
		var before: Dictionary=await before_job.capture()
		check("smooth_molded_before_valid",before.error.is_empty() and before_job.metadata.native.material.ever_used)
		await controlled_tool(6)
		var after_job=Capture.new(preview)
		var after: Dictionary=await after_job.capture()
		var diagnostics:=material_diagnostics(after_job.metadata)
		print("SMOOTH_CAPTURE_ERROR ",after.error," ",JSON.stringify(diagnostics))
		check("smooth_molded_after_valid",after.error.is_empty())
		check("smooth_material_reference_and_pair",diagnostics.current.invalid==0 and diagnostics.spare.invalid==0 and diagnostics.pair_equal)
		var old_sand: PackedFloat32Array=before_job.metadata.native.fields.sand.to_float32_array()
		var new_sand: PackedFloat32Array=after_job.metadata.native.fields.sand.to_float32_array()
		var old_tag: PackedFloat32Array=before_job.metadata.native.material.current_support.to_float32_array()
		var new_tag: PackedFloat32Array=after_job.metadata.native.material.current_support.to_float32_array()
		var expected:=true;var changed:=0
		for i in 65536:
			if old_sand[i]!=new_sand[i]:changed+=1
			var tag: float=clampf(old_tag[i*2]-maxf(old_sand[i]-new_sand[i],0.0),0.0,new_sand[i])
			if absf(new_tag[i*2]-tag)>0.0000001:expected=false
		check("smooth_real_sand_changed",changed>0)
		check("smooth_existing_tag_loss_rule",expected)
		check("smooth_does_not_change_sand_ledger",before_job.metadata.ledger.sand_source_m3==after_job.metadata.ledger.sand_source_m3 and before_job.metadata.ledger.sand_sink_m3==after_job.metadata.ledger.sand_sink_m3)
		if after.error.is_empty():
			var path:=output.get_basename()+".sandgp"
			check("smooth_save",(await preview.save_gpu_checkpoint(path)).is_empty())
			check("smooth_restore",(await preview.restore_gpu_checkpoint(path)).is_empty())
			var restored: Dictionary=await preview.capture_async_checkpoint_data()
			check("smooth_restored_material",restored.error.is_empty() and restored.checkpoint.native.material==after_job.metadata.native.material and restored.checkpoint.native.fields.sand==after_job.metadata.native.fields.sand)
		smooth_evidence={"error":String(after.error),"before":material_diagnostics(before_job.metadata),"after":diagnostics,"changed_cells":changed,"configuration":preview.source_signature,"loaded_scripts":loaded_code()}
	await preview.shutdown()
	check("smooth_shutdown",preview.gpu_release_done and preview.solver.rd==null)
	preview.queue_free();await process_frame
	var log_text:=FileAccess.get_file_as_string(output.get_basename()+".log")
	check("smooth_no_engine_errors",not log_text.contains("SCRIPT ERROR:") and not log_text.contains("\nERROR:"))
	var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify({"pass":not failed,"checks":checks,"evidence":smooth_evidence},"\t"));file.close()
	quit(1 if failed else 0)
