extends SceneTree

func _initialize() -> void:
	var result:={}
	for file in ["foam_cells.png","foam_cells_organic.png"]:
		var path: String="res://assets/water_foam/"+file
		var texture: Texture2D=load(path)
		var image:=texture.get_image()
		result[file]={"source_sha256":FileAccess.get_sha256(path),"import_sha256":FileAccess.get_sha256(path+".import"),"class":texture.get_class(),"width":image.get_width(),"height":image.get_height(),"format":image.get_format(),"mipmap_count":image.get_mipmap_count(),"mip_data_bytes":image.get_data_size(),"compressed":image.is_compressed(),"note":"ResourceLoader imported image data, not PNG file length"}
	FileAccess.open("res://task/water_foam_visual/验收/G1/imported_textures.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify(result))
	quit()
