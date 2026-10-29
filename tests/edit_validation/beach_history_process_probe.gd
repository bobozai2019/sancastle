extends SceneTree

const Store=preload("res://scripts/simulation/checkpoint_store.gd")
const Native=preload("res://scripts/simulation/edit_validation/gpu_checkpoint_codec.gd")
const BeachCodec=preload("res://scripts/simulation/edit_validation/beach_native_codec.gd")
var output := ""
var mode := "write"
var source := ""
var preview
var data := {}
var rows := []
var finished := false

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
		if arg.begins_with("--checkpoint-mode="): mode=arg.trim_prefix("--checkpoint-mode=")
		if arg.begins_with("--checkpoint-source="): source=arg.trim_prefix("--checkpoint-source=")
	call_deferred("_run");call_deferred("_watchdog")

func _watchdog() -> void:
	var start:=Time.get_ticks_msec()
	while not finished:
		if Time.get_ticks_msec()-start>150000: _write(false,"timeout");quit(1);return
		await process_frame

func _write(ok: bool, error: String="") -> void:
	var f:=FileAccess.open(output.path_join("beach_history_process_probe.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify({"pass":ok,"rows":rows,"error":error,"mode":mode,"source":source,"scope":"full original beach load without edits, native physics and both foam/bed histories; GPU edit integration pending"},"\t"))

func _read() -> void:
	for field in Native.FIELD_BYTES: preview.solver.request_data(field,_on_data.bind(field))
	for index in 2:
		preview.foam_field.rd.texture_get_data_async(preview.foam_field.textures[index],0,_on_data.bind("foam_%d" % index))
		preview.foam_field.rd.texture_get_data_async(preview.foam_field.bed_textures[index],0,_on_data.bind("bed_%d" % index))
	preview.local_front_field.request_data(_on_data.bind("local_front"))

func _on_data(bytes: PackedByteArray, key: String) -> void: call_deferred("_record",bytes,key)
func _record(bytes: PackedByteArray, key: String) -> void: data[key]=bytes

func _snapshot(prefix: String) -> bool:
	data.clear();RenderingServer.call_on_render_thread(_read)
	while data.size()<15: await process_frame
	var exact:=true
	for key in data:
		var f:=FileAccess.open(output.path_join(prefix+"_"+key+".bin"),FileAccess.WRITE);f.store_buffer(data[key]);f.close()
		if mode=="read": exact=exact and data[key]==FileAccess.get_file_as_bytes(source.path_join(prefix+"_"+key+".bin"))
	await process_frame;await process_frame
	root.get_texture().get_image().save_png(output.path_join(prefix+".png"))
	if mode=="read":
		var a:=Image.load_from_file(output.path_join(prefix+".png"));var b:=Image.load_from_file(source.path_join(prefix+".png"))
		exact=exact and a.get_size()==b.get_size() and a.get_data()==b.get_data()
	return exact

func _ticks(count: int) -> void:
	# Explicit completed ticks, using the original full-load dispatch path.
	for i in count:
		preview._start_tick()
		while preview.tick_pending and preview.last_error.is_empty(): await process_frame

func _run() -> void:
	root.size=Vector2i(1920,1080)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	preview=load("res://tests/edit_validation/edit_beach_checkpoint_lab.tscn").instantiate()
	preview.playing=false
	if mode=="read":
		var loaded:=Store.load(source.path_join("full_beach_checkpoint.scp"))
		if not loaded.error.is_empty(): _write(false,String(loaded.error));finished=true;quit(1);return
		var valid:=BeachCodec.validate(loaded.checkpoint)
		if not valid.is_empty(): _write(false,String(valid));finished=true;quit(1);return
		for mutation in ["spare_size","half_nan","foam_nan","index","projection"]:
			var bad: Dictionary=loaded.checkpoint.duplicate(true)
			match mutation:
				"spare_size": bad.gpu_beach_native.spare.sand.resize(4)
				"half_nan": bad.gpu_beach_native.spare.wetness.encode_u16(0,0x7e00)
				"foam_nan": bad.gpu_beach_native.foam.foam_0.encode_float(0,NAN)
				"index": bad.gpu_beach_native.current_index=2
				"projection": bad.fields.water[0]+=1.0
			var rejected:=BeachCodec.validate(bad)
			rows.append({"case":"preflight_"+mutation,"pass":not rejected.is_empty(),"error":String(rejected)})
		preview.replay_checkpoint=loaded.checkpoint;preview.replay_prefix_commands=loaded.prefix_commands;preview.replay_target_tick=loaded.checkpoint.tick
	root.add_child(preview)
	while not preview.ready_for_ticks and preview.last_error.is_empty(): await process_frame
	if mode=="read":
		while not preview.replay_ready and preview.last_error.is_empty(): await process_frame
		preview.replay_target_tick=-1
	else:
		await _ticks(15)
		var error: StringName=preview.request_checkpoint_save(output.path_join("full_beach_checkpoint.scp"))
		while not preview.pending_save_path.is_empty() and preview.last_error.is_empty(): await process_frame
		rows.append({"case":"full_beach_capture","pass":error==&"" and preview.last_save_error==&"" and preview.checkpoints[-1].gpu_beach_native.fields.size()==10,"tick":preview.completed_ticks,"wave_count":preview.wave_requests.size()})
	var first: bool=await _snapshot("checkpoint")
	rows.append({"case":"full_physics_and_visual_history_at_checkpoint","pass":first,"tick":preview.completed_ticks,"foam_index":preview.foam_field.current_index,"histories":15})
	await _ticks(7)
	var continued: bool=await _snapshot("continued")
	rows.append({"case":"full_load_seven_tick_continuation","pass":continued and preview.completed_ticks==22 and preview.wave_requests.size()==80,"tick":preview.completed_ticks})
	var ok: bool=preview.last_error.is_empty()
	for row in rows: ok=ok and row.pass
	_write(ok,preview.last_error);preview.queue_free()
	for i in 6: await process_frame
	finished=true;print("BEACH_HISTORY_PROCESS_COMPLETE mode=%s pass=%s" % [mode,str(ok)]);quit(0 if ok else 1)
