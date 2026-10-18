extends "res://scripts/simulation/unified_edit/executor.gd"

# Probe-only capture after validation, before public commit. Copies never feed
# the executor, rollback authority or gate recording of the following stage.
var snapshot_armed:=false
var snapshots: Dictionary={}

func _before_commit() -> void:
	if not snapshot_armed:return
	snapshot_armed=false
	for pair in [["sand0",state.textures.sand[0],RenderingDevice.DATA_FORMAT_R32_SFLOAT],["sand1",state.textures.sand[1],RenderingDevice.DATA_FORMAT_R32_SFLOAT],["support0",state.textures.mold_support[0],RenderingDevice.DATA_FORMAT_R32G32_SFLOAT],["support1",state.textures.mold_support[1],RenderingDevice.DATA_FORMAT_R32G32_SFLOAT],["compact0",state.textures.compaction[0],RenderingDevice.DATA_FORMAT_R16_SFLOAT],["compact1",state.textures.compaction[1],RenderingDevice.DATA_FORMAT_R16_SFLOAT],["sediment0",state.textures.sediment[0],RenderingDevice.DATA_FORMAT_R32_SFLOAT],["sediment1",state.textures.sediment[1],RenderingDevice.DATA_FORMAT_R32_SFLOAT],["water0",state.textures.water[0],RenderingDevice.DATA_FORMAT_R32_SFLOAT],["water1",state.textures.water[1],RenderingDevice.DATA_FORMAT_R32_SFLOAT],["qx0",state.textures.momentum_x[0],RenderingDevice.DATA_FORMAT_R32_SFLOAT],["qx1",state.textures.momentum_x[1],RenderingDevice.DATA_FORMAT_R32_SFLOAT],["qz0",state.textures.momentum_z[0],RenderingDevice.DATA_FORMAT_R32_SFLOAT],["qz1",state.textures.momentum_z[1],RenderingDevice.DATA_FORMAT_R32_SFLOAT],["baseline",images.baseline,RenderingDevice.DATA_FORMAT_R32_SFLOAT],["coverage",images.coverage,RenderingDevice.DATA_FORMAT_R32G32_SFLOAT]]:
		var target: RID=state._create_texture(pair[2],PackedByteArray())
		if rd.texture_copy(pair[1],target,Vector3.ZERO,Vector3.ZERO,Vector3(256,256,1),0,0,0,0)!=OK:push_error("precommit snapshot copy failed")
		snapshots["pre_"+pair[0]]=target

func clear_snapshots() -> void:
	# Probe calls only after all snapshot readback callbacks have completed.
	for texture in snapshots.values():rd.free_rid(texture);state.owned.erase(texture)
	snapshots.clear()
