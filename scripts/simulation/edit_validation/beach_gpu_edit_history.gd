extends RefCounted

const FIELDS=["sand","water","sediment","momentum_x","momentum_z"]
const MAX_RECORDS=32
const MAX_BYTES=96*1024*1024
var records := []
var pending := {}
var bytes_owned := 0
var peak_bytes := 0

func capture(solver, identity: Dictionary) -> bool:
	if solver.rd==null or solver.receipt_pending or solver.publication_pending or not pending.is_empty() or identity.get("generation")!=solver.owner_generation: return false
	if typeof(identity.get("tick"))!=TYPE_INT or identity.tick<0 or typeof(identity.get("command_id"))!=TYPE_INT or identity.command_id<1: return false
	var needed: int=solver.grid_size*solver.grid_size*4*FIELDS.size()*2
	if bytes_owned+needed>MAX_BYTES: return false
	var record: Dictionary={"identity":identity.duplicate(true),"solver_instance_id":solver.get_instance_id(),"index":solver.current_index,"revision":solver.state_revision,"textures":{},"bytes":needed}
	for field in FIELDS:
		var slots: Array[RID]=[]
		record.textures[field]=slots
		for index in 2:
			var rid: RID=solver._create_texture(RenderingDevice.DATA_FORMAT_R32_SFLOAT,PackedByteArray())
			if not rid.is_valid(): _free(solver,record);return false
			slots.append(rid)
			if solver.rd.texture_copy(solver.textures[field][index],rid,Vector3.ZERO,Vector3.ZERO,Vector3(solver.grid_size,solver.grid_size,1),0,0,0,0)!=OK: _free(solver,record);return false
	pending=record;bytes_owned+=needed;peak_bytes=maxi(peak_bytes,bytes_owned)
	return true

func finish(solver, applied: bool) -> void:
	if pending.is_empty(): return
	if applied:
		records.append(pending)
		while records.size()>MAX_RECORDS:
			var oldest: Dictionary=records.pop_front();_free(solver,oldest);bytes_owned-=oldest.bytes
	else:
		_free(solver,pending);bytes_owned-=pending.bytes
	pending={}

func restore_latest(solver, generation: int, tick: int) -> bool:
	if solver.rd==null or solver.receipt_pending or solver.publication_pending or not pending.is_empty() or records.is_empty(): return false
	var record: Dictionary=records[-1]
	if record.solver_instance_id!=solver.get_instance_id() or record.identity.generation!=generation or record.identity.tick!=tick or solver.owner_generation!=generation: return false
	for field in FIELDS:
		for index in 2:
			if solver.rd.texture_copy(record.textures[field][index],solver.textures[field][index],Vector3.ZERO,Vector3.ZERO,Vector3(solver.grid_size,solver.grid_size,1),0,0,0,0)!=OK: return false
	solver.current_index=record.index;solver.state_revision=record.revision
	return true

func _free(solver, record: Dictionary) -> void:
	for slots in record.textures.values():
		for rid in slots:
			if rid.is_valid(): solver.rd.free_rid(rid)

func consume_latest(solver) -> void:
	if records.is_empty(): return
	var record: Dictionary=records.pop_back();_free(solver,record);bytes_owned-=record.bytes

func rebind_owner(previous_instance: int, solver, generation: int) -> bool:
	if not pending.is_empty(): return false
	for record in records:
		if record.solver_instance_id!=previous_instance: return false
	for record in records:
		record.solver_instance_id=solver.get_instance_id();record.identity.generation=generation
	return true

func release(solver) -> void:
	if not pending.is_empty(): _free(solver,pending)
	for record in records: _free(solver,record)
	records.clear();pending={};bytes_owned=0
