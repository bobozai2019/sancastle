extends "res://tests/integration/unified_edit_suspended_probe.gd"

const Half=preload("res://scripts/simulation/unified_edit/unit_half.gd")
var expected: Dictionary={}

func _configure_domain() -> void:
	for field in ["wetness","compaction"]:
		var bytes:=PackedByteArray();bytes.resize(65536*2)
		for index in 65536:
			var at: int=index if field=="wetness" else 65535-index
			var code: int=at%(0x3c01+1);bytes.encode_u16(index*2,code if code<0x3c01 else 0x8000)
		domain.set(field,Half.decode(bytes).value);expected[field]=bytes

func _extra_image_fields() -> Dictionary:
	var images:=super._extra_image_fields()
	images.view_wetness=pipeline.views.textures.wetness;images.view_compaction=pipeline.views.textures.compaction
	return images

func suspended() -> void:
	observations.initial=await snapshot("half_initial")
	var indexes:={}
	for field in expected:
		var path: String=output.get_base_dir()+"/expected_"+String(field)+".bin";FileAccess.open(path,FileAccess.WRITE).store_buffer(expected[field])
		indexes[field]={"path":path,"bytes":expected[field].size(),"sha256":FileAccess.get_sha256(path)}
		for actual in (["wetness0","wetness1","view_wetness"] if field=="wetness" else ["compact0","compact1","view_compaction"]):check("native_initial_"+actual,observations.initial[actual].sha256==indexes[field].sha256)
	var command:=request(1,&"fill_v1",Vector2.ZERO);command.parameters.strength=0.0
	expect("half_nochange",await perform("half_nochange",command),L.Outcome.NO_CHANGE)
	observations.after=await snapshot("half_after")
	for field in indexes:
		for actual in (["wetness0","wetness1","view_wetness"] if field=="wetness" else ["compact0","compact1","view_compaction"]):check("native_after_"+actual,observations.after[actual].sha256==indexes[field].sha256)
	observations.expected=indexes
