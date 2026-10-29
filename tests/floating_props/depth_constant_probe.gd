extends SceneTree

func bits(value: float) -> String:
	var bytes:=PackedByteArray();bytes.resize(8);bytes.encode_double(0,value);return bytes.hex_encode()

func _initialize() -> void:
	var output:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	var decimal: float=0.0010000000474974513
	var binary: float=8589935.0/8589934592.0
	var packed: float=PackedFloat32Array([0.001])[0]
	var result:={"pass":binary==packed,"engine":Engine.get_version_info(),"decimal_equals_float32":decimal==packed,"decimal_double_bits_le":bits(decimal),"binary_double_bits_le":bits(binary),"float32_expanded_double_bits_le":bits(packed),"scope":"CPU GDScript literal rounding observation on the recorded engine; binary-ratio constant must exactly equal expanded float32 cutoff"}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"));print("DEPTH_CONSTANT ",result);quit(0 if result.pass else 1)
