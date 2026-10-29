extends "res://scripts/simulation/edit_validation/split_material_coupler.gd"

# Default-off synchronization adaptation; no shader or source texel changes.
var fence_textures := {}
var copy_count := 0

func initialize(p_solver: SandcastleGpuShallowSolver, dirty_max_texture: RID,
		step_spirv: RDShaderSPIRV, slope_spirv: RDShaderSPIRV,
		commit_spirv: RDShaderSPIRV) -> bool:
	if not super.initialize(p_solver,dirty_max_texture,step_spirv,slope_spirv,commit_spirv): return false
	for format in [RenderingDevice.DATA_FORMAT_R32_SFLOAT,RenderingDevice.DATA_FORMAT_R16_SFLOAT,RenderingDevice.DATA_FORMAT_R8_UNORM]:
		var texture: RID=solver._create_texture(format,PackedByteArray())
		if not texture.is_valid(): release();return false
		fence_textures[format]=texture
	return true

func _observe_stage(stage: String, live_index: int) -> void:
	var fields: Array=[]
	var index:=live_index
	if stage=="before": fields=["sand","rock","water","sediment","wetness","compaction","obstacle"]
	elif stage=="step": fields=["wetness","compaction"];index=1-live_index
	elif stage=="slope": fields=["sand"];index=1-live_index
	else: fields=["sand"]
	for field in fields:
		var format:=RenderingDevice.DATA_FORMAT_R32_SFLOAT
		if field in ["wetness","compaction"]: format=RenderingDevice.DATA_FORMAT_R16_SFLOAT
		elif field=="obstacle": format=RenderingDevice.DATA_FORMAT_R8_UNORM
		var source: RID=solver.textures[field] if field in ["rock","obstacle"] else solver.textures[field][index]
		assert(rd.texture_copy(source,fence_textures[format],Vector3.ZERO,Vector3.ZERO,Vector3(1,1,1),0,0,0,0)==OK)
		copy_count+=1

func release() -> void:
	if rd!=null:
		for texture in fence_textures.values(): rd.free_rid(texture)
	fence_textures.clear()
	super.release()
