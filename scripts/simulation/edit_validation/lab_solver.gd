extends "res://scripts/simulation/gpu_shallow_solver.gd"

# Isolated deterministic initialization. Auxiliary/current flux buffers must
# have defined bytes even before the first tick; original passes stay intact.
func _create_texture(format_id: int, data: PackedByteArray,
		texture_width: int = 0, texture_height: int = 0,
		updatable: bool = false) -> RID:
	if data.is_empty():
		var width: int = grid_size if texture_width == 0 else texture_width
		var height: int = width if texture_height == 0 else texture_height
		var strides := {RenderingDevice.DATA_FORMAT_R32_SFLOAT: 4,
			RenderingDevice.DATA_FORMAT_R32G32_SFLOAT: 8,
			RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT: 16,
			RenderingDevice.DATA_FORMAT_R16_SFLOAT: 2,
			RenderingDevice.DATA_FORMAT_R8_UNORM: 1}
		if not strides.has(format_id):
			return RID()
		data.resize(width * height * strides[format_id])
		data.fill(0)
	# Candidate recovery copies native-format GPU preimages into these textures.
	# Production solver usage flags are unchanged.
	var format:=RDTextureFormat.new()
	format.texture_type=RenderingDevice.TEXTURE_TYPE_2D
	format.width=grid_size if texture_width==0 else texture_width
	format.height=format.width if texture_height==0 else texture_height
	format.format=format_id
	format.usage_bits=RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
	if updatable: format.usage_bits |= RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	return rd.texture_create(format,RDTextureView.new(),[data])

func restore_native_fields(fields: Dictionary, revision: int, spare_fields: Dictionary={}, restored_index: int=-1) -> bool:
	# Cold candidate restore only: caller must keep this solver isolated until
	# all copies are accepted, then settle CPU metadata before publication.
	var strides: Dictionary={"rock":4,"sand":4,"water":4,"sediment":4,"momentum_x":4,"momentum_z":4,"wetness":2,"compaction":2,"obstacle":1,"flux":16}
	if rd==null or revision<0 or fields.size()!=strides.size(): return false
	if "receipt_pending" in self and (self.receipt_pending or self.publication_pending): return false
	if restored_index not in [-1,0,1]: return false
	for field in strides:
		if not fields.get(field) is PackedByteArray or fields[field].size()!=grid_size*grid_size*int(strides[field]): return false
	for field in spare_fields:
		if not strides.has(field) or not textures[field] is Array or not spare_fields[field] is PackedByteArray or spare_fields[field].size()!=grid_size*grid_size*int(strides[field]): return false
	if restored_index>=0: current_index=restored_index
	for field in strides:
		var format:=RDTextureFormat.new()
		format.texture_type=RenderingDevice.TEXTURE_TYPE_2D;format.width=grid_size;format.height=grid_size
		format.format=RenderingDevice.DATA_FORMAT_R16_SFLOAT if strides[field]==2 else (RenderingDevice.DATA_FORMAT_R8_UNORM if strides[field]==1 else (RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT if strides[field]==16 else RenderingDevice.DATA_FORMAT_R32_SFLOAT))
		format.usage_bits=RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
		var source: RID=rd.texture_create(format,RDTextureView.new(),[fields[field]])
		if not source.is_valid(): return false
		var targets: Array=[current_texture(field)] if not spare_fields.is_empty() else (textures[field] if textures[field] is Array else [textures[field]])
		var ok:=true
		for target in targets:
			ok=rd.texture_copy(source,target,Vector3.ZERO,Vector3.ZERO,Vector3(grid_size,grid_size,1),0,0,0,0)==OK and ok
		rd.free_rid(source)
		if not ok: return false
	if not spare_fields.is_empty():
		for field in spare_fields:
			var format_id: int=RenderingDevice.DATA_FORMAT_R16_SFLOAT if strides[field]==2 else (RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT if strides[field]==16 else RenderingDevice.DATA_FORMAT_R32_SFLOAT)
			var source:=_create_texture(format_id,spare_fields[field])
			if not source.is_valid(): return false
			var error: Error=rd.texture_copy(source,textures[field][1-current_index],Vector3.ZERO,Vector3.ZERO,Vector3(grid_size,grid_size,1),0,0,0,0)
			rd.free_rid(source)
			if error!=OK: return false
	state_revision=revision
	return true
