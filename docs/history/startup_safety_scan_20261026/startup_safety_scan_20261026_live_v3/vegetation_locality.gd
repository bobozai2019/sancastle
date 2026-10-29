extends SceneTree
func _initialize() -> void:
 var source: MultiMesh=load("res://assets/vegetation/seagrass_instances.tres")
 var scene: PackedScene=load("res://scenes/components/vegetation_layer.tscn")
 var a=scene.instantiate();var b=scene.instantiate()
 var ma: MultiMesh=a.get_child(0).multimesh;var mb: MultiMesh=b.get_child(0).multimesh
 print("VEGETATION_LOCALITY local=",ma.resource_local_to_scene," count=",ma.instance_count," distinct=",ma!=mb," source_is_instance=",source==ma)
 a.free();b.free();quit()
