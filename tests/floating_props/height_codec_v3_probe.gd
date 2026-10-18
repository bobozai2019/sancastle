extends SceneTree

const Codec=preload("res://scripts/simulation/unified_edit/height_codec.gd")
var checks: Array=[]
var output:=""
var identity:={"generation":9007199254741009,"snapshot_seq":9007199254741011}

func check(name: String, passed: bool) -> void:checks.append({"name":name,"pass":passed})
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	call_deferred("_run")
func _wire() -> PackedByteArray:
	var bytes:=PackedByteArray();bytes.resize(Codec.MAX_BYTES)
	bytes.encode_u32(0,3);bytes.encode_s64(8,identity.generation);bytes.encode_s64(16,identity.snapshot_seq)
	bytes.encode_s64(24,42);bytes.encode_s64(32,18);bytes.encode_u32(40,2);bytes.encode_u32(44,33);bytes.encode_u32(48,256);bytes.encode_float(52,0.125);bytes.encode_u32(56,2*1089*4)
	bytes.encode_u32(60,0x12345678);bytes.encode_u32(Codec.MAX_BYTES-4,0x00123456)
	bytes.encode_u32(64,0x3f800040|5);bytes.encode_u32(68,0x40000000|63)
	return bytes
func _run() -> void:
	var bytes:=_wire();var decoded:=Codec.decode(bytes,identity)
	check("exact_int64_identity_and_revision",decoded.error.is_empty() and decoded.generation==identity.generation and decoded.snapshot_seq==identity.snapshot_seq and decoded.revision==0x0012345612345678)
	check("packed_ids_and_outward_bounds",decoded.chunks==PackedInt32Array([5,63]) and decoded.change_bounds[5]==131073.0/131072.0 and decoded.change_bounds[63]==2.0)
	check("lower_bound_encloses_unpacked_value",Codec.lower_change_bound(decoded.change_bounds[5])<1.000001 and Codec.lower_change_bound(0.0)==0.0 and Codec.lower_change_bound(-1.0)==-1.0)
	check("unchanged_capacity",bytes.size()==128+16*1089*4+4 and decoded.raw.size()==2*1089*4)
	for row in [["old_schema",0,2],["nan_bound",64,0x7fc00000|5],["negative_bound",64,0xbf800000|5],["duplicate_chunk",68,0x40000000|5],["too_many_chunks",40,17]]:
		var changed:=bytes.duplicate();changed.encode_u32(row[1],row[2]);check(row[0]+"_rejected",not Codec.decode(changed,identity).error.is_empty())
	check("truncated_rejected",not Codec.decode(bytes.slice(0,bytes.size()-1),identity).error.is_empty())
	var infinite:=bytes.duplicate();infinite.encode_u32(64,0x7f800000|5)
	var unknown:=Codec.decode(infinite,identity)
	check("infinite_bound_is_explicit_unknown",unknown.error.is_empty() and unknown.change_bounds[5]==-1.0)
	var passed:=checks.all(func(row):return row.pass)
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"pass":passed,"checks":checks,"codec_sha256":FileAccess.get_sha256("res://scripts/simulation/unified_edit/height_codec.gd")},"\t"));print("HEIGHT_CODEC_V3 ",passed," checks=",checks.size());quit(0 if passed else 1)
