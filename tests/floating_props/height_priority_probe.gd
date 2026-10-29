extends "res://tests/integration/unified_edit_height_probe.gd"

var marked:=false

func _mark_complete_height_render() -> void:
	# Test-only metadata invalidation, identical to initial Height channel mark.
	# No physical texture/control write, and no borrowed slot is reclaimed here.
	pipeline.heights.dispatch("height",pipeline.heights.gpu_slots[0].set,Vector3i.ONE,pipeline.heights._push(0))
	call_deferred("_mark_done")
func _mark_done() -> void:marked=true

func _consumer_extension() -> void:
	var heights=pipeline.heights;var priority: Array[int]=[]
	for index in 12:priority.append(index)
	check("priority_twelve_accepted",heights.set_footprint_priority(priority,heights.generation,7).is_empty())
	var before: PackedByteArray=heights.priority_mask.duplicate()
	var duplicate: Array[int]=[1,1];var excess: Array[int]=[]
	for index in 13:excess.append(index)
	check("duplicate_priority_rejected",heights.set_footprint_priority(duplicate,heights.generation,7)==&"invalid_footprint")
	check("excess_priority_rejected",heights.set_footprint_priority(excess,heights.generation,7)==&"invalid_footprint")
	check("stale_priority_owner_rejected",heights.set_footprint_priority(priority,heights.generation,6)==&"stale_owner")
	check("stale_priority_generation_rejected",heights.set_footprint_priority(priority,heights.generation+1,7)==&"stale_generation")
	check("invalid_priority_does_not_mutate",heights.priority_mask==before)
	var serial_before: int=heights.serial
	RenderingServer.call_on_render_thread(_mark_complete_height_render)
	while not marked:await process_frame
	heights.notify_complete();await settle_heights()
	var target: int=pipeline.completed_state_seq
	check("priority_does_not_starve_any_of_64_chunks",heights.applied_state_seq.size()==64 and heights.applied_state_seq.values().all(func(version):return version>=target))
	var captures: Array=[]
	for event in heights.events:
		if event.event==&"capture" and event.identity.snapshot_seq>serial_before:captures.append(event)
	check("priority_snapshot_capacity_preserved",not captures.is_empty() and captures.all(func(event):return event.detail.chunks.size()<=16))
	var empty: Array[int]=[]
	check("priority_clear_accepted",heights.set_footprint_priority(empty,heights.generation,7).is_empty() and heights.priority_mask==PackedByteArray([0,0,0,0,0,0,0,0]))
	observations.footprint_priority={"target":target,"captures":captures,"applied":heights.applied_state_seq.duplicate(),"invalid_mask_preserved":before}
	var chunk:=0;var version: int=heights.applied_state_seq[chunk];var upper: float=heights.applied_change_bounds[chunk]
	var exact:={chunk:version};var future:={chunk:version+1};var small:={chunk:upper+0.001};var large:={chunk:upper+0.02}
	check("strict_future_version_still_waits",not heights.footprint_ready(future,heights.generation).ready)
	check("bounded_small_temporal_difference_compatible",heights.footprint_compatible(future,small,heights.generation,0.005).ready)
	check("large_temporal_difference_holds",not heights.footprint_compatible(future,large,heights.generation,0.005).ready)
	check("unknown_temporal_difference_holds",not heights.footprint_compatible(future,{chunk:-1.0},heights.generation,0.005).ready)
	check("compatible_generation_still_exact",not heights.footprint_compatible(exact,{chunk:upper},heights.generation+1,0.005).ready)
