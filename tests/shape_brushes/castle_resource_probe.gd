extends "res://tests/shape_brushes/material_edit_probe.gd"

var resource_probe_result:Variant=null
func build_bad_template(path:String) -> void:
	var definition=BrushProtocol.registry.definition(&"castle_v1");var original:String=definition.template_path
	definition.template_path=path
	var candidate=preload("res://scripts/simulation/brushes/brush_gpu.gd").new()
	var initialized:bool=candidate.initialize(preview.solver)
	var result:Dictionary={"initialized":initialized,"error":candidate.last_error,"allocated":candidate.owned.size()}
	candidate.release();result.released=candidate.rd==null and candidate.owned.is_empty()
	definition.template_path=original
	call_deferred("bad_template_done",result)
func bad_template_done(result:Dictionary) -> void:resource_probe_result=result

func _run() -> void:
	root.size=Vector2i(1280,720);pair_fields=27
	preview=load("res://tests/shape_brushes/checkpoint_v4_lab.tscn").instantiate();preview.playing=false;preview.hide_hud=true;root.add_child(preview)
	var deadline:=Time.get_ticks_msec()+90000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	_check("resource_lab_ready",preview.ready_for_ticks,preview.last_error)
	if not preview.ready_for_ticks:_finish();quit(1);return
	var bytes:=FileAccess.get_file_as_bytes("res://assets/brushes/castle/four_towers_v1.rgba32f")
	var before:=await snapshot("resource_before");var before_meta:=metadata()
	var invalid:Dictionary={"missing":PackedByteArray(),"size":bytes.slice(0,16),"nan":bytes.duplicate(),"mask":bytes.duplicate()}
	invalid.nan.encode_float(0,NAN);invalid.mask.encode_float(4,0.25)
	for name in invalid:
		var path:=output.path_join("invalid_"+name+".rgba32f")
		if name!="missing":
			var file:=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(invalid[name]);file.close()
		resource_probe_result=null;RenderingServer.call_on_render_thread(build_bad_template.bind(path))
		deadline=Time.get_ticks_msec()+30000
		while resource_probe_result==null and Time.get_ticks_msec()<deadline:await process_frame
		_check(name+"_reject_before_allocation",resource_probe_result!=null and not resource_probe_result.initialized and resource_probe_result.allocated==0,resource_probe_result)
		_check(name+"_release",resource_probe_result!=null and resource_probe_result.released)
		_check(name+"_authority_unchanged",exact(before,await snapshot(name+"_after")) and metadata()==before_meta)
	_check("valid_resource_restored",BrushProtocol.registry.definition(&"castle_v1")!=null and preview.shape_backend_ready and preview.last_error.is_empty())
	await preview.shutdown();preview.queue_free();await process_frame
	_finish();var passed:=true
	for row in checks:passed=passed and row.pass
	quit(0 if passed else 1)
