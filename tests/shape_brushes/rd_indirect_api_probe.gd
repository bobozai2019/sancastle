extends SceneTree
func _init() -> void:
	for method in ClassDB.class_get_method_list("RenderingDevice"):
		if method.name in ["storage_buffer_create","compute_list_dispatch_indirect"]: print(JSON.stringify(method))
	print("INDIRECT_FLAG=",ClassDB.class_get_integer_constant("RenderingDevice","STORAGE_BUFFER_USAGE_DISPATCH_INDIRECT"))
	quit()
