extends SceneTree
func _initialize() -> void:
 var scene: PackedScene=load("res://scenes/components/vegetation_layer.tscn")
 var a=scene.instantiate();var b=scene.instantiate();var rows: Array=[];var passed:=true
 for child in a.get_children():
  var original: MultiMesh=load("res://assets/vegetation/"+String(child.name)+"_instances.tres")
  var first: MultiMesh=child.multimesh;var second: MultiMesh=b.get_node(NodePath(child.name)).multimesh
  var okay: bool=first!=second and first!=original and first.instance_count==original.instance_count and first.transform_format==original.transform_format and first.use_colors==original.use_colors and first.use_custom_data==original.use_custom_data
  passed=passed and okay
  rows.append({"name":String(child.name),"pass":okay,"instances":first.instance_count,"format":first.transform_format,"independent_instances":first!=second,"source_sha256":FileAccess.get_sha256("res://assets/vegetation/"+String(child.name)+"_instances.tres")})
 FileAccess.open("res://test_output/startup_safety_scan_20261026_live_v3/vegetation_review.json",FileAccess.WRITE).store_string(JSON.stringify({"pass":passed,"rows":rows,"scope":"Actual detached scene-local construction; metadata, per-scene independence and errors only, not a GPU buffer-content or visual comparison."},"\t"))
 a.free();b.free();print("VEGETATION_REVIEW ",passed," count=",rows.size());quit(0 if passed else 1)
