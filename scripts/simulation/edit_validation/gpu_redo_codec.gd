extends RefCounted

const Checkpoint=preload("res://scripts/simulation/edit_validation/gpu_checkpoint_codec.gd")
const Protocol=preload("res://scripts/simulation/edit_validation/edit_protocol.gd")

static func digest(data: PackedByteArray) -> String:
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(data)
	return hash.finish().hex_encode()

static func summarize(record: Dictionary) -> Dictionary:
	if record.has("replay_target"): return record.replay_target.duplicate(true)
	var checkpoint: Dictionary=record.replay_checkpoint
	var hashes: Dictionary={}
	for field in Checkpoint.FIELD_BYTES: hashes[field]=digest(checkpoint.gpu_edit_sidecar.raw_fields[field])
	return {"tick":checkpoint.tick,"prefix":checkpoint.gpu_edit_sidecar.prefix.duplicate(true),"ledger":checkpoint.gpu_edit_sidecar.ledger.duplicate(true),"field_sha256":hashes}

static func matches(checkpoint: Dictionary, target: Dictionary) -> bool:
	if checkpoint.tick!=target.tick or checkpoint.gpu_edit_sidecar.ledger!=target.ledger: return false
	for field in Checkpoint.FIELD_BYTES:
		if digest(checkpoint.gpu_edit_sidecar.raw_fields[field])!=target.field_sha256[field]: return false
	return true

static func pack(records: Array) -> Dictionary:
	var pool: Array=[];var indices: Dictionary={};var packed: Array=[]
	for record in records:
		var item: Dictionary={"command":record.command.duplicate(true),"policy":record.policy,"speed":record.speed,"tick":record.tick}
		if record.get("same_tick_transaction",false): item.same_tick_transaction=true
		if record.has("replay_checkpoint") or record.has("replay_target"):
			var target:=summarize(record)
			var references:=PackedInt32Array()
			for entry in target.prefix:
				var key:=digest(var_to_bytes(entry))
				if not indices.has(key): indices[key]=pool.size();pool.append(entry.duplicate(true))
				references.append(indices[key])
			target.erase("prefix");target.prefix_indices=references;item.replay_target=target
		packed.append(item)
	return {"version":1,"prefix_items":pool,"records":packed}

static func unpack(payload: Variant, sidecar: Dictionary, domain_id: StringName) -> Dictionary:
	if not payload is Dictionary or payload.get("version")!=1 or not payload.get("prefix_items") is Array or not payload.get("records") is Array or payload.records.size()>32: return {"error":&"invalid_redo_payload"}
	var records: Array=[]
	for stored in payload.records:
		if not stored is Dictionary or not stored.get("command") is Dictionary: return {"error":&"invalid_redo_record"}
		var finite: Dictionary=stored.command.duplicate(false)
		if finite.get("kind") in [&"smooth",&"compact"] and not finite.has("amount_m3"): finite.amount_m3=0.0
		if not Protocol.finite_command(finite) or stored.command.get("domain_id")!=domain_id or typeof(stored.command.get("command_id"))!=TYPE_INT or stored.command.command_id<1 or stored.command.command_id>sidecar.highwater_id or typeof(stored.get("tick"))!=TYPE_INT or stored.tick<0 or stored.tick>sidecar.tick or stored.get("policy") not in [0,1,2,3] or typeof(stored.get("speed")) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(stored.speed)) or absf(float(stored.speed))>1.0: return {"error":&"invalid_redo_record"}
		var record: Dictionary=stored.duplicate(true)
		if stored.has("same_tick_transaction") and (typeof(stored.same_tick_transaction)!=TYPE_BOOL or not stored.has("replay_target")): return {"error":&"invalid_redo_transaction_mode"}
		if stored.has("replay_target"):
			var target: Variant=stored.replay_target
			if not target is Dictionary or typeof(target.get("tick"))!=TYPE_INT or target.tick<stored.tick or target.tick>sidecar.tick or not target.get("prefix_indices") is PackedInt32Array or not target.get("ledger") is Dictionary or not target.get("field_sha256") is Dictionary or target.field_sha256.size()!=Checkpoint.FIELD_BYTES.size(): return {"error":&"invalid_redo_target"}
			var prefix: Array=[]
			for index in target.prefix_indices:
				if index<0 or index>=payload.prefix_items.size() or not payload.prefix_items[index] is Dictionary: return {"error":&"invalid_redo_reference"}
				prefix.append(payload.prefix_items[index].duplicate(true))
			for field in Checkpoint.FIELD_BYTES:
				var hash: Variant=target.field_sha256.get(field)
				if not hash is String or hash.length()!=64 or not hash.is_valid_hex_number(false): return {"error":&"invalid_redo_hash"}
			var validation: Dictionary=sidecar.duplicate(false);validation.prefix=prefix;validation.ledger=target.ledger;validation.tick=target.tick
			var error: StringName=Checkpoint.validate(validation)
			if not error.is_empty(): return {"error":error}
			for entry in prefix:
				if entry.command.domain_id!=domain_id or not entry.has("available_m3"): return {"error":&"invalid_redo_replay_input"}
			record.replay_target.erase("prefix_indices");record.replay_target.prefix=prefix
		records.append(record)
	return {"error":&"","records":records}
