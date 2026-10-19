extends RefCounted
var lab
var results := []

func wait_idle() -> void:
	while lab.busy or lab.reset_pending:
		await lab.get_tree().process_frame

func snapshot(tag: String) -> PackedByteArray:
	lab.snapshot_pending=true
	await lab.completed
	await wait_idle()
	var file := FileAccess.open(ProjectSettings.globalize_path(lab.run_dir)+"/"+tag+".rgba32f",FileAccess.WRITE)
	file.store_buffer(lab.last_field)
	file=FileAccess.open(ProjectSettings.globalize_path(lab.run_dir)+"/"+tag+".sediment32f",FileAccess.WRITE)
	file.store_buffer(lab.last_sediment)
	return lab.last_field

func reset(mode: int,fixture: String="flat") -> void:
	lab.mode=mode
	lab.fixture=fixture
	lab.reset_pending=true
	await lab.reset_done
	await snapshot("init_g"+str(lab.generation))

func check(condition: bool, message: String) -> void:
	results.append({"pass":condition,"message":message})
	print(("PASS " if condition else "FAIL ")+message)

func picture(tag: String) -> void:
	await lab.get_tree().process_frame
	await RenderingServer.frame_post_draw
	lab.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(lab.run_dir)+"/"+tag+".png")

func edit(a: Vector2,b: Vector2,op: int=0,first: bool=true) -> void:
	check(lab.enqueue(lab.make_command(a,b,op,first)).is_empty(),"accept edit")
	while not lab.commands.is_empty() or lab.busy:await lab.get_tree().process_frame

func run(node, kind: String) -> void:
	lab=node
	await snapshot("initial")
	if kind in ["soak_repeat","soak_sweep","cost","cost_detail"]:
		await soak(kind)
	elif kind=="lifecycle":
		await edit(Vector2.ZERO,Vector2.ZERO)
		await snapshot("one_edit")
		check(lab.latest[3]==0.,"lifecycle edit finite")
	elif kind=="visual":
		await visual()
	else:
		await numeric()
	var file := FileAccess.open(ProjectSettings.globalize_path(lab.run_dir)+"/suite.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(results,"\t"))
	lab.export_run()
	lab.closing=true

func visual() -> void:
	for mode in 3:
		for op in 3:
			await reset(mode)
			lab.get_node("Interface/Panel/Rows/Operation").select(op)
			await edit(Vector2.ZERO,Vector2.ZERO,op)
			await snapshot("visual_%d_%d"%[mode,op])
			lab._on_view(2)
			await picture("visual_%d_%d"%[mode,op])
			for k in 12:
				lab._submit({},16,false)
				await lab.completed
			await picture("visual_%d_%d_after"%[mode,op])
	await reset(2)
	await picture("flat")
	# Engine-generated input exercises the same viewport picking and command
	# path, and is labelled separately from human/desktop input.
	lab.set_meta("engine_injected",true)
	var before: int = lab.accepted.size()
	var camera: Camera3D=lab.get_node("Camera")
	for i in 5:
		var position := camera.unproject_position(Vector3(0,.5,-1.+i*.5))
		if i==0:
			var down := InputEventMouseButton.new()
			down.button_index=MOUSE_BUTTON_LEFT
			down.position=position
			down.pressed=true
			Input.parse_input_event(down)
		else:
			var move := InputEventMouseMotion.new()
			move.position=position
			move.button_mask=MOUSE_BUTTON_MASK_LEFT
			Input.parse_input_event(move)
		await lab.get_tree().process_frame
	var up := InputEventMouseButton.new()
	up.button_index=MOUSE_BUTTON_LEFT
	up.position=camera.unproject_position(Vector3(0,.5,1))
	up.pressed=false
	Input.parse_input_event(up)
	for k in 3:await lab.get_tree().process_frame
	while not lab.commands.is_empty() or lab.busy:await lab.get_tree().process_frame
	check(lab.accepted.size()>before,"engine pointer accepted through viewport")
	await snapshot("pointer_edit")
	lab._on_view(0)
	await picture("pointer_edit")
	for view in 4:
		lab._on_view(view)
		await picture("pointer_view_"+str(view))
	lab.remove_meta("engine_injected")

func numeric() -> void:
	for mode in 3:
		for op in 3:
			await reset(mode)
			await edit(Vector2.ZERO,Vector2.ZERO,op)
			await snapshot("mode%d_op%d_edit"%[mode,op])
			check(lab.latest[3]==0.,"finite edit mode%d op%d"%[mode,op])
			var before: float = lab.latest[0]
			for k in 6:
				var target: float=[.1,.5,1.,2.,5.,6.][k]
				while lab.latest[20]<target:
					lab._submit({},16,false)
					await lab.completed
					if not lab.last_error.is_empty():return
				await snapshot("mode%d_op%d_t%d"%[mode,op,k])
			check(absf(lab.latest[0]-before)/before<.005,"closed mass mode%d op%d"%[mode,op])
	# Frozen-time path sampling and queue batching.
	for samples in [1,8,32]:
		await reset(2)
		for i in samples+1:
			await edit(Vector2(0,-1.),Vector2(0,-1.+2.*i/samples),0,i==0)
		await snapshot("sampling_"+str(samples))
	await reset(2)
	await edit(Vector2(-1,-1),Vector2(-1,1),0,true)
	await edit(Vector2(-1,1),Vector2(1,1),0,false)
	await snapshot("curved_L")
	await reset(2)
	for i in 9:
		check(lab.enqueue(lab.make_command(Vector2(0,-1.),Vector2(0,-1.+2.*i/8),0,i==0)).is_empty(),"batch accepted")
	while not lab.commands.is_empty() or lab.busy:await lab.get_tree().process_frame
	await snapshot("sampling_batch8")
	await reset(2)
	lab.gain=0.
	var zero_before := await snapshot("zero_before")
	await edit(Vector2.ZERO,Vector2.ZERO)
	var zero_after := await snapshot("zero_after")
	var q_unchanged := true
	for i in lab.grid*lab.grid:
		q_unchanged=q_unchanged and zero_before.slice(i*16+4,i*16+16)==zero_after.slice(i*16+4,i*16+16)
	check(q_unchanged,"zero gain h and q byte unchanged")
	lab.gain=1.
	for fps in [30,60,144]:
		await reset(2)
		Engine.max_fps=fps
		for i in 9:
			await edit(Vector2(0,-1.),Vector2(0,-1.+2.*i/8),0,i==0)
			lab._submit({},4,false)
			await lab.completed
		await snapshot("frequency_"+str(fps))
	Engine.max_fps=0
	await reset(2)
	for i in 64:
		check(lab.enqueue(lab.make_command(Vector2.ZERO,Vector2.ZERO,0,i==0)).is_empty(),"bounded queue accepted")
	check(lab.enqueue(lab.make_command(Vector2.ZERO,Vector2.ZERO,0,false))=="queue_full","65th packet backpressure")
	lab._cancel_queued("test_cancelled_queue_capacity")
	await reset(2)
	var command: Dictionary=lab.make_command(Vector2.ZERO,Vector2.ZERO)
	check(lab.enqueue(command).is_empty(),"valid packet")
	var duplicate := command.duplicate()
	duplicate.id+=1
	check(lab.enqueue(duplicate)=="duplicate_sample","duplicate sample rejected")
	var stale := command.duplicate()
	stale.generation-=1
	check(lab.enqueue(stale)=="stale_generation","stale rejected")
	var bad := command.duplicate()
	bad.id+=2
	bad.sample+=1
	bad.gain=NAN
	check(lab.enqueue(bad)=="invalid_input","NaN rejected")
	await wait_idle()
	while not lab.commands.is_empty() or lab.busy:await lab.get_tree().process_frame
	await snapshot("rejection_after")
	var tick: float = lab.latest[21]
	for k in 5:await lab.get_tree().process_frame
	check(lab.latest[21]==tick,"pause holds tick")
	lab.step_pending=1
	await lab.completed
	check(lab.latest[21]==tick+1.,"single step exact")
	# Repeated sample with new ID must leave coverage and source unchanged.
	var original := await snapshot("repeat_before")
	await edit(Vector2.ZERO,Vector2.ZERO,0,false)
	var repeated := await snapshot("repeat_after")
	check(original==repeated,"stationary sample no injection")
	for fixture in ["thin","islands","wall","platform20","platform80","wave"]:
		for mode in 3:
			await reset(mode,fixture)
			await edit(Vector2.ZERO,Vector2.ZERO,1)
			for k in 4:
				lab._submit({},32,false)
				await lab.completed
			await snapshot("boundary_%s_%d"%[fixture,mode])
			check(lab.latest[3]==0.,"boundary finite "+fixture+str(mode))
	for k in 10:
		await reset(k%3)
	check(lab.release_count>0,"ten reset RID retirements")

func soak(kind: String) -> void:
	var duration := 90. if kind.begins_with("cost") else 300.
	lab.depth=.02
	var stroke_count := 0
	var started := Time.get_ticks_msec()
	var next_input := 0
	var next_bin := 0
	var last_mode := -1
	var bins := []
	lab.paused=false
	while float(Time.get_ticks_msec()-started)/1000.<duration:
		var elapsed := float(Time.get_ticks_msec()-started)/1000.
		var selected := int(elapsed/10.)%3 if kind.begins_with("cost") else 2
		if selected!=last_mode:
			lab.paused=true
			await wait_idle()
			await reset(selected)
			lab.paused=false
			last_mode=selected
		if Time.get_ticks_msec()>=next_input and not lab.busy and lab.commands.is_empty():
			var point := Vector2(0,0)
			if kind=="soak_sweep":point=Vector2(sin(elapsed*.43),cos(elapsed*.31))*9.
			lab.depth=.02 if stroke_count%2==0 else -.02
			var error: String=lab.enqueue(lab.make_command(point,point,2,true))
			if error.is_empty():stroke_count+=1
			next_input=Time.get_ticks_msec()+80
		if elapsed>=next_bin:
			bins.append({"wall_s":elapsed,"metrics":Array(lab.latest),"objects":Performance.get_monitor(Performance.OBJECT_COUNT),"video_mem":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),"queue":lab.commands.size()})
			next_bin+=10
		if not lab.last_error.is_empty():break
		await lab.get_tree().process_frame
	lab.paused=true
	await wait_idle()
	while not lab.commands.is_empty() or lab.busy:await lab.get_tree().process_frame
	await snapshot("end_editing")
	var water: float = lab.latest[0]
	if not kind.begins_with("cost"):
		lab.paused=false
		var stop := Time.get_ticks_msec()
		while Time.get_ticks_msec()-stop<30000:await lab.get_tree().process_frame
		lab.paused=true
		await wait_idle()
		await snapshot("after_release30")
	check(lab.last_error.is_empty(),kind+" finite")
	check(absf(lab.latest[0]-water)/water<.005,kind+" release mass")
	var f := FileAccess.open(ProjectSettings.globalize_path(lab.run_dir)+"/bins.json",FileAccess.WRITE)
	f.store_string(JSON.stringify(bins))
