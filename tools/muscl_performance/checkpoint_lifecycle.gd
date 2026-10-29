extends SceneTree

# Targeted round-four lifecycle checks against a real cold-writer checkpoint.
const Pipeline=preload("res://scripts/simulation/unified_edit/pipeline.gd")
const Codec=preload("res://scripts/simulation/unified_edit/checkpoint_codec.gd")
const Config=preload("res://scripts/simulation/unified_edit/configuration.gd")
var owner
var registry
var checkpoint: Dictionary={}
var output:=""
var input:=""
var checks: Array=[]
var cases: Array=[]
var failed:=false
var epoch:=2000
var callback_count:=0
var save_result: Dictionary={}

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		if arg.begins_with("--input="):input=arg.trim_prefix("--input=")
	call_deferred("run")

func _process(_delta: float) -> bool:
	if owner!=null:owner.pump()
	return false

func check(label: String, passed: bool) -> void:
	checks.append({"name":label,"pass":passed});failed=failed or not passed
	print("CHECKPOINT_LIFECYCLE ",label," ",passed)

func wait_until(predicate: Callable, label: String) -> bool:
	var deadline:=Time.get_ticks_msec()+30000
	while not predicate.call() and Time.get_ticks_msec()<deadline:await process_frame
	var passed: bool=predicate.call();check(label,passed);return passed

func create_owner(injection: String="") -> bool:
	epoch+=1;owner=Pipeline.new()
	var configured: StringName=owner.configure_restore(registry,checkpoint.configuration,epoch,checkpoint)
	check("configure:"+injection,configured.is_empty())
	if not configured.is_empty():return false
	if injection in ["restore_hold","restore_cancel"]:owner.restore_verifier.hold_delivery=true
	if injection in ["restore_registration","restore_unknown"]:owner.restore_verifier.inject_registration_failure_once=true
	if injection=="restore_corrupt":owner.restore_verifier.inject_corruption_once=true
	if injection=="restore_unknown":owner.transport.inject_idle_fence_unavailable=true
	if injection.begins_with("partial_"):owner.inject_initialization_failure_after=StringName(injection.trim_prefix("partial_"))
	RenderingServer.call_on_render_thread(owner.initialize_render.bind(owner.restore_domain()))
	if injection in ["restore_hold","restore_cancel"]:
		if not await wait_until(func():return owner.restore_verifier.held.size()==41,"all_41_physical_restore_reads_held"):return false
		check("held_restore_not_ready",not owner.initialized and not owner._ready and owner.restore_verifier.pending==41)
		check("three_physical_momentum_expectations",owner.restore_verifier._expected.has("field/momentum") and owner.restore_verifier._expected.has("spare/momentum") and owner.restore_verifier._expected.has("view/momentum") and not owner.restore_verifier._expected.has("field/momentum_x"))
		if injection=="restore_cancel":check("cancel_held_initialization",owner.cancel_initialization())
		RenderingServer.call_on_render_thread(owner.restore_verifier.release_held_render)
	if not await wait_until(func():return owner.initialized,"restore_terminal:"+injection):return false
	return true

func release_owner(label: String) -> void:
	if owner==null:return
	if not owner.released:
		owner.close_admission()
		await wait_until(func():return owner.pending_count()==0 and owner.active_count()==0,"drain:"+label)
		RenderingServer.call_on_render_thread(owner.release_render)
		await wait_until(func():return owner.released,"release:"+label)
	check("all_owners_zero:"+label,owner.ownership_counts().values().all(func(value):return value==0))
	owner=null

func restore_cases() -> void:
	for name in ["restore_hold","restore_cancel","restore_registration","restore_corrupt","restore_unknown","partial_state","partial_water","partial_coupled","partial_views"]:
		if not await create_owner(name):return
		var record:={"case":name,"ready":owner._ready,"error":String(owner.initialization_error),"verifier_error":String(owner.restore_verifier.error),"pending":owner.restore_verifier.pending,"records":owner.restore_verifier.records.duplicate(true)}
		if name=="restore_hold":
			check("held_restore_releases_to_ready",owner._ready and owner.restore_verifier.passed and owner.restore_verifier.records.size()==41)
		else:
			check("failed_restore_never_ready:"+name,not owner._ready and not owner.initialization_error.is_empty())
			if name=="restore_unknown":
				await wait_until(func():return owner.initialization_cleanup_unknown,"restore_unknown_idle")
				record.unknown_owners=owner.ownership_counts();record.initial_owners=owner.initialization_ownership.duplicate(true)
				check("unknown_restore_retains_all",not owner.released and record.unknown_owners==record.initial_owners)
				RenderingServer.call_on_render_thread(func():owner.transport.inject_idle_fence_unavailable=false)
				owner.retry_initialization_cleanup()
			await wait_until(func():return owner.released,"failed_restore_cleanup:"+name)
			check("failed_restore_readers_drained:"+name,owner.restore_verifier.pending==0)
		cases.append(record);await release_owner(name)
		if failed:return

func saved(value: Dictionary) -> void:callback_count+=1;save_result=value

func capture_cases() -> void:
	for name in ["capture_registration","capture_truncate","capture_cancel","capture_unknown","capture_close"]:
		if not await create_owner():return
		check("capture_fixture_ready",owner._ready)
		var before: Dictionary=owner.ownership_counts()
		callback_count=0;save_result={}
		var destination:=output.path_join(name+".sandue")
		check("capture_admitted:"+name,owner.save_checkpoint(destination,checkpoint.selection,saved).accepted)
		var reader=owner.checkpoint_capture
		if name in ["capture_cancel","capture_close"]:reader.hold_delivery=true
		if name in ["capture_registration","capture_unknown"]:reader.inject_registration_failure_once=true
		if name=="capture_truncate":reader.inject_packet_fault_once="truncate"
		if name=="capture_unknown":RenderingServer.call_on_render_thread(func():owner.transport.inject_idle_fence_unavailable=true)
		if name in ["capture_cancel","capture_close"]:
			if not await wait_until(func():return reader.held.size()==33,"all_33_physical_capture_reads_held"):return
			check("capture_pending_is_physical",reader.pending==33 and reader.registered==33 and reader.expected_sizes.size()==33 and reader.expected_sizes.has("field/momentum") and reader.expected_sizes.has("spare/momentum") and not reader.expected_sizes.has("field/momentum_x"))
			check("capture_retains_owners_while_held",owner.ownership_counts()==before and not owner.released and callback_count==0)
			if name=="capture_cancel":check("cancel_inflight_capture",owner.cancel_checkpoint())
			else:owner.close_admission()
			RenderingServer.call_on_render_thread(reader.release_held_render)
		if name=="capture_unknown":
			if not await wait_until(func():return reader.unknown,"capture_unknown_idle"):return
			check("unknown_capture_keeps_barrier",owner.checkpoint_capture==reader and callback_count==0 and owner.ownership_counts()==before and not owner.released)
			RenderingServer.call_on_render_thread(func():owner.transport.inject_idle_fence_unavailable=false)
			owner.retry_checkpoint_lifetime()
		if not await wait_until(func():return callback_count==1 and owner.checkpoint_capture==null,"capture_terminal_once:"+name):return
		var expected: StringName=&"checkpoint_readback_registration" if name in ["capture_registration","capture_unknown"] else (&"checkpoint_readback_size" if name=="capture_truncate" else &"checkpoint_cancelled")
		check("capture_error:"+name,save_result.error==expected and not FileAccess.file_exists(destination) and reader.pending==0)
		for frame in 3:await process_frame
		check("capture_no_late_recompletion:"+name,callback_count==1)
		cases.append({"case":name,"error":String(save_result.error),"callback_count":callback_count,"registered":reader.registered,"expected_sizes":reader.expected_sizes.duplicate(),"records":reader.records.duplicate(true),"idle_receipt_hex":owner.transport.idle_receipt.hex_encode()})
		await release_owner(name)
		if failed:return

func run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	var loaded:=Codec.read_container(input)
	check("input_container",loaded.error.is_empty())
	if not loaded.error.is_empty():finish();return
	checkpoint=loaded.checkpoint
	check("input_source_identity",Config.validate(checkpoint.configuration,true).is_empty())
	var catalog: Dictionary=load("res://assets/unified_edit/default_catalog.tres").instantiate_registry();registry=catalog.registry
	var bad:=checkpoint.duplicate(true);bad.native.fields.momentum_x=bad.native.fields.momentum_x.slice(0,1)
	var rejected:=Pipeline.new();var rejection: StringName=rejected.configure_restore(registry,checkpoint.configuration,1999,bad)
	check("corrupt_component_length_rejected",not rejection.is_empty() and rejected._registry==null)
	cases.append({"case":"bad_component_length","error":String(rejection)})
	bad=checkpoint.duplicate(true);bad.configuration.sources["res://scripts/simulation/unified_edit/state.gd"]="0".repeat(64);bad.configuration.configuration_hash=Config.stable_hash(bad.configuration)
	rejected=Pipeline.new();rejection=rejected.configure_restore(registry,checkpoint.configuration,1999,bad)
	check("wrong_source_rejected",not rejection.is_empty() and rejected._registry==null)
	cases.append({"case":"wrong_source","error":String(rejection)})
	if not failed:await restore_cases()
	if not failed:await capture_cases()
	finish()

func finish() -> void:
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"checks":checks,"cases":cases,"input":input,"input_sha256":FileAccess.get_sha256(input),"scope":"Real packed restore/capture physical read counts, corrupted length/source, held/cancel/registration/corruption/unknown idle, partial initialization and in-flight capture close; all owners released after proof"},"\t"))
	quit(1 if failed else 0)
