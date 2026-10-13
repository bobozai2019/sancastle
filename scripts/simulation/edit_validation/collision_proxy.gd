extends "res://scripts/collision/gpu_collision_proxy.gd"
signal pack_submitted

var observe_bindings := false
var binding_history := []
var applied_history := []
var retry_queued := false
var readback_callback_us := -1

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
	readback_callback_us=Time.get_ticks_usec()
	super._on_data_render(data)

func _retry_after_frame() -> void:
	await get_tree().process_frame
	retry_queued=false
	if not closing: RenderingServer.call_on_render_thread(_dispatch_pending_render)

func _replace_chunk_shape(chunk_id: int, revision: int, values: PackedFloat32Array) -> void:
	super._replace_chunk_shape(chunk_id,revision,values)
	if observe_bindings: applied_history.append({"chunk":chunk_id,"revision":revision,"generation":generation,"apply_us":Time.get_ticks_usec()})
