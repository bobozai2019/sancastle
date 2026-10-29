extends RefCounted

# Render-thread only native preimages. This primitive does not settle inventory,
# change generation, or authorize undo: the recovery coordinator owns those.
const FIELDS := ["sand","water","sediment","momentum_x","momentum_z","wetness","compaction"]
const MAX_RECORDS := 32
const MAX_BYTES := 64*1024*1024
var solver
var records := []
var pending := {}
var bytes_owned := 0
var peak_bytes := 0

func _init(editor) -> void: solver=editor

func _copy(source: RID, target: RID) -> bool:
	return solver.rd.texture_copy(source,target,Vector3.ZERO,Vector3.ZERO,Vector3(solver.grid_size,solver.grid_size,1),0,0,0,0)==OK

func _free(record: Dictionary) -> void:
	for rid in record.textures.values():
		if rid.is_valid(): solver.rd.free_rid(rid)
	bytes_owned-=int(record.bytes)

func capture(command_id: int, tick: int) -> bool:
	if solver.rd==null or solver.receipt_pending or solver.publication_pending or not pending.is_empty() or command_id<1 or tick<0: return false
	var size: int=solver.grid_size*solver.grid_size*24
	while not records.is_empty() and bytes_owned+size>MAX_BYTES: _free(records.pop_front())
	if bytes_owned+size>MAX_BYTES: return false
	var record: Dictionary={"command_id":command_id,"tick":tick,"generation":solver.owner_generation,"revision":solver.state_revision,"bytes":0,"textures":{}}
	for field in FIELDS:
		var half: bool=field in ["wetness","compaction"]
		var format:=RDTextureFormat.new()
		format.texture_type=RenderingDevice.TEXTURE_TYPE_2D
		format.width=solver.grid_size;format.height=solver.grid_size
		format.format=RenderingDevice.DATA_FORMAT_R16_SFLOAT if half else RenderingDevice.DATA_FORMAT_R32_SFLOAT
		format.usage_bits=RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
		var rid: RID=solver.rd.texture_create(format,RDTextureView.new())
		if not rid.is_valid(): _free(record);return false
		record.textures[field]=rid
		var field_bytes: int=solver.grid_size*solver.grid_size*(2 if half else 4)
		record.bytes+=field_bytes;bytes_owned+=field_bytes
		if not _copy(solver.current_texture(field),rid): _free(record);return false
	pending=record;peak_bytes=maxi(peak_bytes,bytes_owned)
	return true

func finish(applied: bool) -> bool:
	if pending.is_empty(): return false
	if applied:
		records.append(pending)
		while records.size()>MAX_RECORDS: _free(records.pop_front())
	else: _free(pending)
	pending={};return true

func restore_latest(tick: int) -> bool:
	if solver.rd==null or solver.receipt_pending or solver.publication_pending or not pending.is_empty() or records.is_empty(): return false
	var record: Dictionary=records[-1]
	if record.tick!=tick or record.generation!=solver.owner_generation: return false
	for field in FIELDS:
		for target in solver.textures[field]:
			if not _copy(record.textures[field],target): return false
	# The coordinator must publish the restored state only after CPU settlement.
	return true

func discard_latest() -> bool:
	if records.is_empty(): return false
	_free(records.pop_back());return true

func release() -> void:
	if not pending.is_empty(): _free(pending);pending={}
	while not records.is_empty(): _free(records.pop_back())
