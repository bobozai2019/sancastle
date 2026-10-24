extends "res://docs/competitor/tools/probe_foam_comparison.gd"

func _initialize() -> void:
	super._initialize()
	if "--hide-brush-overlays" in OS.get_cmdline_user_args():RenderingServer.frame_pre_draw.connect(_hide_brush)

func _hide_brush() -> void:
	if not is_instance_valid(scene):return
	for path in ["BrushIndicator","BrushPreview"]:
		var node: Node3D=scene.get_node_or_null(path)
		if node!=null:node.hide()
	observations.brush_overlays_hidden=true

# Q02 control: no candidate shader or foam texture is ever installed.
func _capture(label: String) -> void:
	await super._capture(label)
	if label not in ["t360","t360_restored"]:return
	var material: ShaderMaterial=scene.get_node("GpuWaterSurface").material_override
	if not observations.has("original_gain_control"):observations.original_gain_control={}
	observations.original_gain_control[label]=_material(material)
	await super._capture(label+"_repeat_A")
	await super._capture(label+"_repeat_B")
	check(label+"_original_repeat_AB",FileAccess.get_sha256(output+"/"+label+"_repeat_A.png")==FileAccess.get_sha256(output+"/"+label+"_repeat_B.png"))
