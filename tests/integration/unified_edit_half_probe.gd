extends SceneTree

const Half=preload("res://scripts/simulation/unified_edit/unit_half.gd")
var output:=""
var checks:=[]
var failed:=false
var artifacts: Dictionary={}

func check(name: String, value: bool) -> void:
	checks.append({"name":name,"pass":value});failed=failed or not value

func save(label: String, bytes: PackedByteArray) -> void:
	var path:=output.get_base_dir()+"/"+label+".bin";FileAccess.open(path,FileAccess.WRITE).store_buffer(bytes)
	artifacts[label]={"path":path,"bytes":bytes.size(),"sha256":FileAccess.get_sha256(path)}

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	var native:=PackedByteArray();native.resize((0x3c01+1)*2)
	for bits in 0x3c01:native.encode_u16(bits*2,bits)
	native.encode_u16(0x3c01*2,0x8000)
	var decoded:=Half.decode(native);check("all_15362_native_unit_values_decode",decoded.error.is_empty())
	var encoded:=Half.encode(decoded.value);check("all_native_values_lossless_roundtrip",encoded.error.is_empty() and encoded.value==native)
	save("native",native);save("decoded_f32",decoded.value.to_byte_array());save("roundtrip",encoded.value)
	var values:=PackedFloat32Array();var old:=PackedByteArray();old.resize(10000*2)
	var rng:=RandomNumberGenerator.new();rng.seed=6112026
	for index in 10000:
		values.append(rng.randf_range(Half.MIN_NORMAL,1.0));old.encode_half(index*2,values[index])
	var normal:=Half.encode(values);check("normal_values_preserve_host_quantization",normal.error.is_empty() and normal.value==old)
	save("normal_input_f32",values.to_byte_array());save("host_normal_half",old);save("new_normal_half",normal.value)
	var boundary:=PackedFloat32Array([pow(2,-25),pow(2,-24),1.5*pow(2,-24),Half.MIN_NORMAL-pow(2,-24),Half.MIN_NORMAL,1.0,-0.0])
	var result:=Half.encode(boundary)
	check("subnormal_boundaries",result.error.is_empty() and result.value.decode_u16(0)==0 and result.value.decode_u16(2)==1 and result.value.decode_u16(4)==1 and result.value.decode_u16(6)==1023 and result.value.decode_u16(8)==1024 and result.value.decode_u16(10)==0x3c00 and result.value.decode_u16(12)==0x8000)
	save("boundary_input_f32",boundary.to_byte_array());save("boundary_half",result.value)
	for bits in [0x8001,0x3c01,0x7c00,0xfc00,0x7e00,0xffff]:
		var bytes:=PackedByteArray();bytes.resize(2);bytes.encode_u16(0,bits);check("reject_native_"+str(bits),not Half.decode(bytes).error.is_empty())
	for value in [NAN,INF,-0.01,1.001]:check("reject_value_"+str(value),not Half.encode(PackedFloat32Array([value])).error.is_empty())
	check("reject_empty_encode",not Half.encode(PackedFloat32Array()).error.is_empty())
	check("reject_empty_decode",not Half.decode(PackedByteArray()).error.is_empty())
	check("reject_odd_decode",not Half.decode(PackedByteArray([0])).error.is_empty())
	var record:={"pass":not failed,"checks":checks,"artifacts":artifacts,"engine":Engine.get_version_info(),"source_sha256":FileAccess.get_sha256("res://scripts/simulation/unified_edit/unit_half.gd"),"probe_sha256":FileAccess.get_sha256(get_script().resource_path),"scope":"Native finite unit half codec, full legal representation set, host normal compatibility and explicit invalid input rejection; no GPU/full restore claim"}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(record,"\t"));print("UNIT_HALF ",not failed," ",checks.size());quit(1 if failed else 0)
