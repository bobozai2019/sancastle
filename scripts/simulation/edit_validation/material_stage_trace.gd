extends "res://scripts/simulation/edit_validation/split_material_coupler.gd"

# Copies change submission load; this is a separate diagnostic configuration.
var trace=preload("res://scripts/simulation/edit_validation/beach_sand_copy_trace.gd").new()
var substep := 0
var metadata := []
var detail_substep := 0
var observe_enabled := true

func _init() -> void:
	observe_enabled = not "--beach-material-trace-continuation-only" in OS.get_cmdline_user_args()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--beach-material-trace-detail-substep="): detail_substep=arg.get_slice("=",1).to_int()

func _observe_stage(stage: String, live_index: int) -> void:
	if not observe_enabled: return
	if stage=="before":
		substep+=1
		metadata.append({"substep":substep,"revision":solver.state_revision,"index":live_index})
	if "--beach-material-trace-commit-only" in OS.get_cmdline_user_args() and stage!="commit" and substep!=detail_substep: return
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
		trace._copy(solver,source,format,"substep_%02d_%s_%s"%[substep,stage,field])

func release() -> void:
	if solver!=null and solver.rd!=null: trace.release(solver)
	super.release()
