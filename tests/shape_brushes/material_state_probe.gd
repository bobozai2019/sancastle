extends "res://tests/water_material_natural/rdc_main_smoke.gd"

const State = preload("res://scripts/simulation/brushes/brush_material_state_codec.gd")
var profile_hash := ""
var sand := PackedByteArray()
var source_record := {}

func expect_error(name: String, mutation: Dictionary, expected: StringName) -> void:
	var record: Dictionary=source_record.duplicate(true)
	for key in mutation: record[key]=mutation[key]
	_check(name,State.validate(record,sand,sand,profile_hash)==expected,State.validate(record,sand,sand,profile_hash))

func raw_field(sample: Dictionary, name: String) -> PackedByteArray:
	var item: Dictionary=sample.fields[name]
	var bytes:=FileAccess.get_file_as_bytes(item.path)
	_check("source_"+name+"_identity",bytes.size()==int(item.bytes) and FileAccess.get_sha256(item.path)==item.sha256)
	return bytes

func _run() -> void:
	profile_hash=FileAccess.get_sha256("res://assets/brushes/molded_material_candidate.json")
	var values:=PackedFloat32Array();values.resize(65536);values.fill(1.0);sand=values.to_byte_array()
	var zero:=State.initial_values(PackedFloat32Array(),values)
	source_record=State.make_record(zero,zero,false,profile_hash)
	_check("cold_zero_state",State.validate(source_record,sand,sand,profile_hash).is_empty())
	var hot: Dictionary=source_record.duplicate(true);hot.ever_used=true
	_check("hot_zero_state_retains_branch_flag",State.validate(hot,sand,sand,profile_hash).is_empty())
	_check("invalid_metadata_array_type",State.initial_values([0.0],values).is_empty())
	var tags:=PackedFloat32Array();tags.resize(65536);tags.fill(0.0)
	var negative_zero:=tags.to_byte_array();negative_zero.encode_u32(0,0x80000000);tags=negative_zero.to_float32_array()
	_check("initial_negative_zero_canonicalized",State.initial_values(tags,values)==zero)
	for bad in [-0.1,1.1,NAN,INF]:
		tags[0]=bad;_check("initial_bad_tag_"+str(bad),State.initial_values(tags,values).is_empty())
	var domain:=SandWaterDomain.new(256,0.125);domain.sand=values;domain.set_meta("brush_initial_mold_depth",[0.0])
	var solver=preload("res://scripts/simulation/brushes/brush_material_solver.gd").new()
	_check("bad_metadata_rejected_before_gpu_allocation",not solver.initialize(null,domain,null,null,null,null,null,null,null,null) and solver.rd==null and solver.textures.is_empty())
	expect_error("unknown_version",{"version":2},&"invalid_material_header")
	expect_error("float_version",{"version":1.0},&"invalid_material_header")
	expect_error("wrong_grid",{"grid_size":128},&"invalid_material_header")
	expect_error("nonboolean_flag",{"ever_used":1},&"invalid_material_header")
	expect_error("unknown_format",{"format":"R32F"},&"invalid_material_format")
	expect_error("wrong_spacing",{"cell_size_m":0.25},&"invalid_material_format")
	expect_error("wrong_profile",{"profile_id":&"plain_sand_v1"},&"material_profile_mismatch")
	expect_error("wrong_profile_hash",{"profile_sha256":"0".repeat(64)},&"material_profile_mismatch")
	expect_error("missing_current_bytes",{"current_support":PackedByteArray()},&"invalid_material_field_size")
	expect_error("wrong_spare_type",{"spare_support":PackedFloat32Array()},&"invalid_material_field_size")
	var unknown: Dictionary=source_record.duplicate(true);unknown.extra=0
	_check("extra_header_key_rejected",State.validate(unknown,sand,sand,profile_hash)==&"invalid_material_header")
	var missing: Dictionary=source_record.duplicate(true);missing.erase("ever_used")
	_check("missing_header_key_rejected",State.validate(missing,sand,sand,profile_hash)==&"invalid_material_header")
	for bad in [-0.1,1.1,NAN,INF]:
		var bytes:=zero.duplicate();bytes.encode_float(0,bad)
		expect_error("bad_stored_tag_"+str(bad),{"current_support":bytes,"spare_support":bytes},&"invalid_material_values")
	var changed:=zero.duplicate();changed.encode_float(4,1.0)
	expect_error("zero_reference_not_canonical",{"current_support":changed,"spare_support":changed},&"invalid_material_reference")
	changed=zero.duplicate();changed.encode_u32(0,0x80000000)
	expect_error("stored_negative_zero_not_canonical",{"current_support":changed,"spare_support":changed},&"invalid_material_reference")
	changed=zero.duplicate();changed.encode_float(0,0.5);changed.encode_float(4,1.0)
	expect_error("nonzero_missing_ever_used",{"current_support":changed,"spare_support":changed},&"invalid_material_ever_used")
	expect_error("different_slot_preimages_not_saveable",{"current_support":changed,"ever_used":true},&"invalid_material_pair")
	var nonzero: Dictionary=State.make_record(changed,changed,true,profile_hash)
	_check("nonzero_finite_state",State.validate(nonzero,sand,sand,profile_hash).is_empty())
	changed.encode_float(4,0.9)
	expect_error("wrong_reference_sand",{"current_support":changed,"spare_support":changed,"ever_used":true},&"invalid_material_reference")
	var raw_cases:=[]
	for mode in ["intact","trench"]:
		var path: String="res://test_output/shape_brushes/20261014_054945_material_damage_bc4faa31/"+mode+"/damage_evidence.json"
		var evidence: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
		_check(mode+"_source_profile_identity",evidence.profile_sha256==profile_hash)
		for sample in evidence.samples:
			var live:=raw_field(sample,"sand");var spare:=raw_field(sample,"spare_sand")
			var current:=raw_field(sample,"mold_support_0");var other:=raw_field(sample,"mold_support_1")
			var record:=State.make_record(current,other,true,profile_hash)
			_check(mode+"_real_raw_audit_"+str(sample.tick),State.validate(record,live,spare,profile_hash).is_empty())
			raw_cases.append({"mode":mode,"sample":sample,"profile_sha256":profile_hash})
	var file:=FileAccess.open(output.path_join("material_state_evidence.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"raw_cases":raw_cases,"scope":"Material subrecord validation and initialization only; native v2 disk/restore still unsupported."},"\t"));file.close()
	_check("source_record_unchanged",State.validate(source_record,sand,sand,profile_hash).is_empty())
	_finish();var passed:=true
	for row in checks: passed=passed and row.pass
	quit(0 if passed else 1)
