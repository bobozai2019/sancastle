extends "res://tests/integration/unified_edit_playable_probe.gd"

var variants: Dictionary={}

func _hash_value(value: Variant) -> Variant:
	if typeof(value)==TYPE_PACKED_BYTE_ARRAY:return {"bytes":value.size(),"sha256":Codec.Old.digest(value).hex_encode()}
	if value is Dictionary:
		var result:={}
		for key in value:result[key]=_hash_value(value[key])
		return result
	return value

func _run_variant(count: int) -> Dictionary:
	scene=load("res://scenes/main.tscn").instantiate();scene.playing=false
	if count==0:scene.get_node("FloatingProps").free()
	root.add_child(scene)
	var deadline:=Time.get_ticks_msec()+90000
	while (scene._booting or not scene.ready_for_ticks) and scene.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check("isolation_ready_"+str(count),not scene._booting and scene.ready_for_ticks)
	scene.set_process(false)
	if count==3:check("isolation_props_consume_approved_time",(await scene.floating_props.set_paused(false,&"user")).error.is_empty())
	for index in 12:
		if index in [3,8]:
			var selected: StringName=&"fill_v1" if index==3 else &"dig_v1";var profile: Dictionary=scene.registry.profile(selected)
			var command:={"domain_id":"main_beach","generation":scene.runtime.generation(),"command_id":scene.runtime.highwater()+1,"sim_tick":scene.runtime.current.completed_tick,"profile_id":selected,"profile_version":1,"profile_hash":profile.profile_hash,"start_xz_m":Vector2(3,3),"parameters":{"amount_m3":0.02,"radius_m":0.5},"features":{"water_policy":3}}
			check("same_edit_admitted_"+str(count)+"_"+str(index),scene.runtime.submit_intent(command).accepted)
			await _idle()
		check("same_water_admitted_"+str(count)+"_"+str(index),scene.runtime.request_tick(1.0/30.0).is_empty());await _idle()
	var path:=output.get_base_dir()+"/authority_"+str(count)+".sandue"
	check("isolation_snapshot_"+str(count),(await scene.save_gpu_checkpoint(path)).is_empty())
	var loaded:=Codec.load(path,scene.configuration);check("isolation_native_valid_"+str(count),loaded.error.is_empty())
	var value: Dictionary=loaded.checkpoint
	var result:={"native":value.native,"ledger":value.ledger,"clock":[value.state_seq,value.sim_tick,value.revision,value.advanced_time_s],"configuration":value.configuration,"snapshot":path}
	if count==3:check("three_real_props_advanced_without_feedback",scene.floating_props.actual_time.values().all(func(time):return time>0.3) and scene.floating_props.last_error.is_empty())
	await scene.shutdown();check("isolation_release_"+str(count),scene.unified_release_complete())
	var hub=root.get_node("BeachScenes")
	if hub.active_scene==scene:hub.active_scene=null
	root.remove_child(scene);scene.free();scene=null;await process_frame;await process_frame
	return result

func _run() -> void:
	orphan_baseline=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT));DisplayServer.window_set_size(Vector2i(1280,720))
	for count in [0,3]:variants[count]=await _run_variant(count)
	check("authority_native_all_raw_groups_identical",variants[0].native==variants[3].native)
	check("authority_ledger_and_completed_clocks_identical",variants[0].ledger==variants[3].ledger and variants[0].clock==variants[3].clock)
	var hashes:={}
	for count in variants:
		var row: Dictionary=variants[count];var groups: Dictionary=_hash_value(row.native)
		hashes[count]={"groups":groups,"ledger":row.ledger,"clock":row.clock,"configuration":row.configuration,"snapshot":row.snapshot}
	observations.authority=hashes
	check("no_orphans_after_both_variants",int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))<=orphan_baseline)
	finish()

func finish() -> void:
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"checks":checks,"observations":observations,"scope":"G6 same source, seed and serial admitted input; 0 versus 3 real integrating bodies, all native authority groups/control, ledgers and exact completed clocks. No cost claim."},"\t"));quit(1 if failed else 0)
