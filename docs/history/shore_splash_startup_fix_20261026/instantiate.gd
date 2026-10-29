extends SceneTree
func _initialize() -> void:
 for path in ["res://scenes/main.tscn","res://scenes/playable/test1_geometry.tscn"]:
  print("START_INSTANTIATE ",path)
  var packed: PackedScene=load(path)
  var first=packed.instantiate()
  var second=packed.instantiate()
  var splash: MultiMesh=first.get_node("ShoreSplash").multimesh
  print("SPLASH ",splash.instance_count," format=",splash.transform_format," local=",splash.resource_local_to_scene)
  first.free();second.free()
 quit()
