extends "res://tests/water_material_natural/common_checkpoint_cost.gd"

func _lighting_sweep(before: Dictionary) -> void:
	preview.playing=false;preview.replay_target_tick=-1
	var rows:=[]
	var start_tick:int=preview.completed_ticks
	var start_time:float=preview.visual_time_s
	var start_generation:int=preview.generation
	for i in preview.compiled_bundle.components.size():
		var component:Dictionary=preview.compiled_bundle.components[i]
		var material:ShaderMaterial=preview.water_material if component.material=="water" else preview.terrain_material
		for key in preview.compiled_constants[i]:
			var explicit:Variant=material.get_shader_parameter(key)
			var expected:Variant=preview.compiled_constants[i][key]
			var changed:Variant=not expected if expected is bool else float(expected)+1.
			material.set_shader_parameter(key,changed)
			preview._seal_test1_effective_profile()
			var error:String=preview.last_error
			var rejected:bool=error=="compiled_constant_mismatch: "+String(key)
			material.set_shader_parameter(key,explicit)
			preview.last_error=""
			var recovered:bool=preview._validate_compiled_inputs()
			rows.append({"material":component.material,"field":key,"expected":expected,"changed":changed,"error":error,"rejected":rejected,"recovered":recovered})
			if not rejected or not recovered:_fail("compiled guard did not reject/recover");return
	var original:Shader=preview.water_material.shader
	preview.water_material.shader=load("res://assets/water_material_natural_candidate/water_height.gdshader")
	preview._seal_test1_effective_profile()
	var shader_error:String=preview.last_error
	preview.water_material.shader=original;preview.last_error=""
	var recovered:bool=preview._validate_compiled_inputs()
	rows.append({"field":"shader_path","error":shader_error,"rejected":shader_error=="compiled_shader_path_mismatch","recovered":recovered})
	if shader_error!="compiled_shader_path_mismatch" or not recovered:_fail("compiled path guard failed");return
	fields.clear();RenderingServer.call_on_render_thread(_read_fields)
	var deadline:=Time.get_ticks_msec()+10000
	while fields.size()<7:
		await process_frame
		if Time.get_ticks_msec()>deadline:_fail("compiled guard readback timeout");return
	var pairs:={}
	for name in fields:
		var ctx:=HashingContext.new();ctx.start(HashingContext.HASH_SHA256);ctx.update(fields[name]);pairs[name]=ctx.finish().hex_encode()==before[name].sha256
		if not pairs[name]:_fail("compiled guard changed authority");return
	var state_equal:bool=preview.completed_ticks==start_tick and preview.generation==start_generation and preview.visual_time_s==start_time
	var file:=FileAccess.open(output+"/compiled_guard.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases":rows,"authority_pairs":pairs,"state_equal":state_equal,"effective_compilation":preview.effective_compilation,"scope":"Runtime rejection test with expected ERROR logs; not engine-error-free operation, startup guard or ordinary restore/cost acceptance."},"\t"));file.close()
	if not state_equal:_fail("compiled guard clock/state changed")
