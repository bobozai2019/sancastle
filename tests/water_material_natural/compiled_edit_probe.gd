extends "res://tests/water_material_natural/foam_sequence_probe.gd"

var records:=[]
var point:=Vector3.ZERO
var selected:={}

func _settle(id: int) -> bool:
	var deadline:=Time.get_ticks_msec()+30000
	while preview.tick_pending or not preview.command_queue.pending.is_empty() or preview.checkpoint_capture_pending or (id>0 and not preview.tool_revision_by_command_id.has(id)):
		await process_frame
		if Time.get_ticks_msec()>deadline or not preview.last_error.is_empty():_fail("edit completion timeout/error: "+preview.last_error);return false
	return true

func _capture_state(label: String) -> bool:
	var before:=await _hash_state()
	var raw:={}
	for name in fields:
		var path:=output+"/"+label+"_"+String(name)+".bin"
		var f:=FileAccess.open(path,FileAccess.WRITE);f.store_buffer(fields[name]);f.close();raw[name]={"path":path,"sha256":before[name]}
	var water:ShaderMaterial=preview.water_material;var bed:ShaderMaterial=preview.terrain_material
	var originals:=[water.shader,bed.shader]
	var mats:=[water,bed];var params:=[]
	for mat in mats:
		var values:={}
		for uniform in mat.shader.get_shader_uniform_list():
			var value:Variant=mat.get_shader_parameter(uniform.name)
			if value!=null:values[String(uniform.name)]=value
		params.append(values)
	var images:={}
	for mode in ["compiled","original"]:
		for i in range(2):
			mats[i].shader=originals[i] if mode=="compiled" else load("res://assets/water_material_natural_candidate/water_height.gdshader" if i==0 else "res://assets/water_material_natural_candidate/bed_style.gdshader")
			for key in params[i]:mats[i].set_shader_parameter(key,params[i][key])
		for cam in [&"close",&"oblique",&"grazing"]:
			preview.set_fixture_camera(cam)
			for i in range(8):await process_frame
			await RenderingServer.frame_post_draw
			var path:String=output+"/%s_%s_%s.png"%[label,String(mode),String(cam)]
			if root.get_texture().get_image().save_png(path)!=OK:_fail("edit capture failed");return false
			images[String(mode)+"_"+String(cam)]={"path":path,"sha256":FileAccess.get_sha256(path)}
	for i in range(2):
		mats[i].shader=originals[i]
		for key in params[i]:mats[i].set_shader_parameter(key,params[i][key])
	if not preview._validate_compiled_inputs():_fail("compiled restoration mismatch");return false
	var after:=await _hash_state()
	if before!=after:_fail("edit presentation changed authority");return false
	var bindings:={}
	for pair in [["water",water],["bed",bed],["fine",preview.get_node("PrototypeFrontFoamDense").material_override],["contact",preview.get_node("ShoreContactOverlay").material_override]]:
		var values:={}
		for field in ["rock","sand","water"]:
			values[field]=pair[1].get_shader_parameter(field+"_state")==preview.get(field+"_texture")
		bindings[pair[0]]=values
	records.append({"label":label,"tick":preview.completed_ticks,"generation":preview.generation,"revision":preview.solver.state_revision,"visual_time_s":preview.visual_time_s,"water_clock":water.get_shader_parameter("visual_time_s"),"bed_clock":bed.get_shader_parameter("visual_time_s"),"inventory_m3":preview.shadow_domain.tool_inventory_m3,"raw":raw,"before":before,"after":after,"images":images,"bindings":bindings,"compilation":preview.effective_compilation.duplicate(true),"commands":preview.command_queue.applied_log.duplicate(true)})
	return true

func _lighting_sweep(_before: Dictionary) -> void:
	preview.playing=false;preview.replay_target_tick=-1;preview.set_fixture_camera(&"close")
	await _hash_state()
	var sand:PackedFloat32Array=fields.sand.to_float32_array();var water:PackedFloat32Array=fields.water.to_float32_array();var rock:PackedFloat32Array=fields.rock.to_float32_array()
	var best:=-1;var best_score:=INF
	for cell in range(65536):
		if sand[cell]<0.15 or water[cell]<0.005 or water[cell]>0.035:continue
		var x:int=cell%256;var z:int=cell/256;var near_dry:=false
		for dz in range(-2,3):
			for dx in range(-2,3):
				if water[clampi(z+dz,0,255)*256+clampi(x+dx,0,255)]<=0.001:near_dry=true
		if not near_dry:continue
		var world:=Vector3(-16.+(x+.5)*.125,rock[cell]+sand[cell],-16.+(z+.5)*.125)
		if preview.overview_camera.is_position_behind(world):continue
		var screen:Vector2=preview.overview_camera.unproject_position(world)
		if screen.x<96 or screen.x>root.size.x-96 or screen.y<96 or screen.y>root.size.y-96:continue
		var score:=screen.distance_squared_to(Vector2(root.size.x*.52,root.size.y*.65))
		if score<best_score:best=cell;best_score=score;point=world;selected={"cell":cell,"world":[world.x,world.y,world.z],"screen":[screen.x,screen.y],"sand_m":sand[cell],"water_m":water[cell]}
	if best<0:_fail("no visible sandy wet/dry edit cell");return
	if not await _capture_state("before"):return
	var submitted:=[]
	for row in [["paused_dig",&"remove_sand",.01,false],["paused_place",&"place_sand",.005,false],["realtime_dig",&"remove_sand",.005,true],["realtime_place",&"place_sand",.003,true]]:
		preview.set_fixture_camera(&"close")
		preview.playing=row[3]
		if row[3]:
			for i in range(30):await process_frame
		var tick:int=preview.completed_ticks
		var was_pending:bool=preview.water_tick_in_flight
		var error:StringName=preview._submit_brush(row[1],row[2],point,point,&"circle")
		var id:int=preview.command_id
		submitted.append({"label":row[0],"id":id,"kind":String(row[1]),"amount_m3":row[2],"playing_at_submit":preview.playing,"tick_at_submit":tick,"water_tick_in_flight":was_pending,"error":String(error)})
		if not error.is_empty():_fail("small edit rejected: "+String(error));return
		var deadline:=Time.get_ticks_msec()+30000
		while not preview.tool_revision_by_command_id.has(id):
			await process_frame
			if Time.get_ticks_msec()>deadline or not preview.last_error.is_empty():_fail("edit application failed");return
		preview.playing=false
		if not await _settle(id):return
		if not row[3] and preview.completed_ticks!=tick:_fail("paused edit advanced time");return
		if not await _capture_state(row[0]):return
	var file:=FileAccess.open(output+"/compiled_edits.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"selected":selected,"submitted":submitted,"states":records,"scope":"Existing ordinary brush/queue only. Same-state edited render pair/texture/clock checks, not formal integration/complete visual/contact or performance acceptance."},"\t"));file.close()
