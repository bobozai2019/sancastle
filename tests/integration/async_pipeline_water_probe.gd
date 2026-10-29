extends SceneTree

const Editor=preload("res://scripts/simulation/edit_validation/frame_pipeline/async_editor.gd")
const Water=preload("res://scripts/simulation/edit_validation/frame_pipeline/async_water.gd")
const Slots=preload("res://scripts/simulation/edit_validation/frame_pipeline/async_slots.gd")
const Coupled=preload("res://scripts/simulation/edit_validation/frame_pipeline/async_coupled.gd")
const Sediment=preload("res://scripts/simulation/erosion/gpu_sediment_coupler.gd")
const Materials=preload("res://scripts/simulation/brushes/brush_material_coupler.gd")
const Visuals=preload("res://scripts/simulation/edit_validation/frame_pipeline/async_visuals.gd")
const Foam=preload("res://scripts/visual/gpu_foam_field.gd")
const Gravel=preload("res://scripts/visual/gpu_gravel_field.gd")
const EditWire=preload("res://scripts/simulation/edit_validation/edit_protocol.gd")
var preview
var editor:=Editor.new()
var water:=Water.new()
var pool
var checks:=[]
var failed:=false
var output:=""
var initialized:=false
var initialize_ok:=false
var completed:={}
var decision_bytes:=PackedByteArray()
var fields:={}
var remaining:=0
var reset_done:=false
var reference_done:=false
var released:=false
var actual_time:=0.0
var comparisons:=[]
var with_coupled:=false
var with_mold:=false
var coupled:=Coupled.new()
var sediment:=Sediment.new()
var material:=Materials.new()
var originals:=[]
var compared_fields: Array=["water","momentum_x","momentum_z"]
var with_boundary:=false
var with_visuals:=false
var visuals:=Visuals.new()
var foam:=Foam.new()
var gravel:=Gravel.new()
var initial_foam_index:=0
var initial_gravel_index:=0
var begin_time:=0.0
var interleaved_ticks:=0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		if arg=="--coupled":with_coupled=true
		if arg=="--mold":with_mold=true
		if arg=="--boundary":with_boundary=true
		if arg=="--visuals":with_visuals=true
	call_deferred("_run")

func check(label: String, value: bool) -> void:
	checks.append({"name":label,"pass":value})
	failed=failed or not value
	print("ASYNC_WATER ",label," ",value)

func _initialize_render() -> void:
	editor.edit_spirvs=preview.edit_spirvs
	editor.water_spirvs=preview.water_spirvs
	editor.fast_full_wet=preview.solver.fast_full_wet
	editor.connected_runs=preview.solver.connected_runs
	initialize_ok=editor.initialize(RenderingServer.get_rendering_device(),preview.shadow_domain,
		preview.spirvs[0],preview.spirvs[1],preview.spirvs[2],preview.spirvs[3],preview.spirvs[4],preview.spirvs[5],preview.spirvs[6],preview.spirvs[7])
	if initialize_ok:initialize_ok=editor.enable_async() and water.initialize(editor)
	if initialize_ok and with_coupled:
		material.cohesion_yield_height_m=preview.material_coupler.cohesion_yield_height_m
		initialize_ok=sediment.initialize(editor,preview.spirvs[10],preview.spirvs[11]) and material.initialize(editor,sediment.dirty_max_texture,preview.spirvs[12],preview.spirvs[13],preview.spirvs[14])
		if initialize_ok:initialize_ok=coupled.initialize(water,sediment,material)
	if initialize_ok and with_boundary:initialize_ok=water.configure_boundary(Vector3(0.1,0.11,0.35),[Vector4(0.0,1.0,0.05,0.3)])
	if initialize_ok and with_visuals:
		var bed:=PackedFloat32Array()
		bed.resize(65536)
		for index in 65536:bed[index]=preview.shadow_domain.rock[index]+preview.shadow_domain.sand[index]
		initialize_ok=foam.initialize(editor,preview.spirvs[17],PackedFloat32Array(),bed) and gravel.initialize(editor,preview.gravel_spirv,preview.gravel_profile,preview.generation,0,0)
		# This harness restores a fixed fixture between candidate/reference runs.
		# Give only its private foam images COPY_TO; normal main formats stay intact.
		if initialize_ok:
			foam.release_uniform_sets()
			var zero:=PackedFloat32Array()
			zero.resize(65536*2)
			for pair in [[foam.textures,zero.to_byte_array()],[foam.bed_textures,bed.to_byte_array()]]:
				for index in 2:
					var old: RID=pair[0][index]
					var format:=editor.rd.texture_get_format(old)
					format.usage_bits|=RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
					pair[0][index]=editor.rd.texture_create(format,RDTextureView.new(),[pair[1]])
					editor.rd.free_rid(old)
			initialize_ok=foam.configure_uniforms(editor)
		if initialize_ok:initialize_ok=visuals.initialize(water,foam,gravel)
		initial_foam_index=foam.current_index
		initial_gravel_index=gravel.current_index
	if initialize_ok:
		for field in ["sand","sediment","wetness","compaction","mold_support"]:
			for slot in 2:originals.append({"target":editor.textures[field][slot],"source":editor._new_texture_copy(editor.textures[field][slot]),"extent":Vector3(256,256,1)})
		if with_visuals:
			for texture in foam.textures+foam.bed_textures+gravel.textures:
				var format:=editor.rd.texture_get_format(texture)
				format.usage_bits|=RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
				var source:=editor.rd.texture_create(format,RDTextureView.new())
				var extent:=Vector3(format.width,format.height,1)
				if editor.rd.texture_copy(texture,source,Vector3.ZERO,Vector3.ZERO,extent,0,0,0,0)!=OK:call_deferred("_error","fixture_copy")
				originals.append({"target":texture,"source":source,"extent":extent})
	call_deferred("_initialized")

func _initialized() -> void:
	initialized=true

func _reset_render(speed: float, invalid: bool) -> void:
	for item in originals:
		if editor.rd.texture_copy(item.source,item.target,Vector3.ZERO,Vector3.ZERO,item.extent,0,0,0,0)!=OK:call_deferred("_error","fixture_restore")
	if with_visuals:
		foam.current_index=initial_foam_index
		gravel.current_index=initial_gravel_index
		gravel.completed_tick=0
		gravel.revision=0
	var h:=PackedFloat32Array()
	h.resize(65536)
	h.fill(0.1)
	var q:=PackedFloat32Array()
	q.resize(65536)
	q.fill(maxf(0.0,speed-sqrt(9.81*0.1))*0.1)
	if invalid:q[1234]=NAN
	var zero:=PackedFloat32Array()
	zero.resize(65536)
	for pair in [["water",h],["momentum_x",q],["momentum_z",zero]]:
		for slot in 2:
			var source:=editor._create_texture(RenderingDevice.DATA_FORMAT_R32_SFLOAT,pair[1].to_byte_array())
			editor.rd.texture_copy(source,editor.textures[pair[0]][slot],Vector3.ZERO,Vector3.ZERO,Vector3(256,256,1),0,0,0,0)
			editor.rd.free_rid(source)
	editor.current_index=0
	editor.state_revision=0
	editor.tide_ledger_pending=false
	call_deferred("_reset_finished")

func _reset_finished() -> void:
	reset_done=true

func reset(speed: float, invalid: bool=false) -> void:
	reset_done=false
	RenderingServer.call_on_render_thread(_reset_render.bind(speed,invalid))
	while not reset_done:await process_frame

func _submit_render(id: Dictionary, dt: float) -> void:
	var error:=water.dispatch(id,dt,_arrived)
	if not error.is_empty():call_deferred("_error",error)

func _error(error: String) -> void:
	check(error,false)

func _arrived(bytes: PackedByteArray, id: Dictionary) -> void:
	call_deferred("_receive",bytes,id)

func _receive(bytes: PackedByteArray, id: Dictionary) -> void:
	check("completion_identity_%d"%id.batch_seq,pool.completed(bytes,id).is_empty())
	completed[id.batch_seq]=id

func tick(dt: float) -> Dictionary:
	var acquired: Dictionary=pool.acquire()
	check("acquire",acquired.error.is_empty())
	var id: Dictionary=acquired.identity
	pool.submitted(id)
	RenderingServer.call_on_render_thread(_submit_render.bind(id,dt))
	var deadline:=Time.get_ticks_msec()+30000
	while not completed.has(id.batch_seq) and Time.get_ticks_msec()<deadline:await process_frame
	check("tick_complete",completed.has(id.batch_seq))
	decision_bytes=PackedByteArray()
	RenderingServer.call_on_render_thread(_decision_render)
	while decision_bytes.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check("decision_bytes",decision_bytes.size()==64)
	var result: Dictionary=pool.consume(id)
	RenderingServer.call_on_render_thread(_retire_render.bind(id))
	result.decision=decision_bytes
	return result

func _decision_render() -> void:
	editor.rd.buffer_get_data_async(water.decision,_decision_arrived)

func _decision_arrived(bytes: PackedByteArray) -> void:
	call_deferred("_decision_store",bytes)

func _decision_store(bytes: PackedByteArray) -> void:
	decision_bytes=bytes

func _retire_render(id: Dictionary) -> void:
	editor.retire_async(id)

func _edit_render(id: Dictionary, command_id: int) -> void:
	var commands:=[]
	for index in 2:
		var command:={"command_id":command_id+index,"generation":preview.generation,"sim_tick":0,"kind":&"place_sand","shape":&"circle","transform":{"position_m":Vector3(-2,0,float(index)*0.5)},"radius_m":0.3,"strength":1.0,"amount_m3":0.015,"seed":101}
		commands.append(EditWire.encode(command,command_id+index,999,256,0.125,3,0.015001,0.25))
	var error:=editor.dispatch_async_batch(id,commands,_arrived)
	if not error.is_empty():call_deferred("_error",error)

func interleave() -> void:
	await reset(10.0)
	var ids:=[]
	for index in 3:
		var id: Dictionary=pool.acquire().identity
		pool.submitted(id)
		ids.append(id)
		if index==1:RenderingServer.call_on_render_thread(_submit_render.bind(id,0.001))
		else:RenderingServer.call_on_render_thread(_edit_render.bind(id,1000+index*2))
	check("edit_water_edit_before_cpu_consume",pool.active_count()==3)
	var deadline:=Time.get_ticks_msec()+30000
	while not ids.all(func(id):return completed.has(id.batch_seq)) and Time.get_ticks_msec()<deadline:await process_frame
	var results:=[]
	for id in ids:
		var result: Dictionary=pool.consume(id)
		check("interleaved_completion_%d"%id.batch_seq,result.error.is_empty() and result.error_flags==0)
		results.append(result)
		RenderingServer.call_on_render_thread(_retire_render.bind(id))
	check("water_advances_between_real_edits",results[1].sim_tick==results[0].sim_tick+1 and results[2].sim_tick==results[1].sim_tick and results[2].revision==results[1].revision+2)
	check("interleaved_actual_clock",absf(results[1].advanced_time_s-results[0].advanced_time_s-results[1].actual_dt)<1e-7 and results[2].advanced_time_s==results[1].advanced_time_s)
	interleaved_ticks=1

func snapshot() -> Dictionary:
	fields={}
	remaining=compared_fields.size()*2
	RenderingServer.call_on_render_thread(_read_render)
	while remaining>0:await process_frame
	return fields.duplicate(true)

func _read_render() -> void:
	for field in compared_fields:
		var textures: Array
		var current: int=editor.current_index
		if field=="foam":textures=foam.textures;current=foam.current_index
		elif field=="bed_history":textures=foam.bed_textures;current=foam.current_index
		elif field=="gravel":textures=gravel.textures;current=gravel.current_index
		else:textures=editor.textures[field]
		editor.rd.texture_get_data_async(textures[current],0,_read_arrived.bind(field))
		editor.rd.texture_get_data_async(textures[1],0,_read_arrived.bind(field+"_slot1"))

func _read_arrived(bytes: PackedByteArray, field: String) -> void:
	call_deferred("_read_store",bytes,field)

func _read_store(bytes: PackedByteArray, field: String) -> void:
	fields[field]=bytes
	remaining-=1

func reference(dt: float, n: int) -> void:
	reference_done=false
	RenderingServer.call_on_render_thread(_reference_render.bind(dt,n))
	while not reference_done:await process_frame

func _reference_render(dt: float, n: int) -> void:
	if with_boundary:
		var u:=begin_time
		var wave:=0.05*pow(sin(PI*u),2.0)*(0.95+0.05*sin(TAU*u+0.3))
		var level:=0.1+0.11*sin(begin_time*0.35)+wave
		if not editor.dispatch_wave_boundary(level,wave):call_deferred("_error","reference_boundary")
		if with_coupled:sediment.dispatch_after_boundary()
		editor.request_tide_ledger(_legacy_ledger)
	if not editor.dispatch_tick_validated(dt,n,editor.state_revision,_reference_coupled if with_coupled else Callable()):call_deferred("_error","reference_dispatch")
	if with_visuals:
		foam.dispatch(editor,dt)
		gravel.advance(editor,1,editor.state_revision,preview.generation,dt)
	call_deferred("_reference_finished")

func _legacy_ledger(_source: float, _sink: float, _revision: int, valid: bool) -> void:
	if not valid:call_deferred("_error","reference_ledger")

func _reference_coupled(dt: float) -> bool:
	return sediment.dispatch_after_water_substep(dt) and material.dispatch_after_erosion(dt)

func _reference_finished() -> void:
	reference_done=true

func _release_render() -> void:
	for item in originals:editor.rd.free_rid(item.source)
	originals.clear()
	if with_coupled:
		coupled.detach()
	if with_visuals:visuals.detach()
	# Release sets referencing material support flags before their owner frees
	# those buffers (RD otherwise invalidates these dependent sets implicitly).
	water.release()
	if with_visuals:
		foam.release()
		gravel.release()
	if with_coupled:
		material.release()
		sediment.release()
	editor.release()
	call_deferred("_released")

func _released() -> void:
	released=editor.rd==null and water.rd==null

func _run() -> void:
	preview=load("res://scenes/main.tscn").instantiate()
	preview.playing=false
	root.add_child(preview)
	var deadline:=Time.get_ticks_msec()+60000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check("main_ready",preview.ready_for_ticks and preview.last_error.is_empty())
	if with_mold:
		var mold:=PackedFloat32Array()
		mold.resize(65536)
		for index in 65536:mold[index]=preview.shadow_domain.sand[index]*0.5
		preview.shadow_domain.set_meta("brush_initial_mold_depth",mold)
	if with_coupled:compared_fields.append_array(["sand","sediment","wetness","compaction","mold_support"])
	if with_visuals:compared_fields.append_array(["foam","bed_history","gravel"])
	pool=Slots.new(preview.generation)
	RenderingServer.call_on_render_thread(_initialize_render)
	while not initialized and Time.get_ticks_msec()<deadline:await process_frame
	check("gpu_water_initialized",initialized and initialize_ok)
	if initialize_ok:
		for desired in [1,2,3,64,100]:
			var requested_dt:=0.001
			var speed: float=(float(desired)-0.25)*editor.COURANT*editor.cell_size_m/requested_dt
			await reset(speed)
			begin_time=actual_time
			var result: Dictionary=await tick(requested_dt)
			var d: PackedByteArray=result.decision
			var expected_n:=mini(desired,64)
			check("gpu_cfl_n_%d"%desired,d.decode_u32(4)==expected_n)
			check("gpu_status_%d"%desired,d.decode_u32(16)==(1 if desired>64 else 0) and result.error_flags==0)
			var expected_dt:=minf(requested_dt,64.0*editor.COURANT*editor.cell_size_m/d.decode_float(0))
			check("safe_actual_dt_%d"%desired,absf(d.decode_float(12)-expected_dt)<1e-8 and (result.actual_dt<requested_dt if desired>64 else absf(result.actual_dt-requested_dt)<1e-8))
			actual_time+=result.actual_dt
			check("gpu_clock_%d"%desired,absf(result.advanced_time_s-actual_time)<1e-7 and result.sim_tick==pool.batch_seq)
			check("normalized_slot_%d"%desired,editor.current_index==0 and d.decode_u32(20)==0)
			var candidate: Dictionary=await snapshot()
			if expected_n%2==1:
				for field in compared_fields:
					if field not in ["foam","bed_history","gravel"]:check("odd_normalized_copy_%d_%s"%[desired,field],candidate[field]==candidate[field+"_slot1"])
			await reset(speed)
			await reference(result.actual_dt,expected_n)
			var comparison: Dictionary=await snapshot()
			for field in compared_fields:
				var a:=PackedFloat32Array()
				var b:=PackedFloat32Array()
				if field in ["wetness","compaction"]:
					for index in 65536:
						a.append(candidate[field].decode_half(index*2))
						b.append(comparison[field].decode_half(index*2))
				else:
					a=candidate[field].to_float32_array()
					b=comparison[field].to_float32_array()
				var max_delta:=0.0
				var example:={}
				for index in a.size():
					max_delta=maxf(max_delta,absf(a[index]-b[index]))
					if a[index]!=b[index] and example.is_empty():example={"index":index,"candidate":a[index],"reference":b[index]}
				comparisons.append({"case":desired,"field":field,"max_delta":max_delta,"example":example})
				# Dynamic GPU exp and CPU double exp narrowed to f32 may differ.
				# Keep water-core exact; coupled f32 tolerance is one micrometre,
				# material half tolerance is one half-precision ULP at unit scale.
				var tolerance:=0.0009765625 if field in ["wetness","compaction"] else 0.000001
				check("water_reference_%d_%s"%[desired,field],max_delta<=tolerance if with_coupled else candidate[field]==comparison[field])
		if with_coupled:await interleave()
		await reset(10.0,true)
		var before: Dictionary=await snapshot()
		var bad: Dictionary=await tick(0.001)
		check("invalid_cfl_stops",bad.error_flags!=0 and bad.decision.decode_u32(16)==2 and bad.decision.decode_u32(4)==0 and bad.sim_tick==5+interleaved_ticks)
		var after: Dictionary=await snapshot()
		for field in before:check("invalid_cfl_preserves_"+field,before[field]==after[field])
		pool.stop_admission()
		RenderingServer.call_on_render_thread(_release_render)
		while not released:await process_frame
		check("resources_released",released)
	await preview.shutdown()
	preview.queue_free()
	await process_frame
	if not output.is_empty():
		var file:=FileAccess.open(output,FileAccess.WRITE)
		if file!=null:file.store_string(JSON.stringify({"pass":not failed,"checks":checks,"comparisons":comparisons,"events":pool.events,"with_coupled":with_coupled,"with_mold":with_mold,"with_boundary":with_boundary,"with_visuals":with_visuals,"scope":"P03 candidate components; main integration pending"},"\t"))
	quit(1 if failed else 0)
