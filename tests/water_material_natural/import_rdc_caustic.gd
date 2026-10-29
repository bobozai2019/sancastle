extends SceneTree

const RAW := "res://test_output/competitor_water_material_20261011/replay_v5/event_5006_ps_texture_1105_mip0.bin"
const DEST := "res://assets/water_material_natural_candidate/rdc_caustic_1105_mipped.res"

func _initialize() -> void:
	call_deferred("_build")

func _build() -> void:
	if FileAccess.get_sha256(RAW) != "e5355399d7e4931291032ebd78d7b50dfe89cb7565dbda422f74e469769d3b0c":
		push_error("Caustic source identity mismatch");quit(1);return
	var raw := FileAccess.get_file_as_bytes(RAW)
	var slices: Array[Image] = []
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://test_output/water_material_rdc/caustic_mips_v1/manifest.json"))
	if not manifest.get("pass",false):push_error("Missing full mip source");quit(1);return
	var expected := PackedByteArray()
	for mip in manifest.mips:
		var data := FileAccess.get_file_as_bytes(mip.path)
		if FileAccess.get_sha256(mip.path)!=mip.sha256:push_error("Mip identity mismatch");quit(1);return
		expected.append_array(data)
		var width := int(mip.dimensions[0]);var height := int(mip.dimensions[1])
		var size := width*height
		for z in range(int(mip.dimensions[2])):
			slices.append(Image.create_from_data(width,height,false,Image.FORMAT_R8,data.slice(z*size,(z+1)*size)))
	var volume := ImageTexture3D.new()
	var error := volume.create(Image.FORMAT_R8,256,256,64,true,slices)
	if error != OK or ResourceSaver.save(volume,DEST) != OK:
		push_error("Caustic resource creation failed");quit(1);return
	var loaded := ResourceLoader.load(DEST,"",ResourceLoader.CACHE_MODE_IGNORE) as Texture3D
	if loaded == null or loaded.get_width()!=256 or loaded.get_height()!=256 or loaded.get_depth()!=64:
		push_error("Caustic reload failed");quit(1);return
	var recovered := PackedByteArray()
	for slice in loaded.get_data():recovered.append_array(slice.get_data())
	if recovered != expected or not loaded.has_mipmaps():
		push_error("Caustic reload texels differ");quit(1);return
	var result := {"source":RAW,"source_sha256":FileAccess.get_sha256(RAW),"resource":DEST,"resource_sha256":FileAccess.get_sha256(DEST),"dimensions":[256,256,64],"format":"R8","mipmaps":true,"mip_count":9,"source_manifest":"res://test_output/water_material_rdc/caustic_mips_v1/manifest.json","texel_roundtrip_exact":true,"scope":"All nine captured mip levels preserved exactly."}
	var file := FileAccess.open("res://assets/water_material_natural_candidate/rdc_caustic_manifest.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"));file.close()
	print("PASS: exact captured caustic volume saved and reloaded")
	quit(0)
