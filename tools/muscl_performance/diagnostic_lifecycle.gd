extends SceneTree

const Observer=preload("res://tools/muscl_performance/diagnostic.gd")
var output:=""
var observer
var checks: Array=[]
var report_ready:=false
var report_data: Dictionary={}

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	call_deferred("run")

func check(name: String, passed: bool) -> void:
	checks.append({"name":name,"pass":passed})

func exercise() -> void:
	var rd:=RenderingServer.get_rendering_device()
	observer=Observer.new()
	check("initialize",observer.initialize(rd))
	observer.enabled=true;observer.stride=1
	# Inject occupied leases without GPU work: no free slot must drop a sample.
	for slot in observer._slots:slot.busy=true
	check("saturated_queue_drops",not observer.begin_tick(true,0.01) and observer.dropped.queue==1)
	for slot in observer._slots:slot.busy=false
	# Real copied-buffer readback, followed by close before it can be delivered.
	var sources: Array[RID]=[]
	for size in [64,2048,128]:sources.append(rd.storage_buffer_create(size))
	check("sample_admitted",observer.begin_tick(true,0.01))
	observer.pass_begin("edge",0,0)
	observer.end_tick(sources[0],sources[1],sources[2])
	check("one_outstanding_readback",observer.pending()==1)
	check("same_frame_budget_drops",not observer.begin_tick(true,0.01) and observer.dropped.budget==1)
	observer.close()
	check("close_keeps_inflight_rid",observer._slots.any(func(slot):return slot.busy and slot.rid.is_valid()))
	check("close_blocks_new_sample",not observer.begin_tick(true,0.01))
	# RD owns submitted operations; disposal follows command ordering, and the
	# observer's copied staging allocation stays alive until its own callback.
	for rid in sources:rd.free_rid(rid)

func poll() -> void:
	if report_ready:return
	if observer.pending()!=0:return
	check("close_delivery_discarded",observer.dropped.closed==1 and observer.snapshot().samples.is_empty())
	check("all_staging_rids_released",observer._slots.all(func(slot):return not slot.rid.is_valid()))
	var failed_read:=Observer.new()
	check("read_failure_fixture",failed_read.initialize(RenderingServer.get_rendering_device()))
	failed_read._slots[0].busy=true
	# Exercise malformed delivery through the real receive validation path.
	failed_read._receive(PackedByteArray(),{"staging_slot":0})
	check("short_read_isolated",failed_read.dropped.readback==1 and failed_read.pending()==0 and failed_read.snapshot().samples.is_empty())
	failed_read.close()
	check("short_read_resources_released",failed_read._slots.all(func(slot):return not slot.rid.is_valid()))
	report_data={"checks":checks,"observer":observer.snapshot(),"scope":"Developer diagnostic ownership/queue/budget/short-read/close; no numerical performance claim"}
	report_ready=true

func run() -> void:
	RenderingServer.call_on_render_thread(exercise)
	var deadline:=Time.get_ticks_msec()+15000
	while not report_ready and Time.get_ticks_msec()<deadline:
		await process_frame
		RenderingServer.call_on_render_thread(poll)
	DirAccess.make_dir_recursive_absolute(output)
	var passed: bool=report_ready and checks.all(func(row):return row.pass)
	FileAccess.open(output.path_join("lifecycle.json"),FileAccess.WRITE).store_string(JSON.stringify({"pass":passed,"report":report_data},"\t"))
	quit(0 if passed else 1)
