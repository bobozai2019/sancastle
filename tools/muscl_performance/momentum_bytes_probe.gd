extends SceneTree

const Bytes=preload("res://scripts/simulation/unified_edit/momentum_bytes.gd")

func _initialize() -> void:
	var x:=PackedByteArray();var z:=PackedByteArray();x.resize(Bytes.SCALAR_BYTES);z.resize(Bytes.SCALAR_BYTES)
	var patterns: Array=[0,0x80000000,0x3f800000,0xbf800000,0x00000001,0x7f7fffff,0x7fc12345,0x7f800000]
	for i in Bytes.CELLS:
		x.encode_u32(i*4,patterns[i%patterns.size()]);z.encode_u32(i*4,patterns[(i+3)%patterns.size()])
	var packed:=Bytes.pack(x,z);var split:=Bytes.split(packed.value)
	var swapped:=Bytes.pack(z,x)
	var checks:={"roundtrip":split.error.is_empty() and split.momentum_x==x and split.momentum_z==z,"channel_order":packed.value.decode_u32(0)==x.decode_u32(0) and packed.value.decode_u32(4)==z.decode_u32(0),"swap_detected":swapped.value!=packed.value,"spare_independent":Bytes.split(swapped.value).momentum_x==z,"short_x":not Bytes.pack(x.slice(0,4),z).error.is_empty(),"short_z":not Bytes.pack(x,z.slice(0,4)).error.is_empty(),"short_packed":not Bytes.split(packed.value.slice(0,8)).error.is_empty(),"long_packed":not Bytes.split(packed.value+PackedByteArray([0])).error.is_empty()}
	var output:=OS.get_cmdline_user_args()[0]
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"pass":checks.values().all(func(value):return value),"checks":checks,"scope":"Unsigned bit copies, including signed zero, subnormal, finite extremes and NaN/Inf patterns. This helper does not authorize nonfinite initialization."},"\t"))
	quit(0 if checks.values().all(func(value):return value) else 1)
