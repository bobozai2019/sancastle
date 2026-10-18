extends SceneTree

const Editor = preload("res://scripts/simulation/edit_validation/frame_pipeline/async_editor.gd")
const Slots = preload("res://scripts/simulation/edit_validation/frame_pipeline/async_slots.gd")
const Wire = preload("res://scripts/simulation/edit_validation/edit_protocol.gd")
const FIELDS = ["sand","water","sediment","momentum_x","momentum_z","mold_support","compaction"]
var preview
var editor := Editor.new()
var pool
var output := ""
var checks := []
var failed := false
var initialized := false
var initialize_ok := false
var callbacks := {}
var reads := {}
var remaining := 0
var serial := 0
var released := false
var wet_point := Vector3.ZERO
var diagnostic_bytes := {}
var with_mold := true

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
		if arg=="--no-mold": with_mold=false
	call_deferred("_run")

func check(label: String, value: bool) -> void:
	checks.append({"name":label,"pass":value})
	failed=failed or not value
	print("ASYNC_EDIT ",label," ",value)

func _initialize_render() -> void:
	editor.edit_spirvs=preview.edit_spirvs
	editor.water_spirvs=preview.water_spirvs
	editor.local_dispatch=true
	editor.fast_full_wet=preview.solver.fast_full_wet
	editor.connected_runs=preview.solver.connected_runs
	initialize_ok=editor.initialize(RenderingServer.get_rendering_device(),preview.shadow_domain,
		preview.spirvs[0],preview.spirvs[1],preview.spirvs[2],preview.spirvs[3],preview.spirvs[4],preview.spirvs[5],preview.spirvs[6],preview.spirvs[7])
	if initialize_ok: initialize_ok=editor.enable_async(true)
	call_deferred("_initialized")

func _initialized() -> void:
	initialized=true

func make(point: Vector3, kind: StringName=&"place_sand") -> PackedByteArray:
	serial+=1
	var cmd := {"command_id":serial,"generation":preview.generation,"sim_tick":0,"kind":kind,"shape":&"circle",
		"transform":{"position_m":point},"radius_m":0.3,"strength":1.0,"amount_m3":0.015,"seed":101}
	# Deliberately wrong speculative revision: async select must use GPU live state.
	return Wire.encode(cmd,serial,999+serial,256,0.125,3,0.015001,0.25)

func _submit_render(id: Dictionary, envelopes: Array, inject_water: bool) -> void:
	editor.inject_water_loss_once=inject_water
	var error := editor.dispatch_async_batch(id,envelopes,_arrived)
	if not error.is_empty(): call_deferred("_transport_error",error)

func _transport_error(error: String) -> void:
	check("transport_error_"+error,false)

func _arrived(bytes: PackedByteArray, id: Dictionary) -> void:
	call_deferred("_receive",bytes,id)

func _receive(bytes: PackedByteArray, id: Dictionary) -> void:
	check("completion_%d" % id.batch_seq,pool.completed(bytes,id).is_empty())
	callbacks[id.batch_seq]=id

func submit(envelopes: Array, inject_water: bool=false) -> Dictionary:
	var acquired: Dictionary=pool.acquire()
	check("acquired",acquired.error.is_empty())
	if not acquired.error.is_empty(): return {}
	var id: Dictionary=acquired.identity
	check("submitted_%d" % id.batch_seq,pool.submitted(id))
	RenderingServer.call_on_render_thread(_submit_render.bind(id,envelopes,inject_water))
	return id

func wait_batch(id: Dictionary, count: int, allow_error: bool=false) -> Array:
	var deadline := Time.get_ticks_msec()+30000
	while not callbacks.has(id.batch_seq) and not failed and Time.get_ticks_msec()<deadline: await process_frame
	check("finished_%d" % id.batch_seq,callbacks.has(id.batch_seq))
	if not callbacks.has(id.batch_seq): return []
	# Diagnostics are test-only and never gate normal dispatch. Keep this lease
	# until this extra probe consumer has read the immutable per-slot receipt.
	RenderingServer.call_on_render_thread(_diagnostic_render.bind(id,count))
	while not diagnostic_bytes.has(id.batch_seq) and Time.get_ticks_msec()<deadline: await process_frame
	var bytes: PackedByteArray=diagnostic_bytes.get(id.batch_seq,PackedByteArray())
	check("diagnostic_size_%d" % id.batch_seq,bytes.size()==count*128)
	var results := []
	for index in count:
		var result := Wire.decode_receipt(bytes.slice(index*128,(index+1)*128))
		check("receipt_valid_%d_%d" % [id.batch_seq,index],result.get("ok",false))
		results.append(result)
	var completion: Dictionary=pool.consume(id)
	check("complete_without_cpu_publication_%d" % id.batch_seq,completion.error.is_empty() and (completion.error_flags>0 if allow_error else completion.error_flags==0) and not editor.receipt_pending and not editor.publication_pending and not editor.receipt_batch_open)
	RenderingServer.call_on_render_thread(_retire_render.bind(id))
	return results

func _diagnostic_render(id: Dictionary, count: int) -> void:
	editor.rd.buffer_get_data_async(editor.async_resources[id.slot_id].diagnostic,_diagnostic_ready.bind(id.batch_seq),0,count*128)

func _diagnostic_ready(bytes: PackedByteArray, batch: int) -> void:
	call_deferred("_diagnostic_store",bytes,batch)

func _diagnostic_store(bytes: PackedByteArray, batch: int) -> void:
	diagnostic_bytes[batch]=bytes

func _retire_render(id: Dictionary) -> void:
	if not editor.retire_async(id): call_deferred("_transport_error","retire")

func snapshot() -> Dictionary:
	reads={}
	remaining=14
	RenderingServer.call_on_render_thread(_read_render)
	var deadline := Time.get_ticks_msec()+30000
	while remaining>0 and Time.get_ticks_msec()<deadline: await process_frame
	check("snapshot_complete",remaining==0)
	return reads.duplicate(true)

func _read_render() -> void:
	for field in FIELDS:
		for index in 2: editor.rd.texture_get_data_async(editor.textures[field][index],0,_read_arrived.bind(field+str(index)))

func published() -> Dictionary:
	reads={}
	remaining=2
	RenderingServer.call_on_render_thread(_read_published_render)
	var deadline := Time.get_ticks_msec()+30000
	while remaining>0 and Time.get_ticks_msec()<deadline: await process_frame
	check("published_read_complete",remaining==0)
	return reads.duplicate(true)

func _read_published_render() -> void:
	editor.rd.texture_get_data_async(editor.published_sand,0,_read_arrived.bind("sand"))
	editor.rd.texture_get_data_async(editor.published_water,0,_read_arrived.bind("water"))

func _read_arrived(bytes: PackedByteArray, key: String) -> void:
	call_deferred("_read_store",bytes,key)

func _read_store(bytes: PackedByteArray, key: String) -> void:
	reads[key]=bytes
	remaining-=1

func compare(label: String, before: Dictionary, after: Dictionary) -> void:
	for field in before: check(label+"_"+field,after.get(field)==before[field])

func _reset_render(fields: Dictionary) -> void:
	# Test-only restore of exact initial authority; production recovery is P06.
	for field in FIELDS:
		for index in 2:
			var target: RID=editor.textures[field][index]
			var source: RID=editor.rd.texture_create(editor.rd.texture_get_format(target),RDTextureView.new(),[fields[field+str(index)]])
			editor.rd.texture_copy(source,target,Vector3.ZERO,Vector3.ZERO,Vector3(256,256,1),0,0,0,0)
			editor.rd.free_rid(source)

func _release_render() -> void:
	editor.release()
	call_deferred("_released")

func _released() -> void:
	released=editor.rd==null

func _run() -> void:
	preview=load("res://scenes/main.tscn").instantiate()
	preview.playing=false
	root.add_child(preview)
	var deadline := Time.get_ticks_msec()+60000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline: await process_frame
	check("main_ready",preview.ready_for_ticks and preview.last_error.is_empty())
	pool=Slots.new(preview.generation)
	# A genuine nonzero molded field exercises material validation and commit.
	var mold := PackedFloat32Array()
	mold.resize(65536)
	var found := false
	for index in 65536:
		mold[index]=preview.shadow_domain.sand[index]*0.5 if with_mold else 0.0
		if not found and preview.shadow_domain.water[index]>0.05 and index%256>10 and index%256<245:
			wet_point=Vector3((index%256+0.5)*0.125-16,0,(index/256+0.5)*0.125-16)
			found=true
	preview.shadow_domain.set_meta("brush_initial_mold_depth",mold)
	check("wet_fixture",found)
	RenderingServer.call_on_render_thread(_initialize_render)
	while not initialized and Time.get_ticks_msec()<deadline: await process_frame
	check("async_editor_ready",initialized and initialize_ok)
	if initialize_ok:
		check("material_fixture_mode",editor.mold_field_ever_used==with_mold)
		var initial: Dictionary=await snapshot()
		var rejected: Array=await wait_batch(submit([make(Vector3(40,0,40)),make(Vector3(40,0,40))]),2)
		check("all_rejected",rejected.size()==2 and rejected.all(func(r):return r.status==2))
		compare("reject_preserves_all_fields",initial,await snapshot())
		var water_rejected: Array=await wait_batch(submit([make(wet_point)],true),1)
		check("water_rejected",water_rejected.size()==1 and water_rejected[0].status==2)
		compare("water_reject_preserves_all_fields",initial,await snapshot())
		var a := make(wet_point)
		var b := make(Vector3(40,0,40))
		var c := make(Vector3(-2,0,0),&"remove_sand")
		var d := make(Vector3(-1,0,1))
		var mixed_id := submit([a,b,c])
		var next_id := submit([d])
		check("next_real_batch_before_cpu_consume",pool.active_count()==2)
		var mixed: Array=await wait_batch(mixed_id,3)
		var next: Array=await wait_batch(next_id,1)
		check("success_reject_success",mixed.size()==3 and mixed[0].status==1 and mixed[1].status==2 and mixed[2].status==1)
		check("next_batch_success",next.size()==1 and next[0].status==1)
		check("revision_uses_live_gpu_state",mixed.size()==3 and mixed[1].input_revision==mixed[0].output_revision and mixed[2].input_revision==mixed[1].output_revision and next[0].input_revision==mixed[2].output_revision)
		var candidate: Dictionary=await snapshot()
		check("real_sand_changed",initial.sand0!=candidate.sand0)
		check("material_behavior",(initial.mold_support0!=candidate.mold_support0)==with_mold)
		var displayed: Dictionary=await published()
		check("gpu_complete_published_sand",displayed.sand==candidate.sand0)
		check("gpu_complete_published_water",displayed.water==candidate.water0)
		check("no_batch_backups",editor.batch_backups.is_empty() and editor.receipt_batch_metrics.backup_texture_count==0)
		RenderingServer.call_on_render_thread(_reset_render.bind(initial))
		# Compare with the same valid command order, across separate work units.
		await wait_batch(submit([a]),1)
		await wait_batch(submit([c]),1)
		await wait_batch(submit([d]),1)
		compare("matches_A_C_D_reference",candidate,await snapshot())
		var prefix_rejected: Array=await wait_batch(submit([make(Vector3(40,0,40)),make(Vector3(40,0,40)),make(Vector3(-2,0,0))]),3)
		check("first_and_consecutive_reject_continue",prefix_rejected.size()==3 and prefix_rejected[0].status==2 and prefix_rejected[1].status==2 and prefix_rejected[2].status==1)
		if with_mold:
			var corrupted := initial.duplicate(true)
			for index in 65536:
				for slot in 2: corrupted["mold_support"+str(slot)].encode_float(index*8,initial.sand0.decode_float(index*4)+1.0)
			RenderingServer.call_on_render_thread(_reset_render.bind(corrupted))
			var fatal: Array=await wait_batch(submit([make(wet_point)]),1,true)
			check("corrupt_material_reports_error",fatal.size()==1 and fatal[0].status==2 and fatal[0].invalid_flags & 256 != 0)
			compare("corrupt_material_no_partial_write",corrupted,await snapshot())
		pool.stop_admission()
		check("pool_drained",pool.can_release())
		RenderingServer.call_on_render_thread(_release_render)
		while not released and Time.get_ticks_msec()<deadline: await process_frame
		check("editor_released",released)
	await preview.shutdown()
	check("main_released",preview.gpu_release_done)
	preview.queue_free()
	await process_frame
	if not output.is_empty():
		var file := FileAccess.open(output,FileAccess.WRITE)
		if file!=null: file.store_string(JSON.stringify({"pass":not failed,"checks":checks,"events":pool.events,"with_mold":with_mold,"scope":"P02 candidate GPU edits; not main integration"},"\t"))
	quit(1 if failed else 0)
