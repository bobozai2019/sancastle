extends SceneTree

const OUTPUT := "res://test_output/sandcastle_water_sand_coupling/验收/G1A_gpu_format_support.csv"
const SIZE := 256

var rows: PackedStringArray = PackedStringArray()
var failed := false


func _init() -> void:
	call_deferred("_begin")


func _begin() -> void:
	rows.append("format,storage_sample_copy_supported,texture_created,width,height")
	RenderingServer.call_on_render_thread(_probe_render)


func _probe_render() -> void:
	var rd := RenderingServer.get_rendering_device()
	if rd == null:
		call_deferred("_finish", true)
		return
	var usage := RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	var options := [
		["R32_SFLOAT", RenderingDevice.DATA_FORMAT_R32_SFLOAT],
		["R32G32_SFLOAT", RenderingDevice.DATA_FORMAT_R32G32_SFLOAT],
		["R32G32B32A32_SFLOAT", RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT],
		["R16_SFLOAT", RenderingDevice.DATA_FORMAT_R16_SFLOAT],
		["R8_UNORM", RenderingDevice.DATA_FORMAT_R8_UNORM]
	]
	var local_rows: PackedStringArray = PackedStringArray()
	var any_failure := false
	for option in options:
		var label: String = option[0]
		var format_id: int = option[1]
		var supported: bool = rd.texture_is_format_supported_for_usage(format_id, usage)
		var created := false
		if supported:
			var texture_format := RDTextureFormat.new()
			texture_format.texture_type = RenderingDevice.TEXTURE_TYPE_2D
			texture_format.width = SIZE
			texture_format.height = SIZE
			texture_format.format = format_id
			texture_format.usage_bits = usage
			var rid := rd.texture_create(texture_format, RDTextureView.new())
			created = rid.is_valid()
			if created:
				rd.free_rid(rid)
		if not supported or not created:
			any_failure = true
		local_rows.append("%s,%s,%s,%d,%d" % [label, str(supported), str(created), SIZE, SIZE])
	call_deferred("_finish", any_failure, local_rows)


func _finish(any_failure: bool, local_rows: PackedStringArray = PackedStringArray()) -> void:
	for row in local_rows:
		rows.append(row)
	var file := FileAccess.open(OUTPUT, FileAccess.WRITE)
	if file == null:
		printerr("FAIL: format support CSV unavailable")
		quit(1)
		return
	file.store_string("\n".join(rows) + "\n")
	file.close()
	for row in local_rows:
		print("FORMAT " + row)
	if any_failure:
		printerr("FAIL: at least one candidate texture format unavailable")
		quit(1)
		return
	print("PASS: five 256-square main-RD formats support storage, sampling, copy")
	quit(0)
