extends "res://scripts/collision/gpu_collision_proxy.gd"
signal pack_submitted

var observe_bindings := false
var binding_history := []
var applied_history := []
var retry_queued := false
var readback_callback_us := -1
var async_failure_callback: Callable
var failed_readback_owned:=false
var terminal_running:=false
var inject_readback_failure_once:=false
var native_readback_pending:=false
var terminal=preload("res://scripts/simulation/edit_validation/frame_pipeline/async_terminal_guard.gd").new()

func _request_staging_readback() -> Error:
	var result: Error=ERR_UNAVAILABLE
	if inject_readback_failure_once:inject_readback_failure_once=false
	else:result=super._request_staging_readback()
	if result!=OK and async_failure_callback.is_valid():
		failed_readback_owned=true
		closing=true
		pending_revisions.clear()
		call_deferred("_drain_failed_readback")
	elif result==OK:native_readback_pending=true
	return result

func _report_failure(message: String) -> void:
	if not async_failure_callback.is_valid():super._report_failure(message);return
	closing=true
	pending_revisions.clear()
	if staging_texture.is_valid() and not native_readback_pending and not failed_readback_owned:
		failed_readback_owned=true
		_drain_failed_readback()
	invalid_readbacks+=1
	async_failure_callback.call("GPU pipeline fatal: legacy "+message)

func _drain_failed_readback() -> void:
	if not failed_readback_owned or terminal_running:return
	terminal_running=true
	terminal.begin("final")
	while terminal.pending:await get_tree().process_frame
	if not terminal.unconfirmed_ownership:
		RenderingServer.call_on_render_thread(_discard_failed_snapshot)
	terminal_running=false

func _discard_failed_snapshot() -> void:
	if not failed_readback_owned or not terminal.confirmed or rd==null:return
	# There was no native readback callback. The ordered proof, not empty data,
	# authorizes releasing only this failed immutable snapshot. Old shapes stay.
	for rid in [uniform_set,staging_texture]:
		if rid.is_valid():rd.free_rid(rid)
	uniform_set=RID();staging_texture=RID()
	active_chunks=PackedInt32Array();active_queued_usec=PackedInt64Array()
	call_deferred("_failed_snapshot_discarded")

func _failed_snapshot_discarded() -> void:failed_readback_owned=false

func retry_failed_readback() -> void:
	if failed_readback_owned and not terminal_running:_drain_failed_readback()

func _release_render() -> void:
	if failed_readback_owned or terminal_running or not terminal.release_render():return
	super._release_render()

func request_chunks_render(chunks: PackedInt32Array, revision: int, token: int) -> bool:
	if solver==null or revision>solver.state_revision: return false
	return super.request_chunks_render(chunks,revision,token)

func _dispatch_pending_render() -> void:
	if closing or rd==null: return
	if solver!=null and "receipt_pending" in solver and (solver.receipt_pending or solver.publication_pending):
		if not retry_queued:
			retry_queued=true;call_deferred("_retry_after_frame")
		return
	var already_active:=staging_texture.is_valid()
	var queued_revisions:=pending_revisions.duplicate()
	var captured_revision: int=solver.state_revision if solver!=null else -1
	super._dispatch_pending_render()
	if not already_active and staging_texture.is_valid() and not active_chunks.is_empty():
		var requested_revision:=active_revision
		active_revision=captured_revision
		if observe_bindings:
			var requests:=[]
			for chunk in active_chunks: requests.append(int(queued_revisions[chunk]))
			binding_history.append({"requested_revision":requested_revision,"requested_by_chunk":requests,"captured_revision":captured_revision,"generation":generation,"chunks":Array(active_chunks),"bind_us":Time.get_ticks_usec(),"receipt_pending":solver.receipt_pending,"publication_pending":solver.publication_pending})
			call_deferred("_notify_pack")

func _notify_pack() -> void: pack_submitted.emit()

func _on_data_render(data: PackedByteArray) -> void:
	if rd==null or failed_readback_owned:return
	native_readback_pending=false
	readback_callback_us=Time.get_ticks_usec()
	super._on_data_render(data)

func _retry_after_frame() -> void:
	await get_tree().process_frame
	retry_queued=false
	if not closing: RenderingServer.call_on_render_thread(_dispatch_pending_render)

func _replace_chunk_shape(chunk_id: int, revision: int, values: PackedFloat32Array) -> void:
	super._replace_chunk_shape(chunk_id,revision,values)
	if observe_bindings: applied_history.append({"chunk":chunk_id,"revision":revision,"generation":generation,"apply_us":Time.get_ticks_usec()})
