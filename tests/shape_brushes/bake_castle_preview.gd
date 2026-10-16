extends SceneTree

func _init() -> void:
	var image:=Image.create_from_data(65,65,false,Image.FORMAT_RGBAF,FileAccess.get_file_as_bytes("res://assets/brushes/castle/four_towers_v1.rgba32f"))
	var texture:=ImageTexture.create_from_image(image)
	var result:=ResourceSaver.save(texture,"res://assets/brushes/castle/four_towers_preview.tres")
	print("CASTLE_PREVIEW_RESOURCE ",result==OK);quit(0 if result==OK else 1)
