extends SceneTree
func _init() -> void:
	for method in ClassDB.class_get_method_list(&"RenderingServer"):
		if "profil" in String(method.name): print(JSON.stringify(method))
	quit()
