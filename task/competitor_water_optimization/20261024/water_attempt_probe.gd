extends SceneTree

# Read-only asynchronous decision sampling. Not a cost benchmark.
var beach
var output:="res://test_output/water_attempt_probe"
var tail: Callable
var recorded:=0
var requested:=0
var samples: Array=[]

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	call_deferred("run")

func record_tail(decision: RID) -> void:
	tail.call(decision)
	recorded+=1
	if recorded%16==0:
		requested+=1
		var error: Error=beach.runtime.current.state.rd.buffer_get_data_async(decision,received_render.bind(recorded))
		if error!=OK:received_render(PackedByteArray(),recorded)

func received_render(bytes: PackedByteArray, index: int) -> void:
	received.call_deferred(bytes,index)

func received(bytes: PackedByteArray, index: int) -> void:
	var row:={"recorded_tick_index":index,"raw_hex":bytes.hex_encode(),"bytes":bytes.size()}
	if bytes.size()==64:
		row.accepted=bytes.decode_u32(4);row.rejected=bytes.decode_u32(40)
		row.advanced_s=bytes.decode_float(12);row.requested_s=bytes.decode_float(24)
		row.status=bytes.decode_u32(16)
	samples.append(row)

func run() -> void:
	beach=load("res://scenes/playable/test1_geometry.tscn").instantiate();root.add_child(beach);current_scene=beach
	var deadline:=Time.get_ticks_msec()+90000
	while (not beach.ready_for_ticks or beach._booting) and beach.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	if not beach.ready_for_ticks:push_error(str(beach.last_error));quit(1);return
	var service=root.get_node("Parameters")
	for group in service.GROUPS:service.get_node(group).hide()
	root.grab_focus()
	await create_timer(5.0).timeout
	RenderingServer.call_on_render_thread(func():tail=beach.runtime.current.water.tail_recorder;beach.runtime.current.water.tail_recorder=record_tail)
	await create_timer(20.0).timeout
	beach.playing=false
	var p=beach.runtime.current
	deadline=Time.get_ticks_msec()+30000
	while (p.pending_count()>0 or p.active_count()>0 or samples.size()<requested) and Time.get_ticks_msec()<deadline:await process_frame
	RenderingServer.call_on_render_thread(func():p.water.tail_recorder=tail)
	var result:={"scene":"res://scenes/playable/test1_geometry.tscn","configuration":beach.configuration,"samples":samples,"sample_stride_ticks":16,"requested_samples":requested,"last_error":beach.last_error,"note":"Read-only asynchronous 64-byte decision snapshots at the original tail callback position; no GPU timestamps, no cost claim; original tail invoked unchanged","source_drift":[]}
	for path in beach.configuration.sources:
		if FileAccess.get_sha256(path)!=beach.configuration.sources[path]:result.source_drift.append(path)
	result.pass=not samples.is_empty() and samples.size()==requested and samples.all(func(row):return row.bytes==64 and row.status==0) and result.last_error.is_empty() and result.source_drift.is_empty()
	DirAccess.make_dir_recursive_absolute(output)
	FileAccess.open(output.path_join("attempts.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	await beach.shutdown();tail=Callable()
	print("WATER_ATTEMPTS ",result.pass," samples=",samples.size())
	quit(0 if result.pass else 1)
