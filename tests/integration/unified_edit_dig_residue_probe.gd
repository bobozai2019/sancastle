extends "res://tests/integration/unified_edit_target_probe.gd"

# Regression for shovel -> ordinary dig. A single thin donor must not be
# omitted from the allocation denominator while still donating sand.
var records: Array=[]
var before_dig:=PackedFloat32Array()
var after_dig:=PackedFloat32Array()
var dig_command: Dictionary={}
var frozen_dig: Dictionary={}
var metrics: Dictionary={}
const CENTER:=128*256+128
const AREA:=0.015625

func _run() -> void:
	started=Time.get_ticks_msec()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	registry=preload("res://scripts/simulation/unified_edit/profile_registry.gd").new()
	check("registry",registry.initialize(Array(load("res://assets/unified_edit/default_catalog.tres").profiles)).is_empty())
	var simulation:={"enable_erosion":false,"enable_brush_water":true,"unrestricted_sand_tools":true,"enable_structures":false,"local_front_history":false,"rise_front_history":false,"contact_history":false}
	var configuration:=Config.freeze(registry,"main_beach",simulation,{"foam_enabled":false,"gravel_enabled":false},{},{"engine":Engine.get_version_info().string,"probe":"dig_residue"},PackedStringArray(Pipeline.SOURCE_PATHS+Pipeline.ADAPTER_SOURCES))
	check("configuration",configuration.error.is_empty())
	if not configuration.error.is_empty():finish();return
	source_hashes=configuration.value.sources.duplicate(true)
	check("configure",pipeline.configure(registry,configuration.value,9007199254740993).is_empty())
	domain=Domain.new(256,0.125);domain.domain_id=&"main_beach";domain.generation=9007199254740993
	domain.sand.fill(0.2);domain.water.fill(0.15 if probe_case=="shovel_wet" else 0.0);domain.rock.fill(0.0)
	var use_shovel:=probe_case.begins_with("shovel") or probe_case=="queued_switch"
	if use_shovel:
		domain.sand.fill(0.03);domain.sand[CENTER]=0.140655
	else:domain.sand[CENTER]=0.00003
	if probe_case=="thresholds":
		for pair in [[CENTER-2,0.0],[CENTER-1,0.00003],[CENTER,0.000064],[CENTER+1,0.000065]]:domain.sand[pair[0]]=pair[1]
	elif probe_case=="all_dust":domain.sand.fill(0.00003)
	elif probe_case=="limited":domain.sand.fill(0.00003);domain.sand[CENTER+1]=0.05
	RenderingServer.call_on_render_thread(pipeline.initialize_render.bind(domain))
	while not pipeline.initialized and pipeline.fault_reason().is_empty() and Time.get_ticks_msec()-started<20000:await process_frame
	check("initialized",pipeline.initialized and pipeline.fault_reason().is_empty())
	if not pipeline.initialized or not pipeline.fault_reason().is_empty():finish();return
	var queued:=probe_case=="queued_switch"
	if use_shovel:
		await submit("begin",control_identity(),"begin",not queued)
		var shovel:=shape_request(&"shovel_v1",Vector2(-1,0),Vector2(1,0),1,{},1,11,2)
		if probe_case=="shovel_wet":shovel.features.water_policy=2;shovel.parameters.speed_m_s=0.25
		await submit("shovel",shovel,"",not queued)
		await submit("end",control_identity(),"end",not queued)
	if not queued:
		await capture("before");before_dig=fields.sand.to_float32_array()
		if use_shovel:check("shovel_produced_thin_residue",before_dig[CENTER]>0.0 and before_dig[CENTER]*AREA<1e-6)
	serial+=1
	dig_command=request(serial,&"dig_sweep_v1" if probe_case=="shovel_sweep" else &"dig_v1",Vector2.ZERO,0.05 if probe_case=="limited" else 0.01)
	if probe_case=="shovel_sweep":dig_command.end_xz_m=Vector2(0.05,0)
	if probe_case=="low_strength":dig_command.parameters.strength=1.0/3.0
	if probe_case=="shovel_wet":dig_command.features.water_policy=2;dig_command.parameters.speed_m_s=0.25
	frozen_dig=preload("res://scripts/simulation/unified_edit/intent.gd").freeze(registry,dig_command,"main_beach",9007199254740993).value
	await submit("dig",dig_command)
	if queued:
		for record in records:
			record.result=pipeline.result(record.command.command_id)
			check("queued_"+record.label+"_completed",record.result.get("error_code",-1)==0)
		check("queued_shovel_applied",records[1].result.get("outcome")==L.Outcome.APPLIED)
	await capture("after");after_dig=fields.sand.to_float32_array()
	var result:=pipeline.result(dig_command.command_id)
	check("switch_keeps_pipeline_healthy",pipeline.fault_reason().is_empty())
	if not result.is_empty():
		check("dig_expected_outcome",result.outcome==(L.Outcome.NO_CHANGE if probe_case=="all_dust" else L.Outcome.APPLIED))
		var nominal:=Wire.gpu_nominal(frozen_dig)
		check("receipt_within_request",result.removed_m3<=nominal+result.eps_sand_m3)
		if not before_dig.is_empty():
			var removed:=0.0;var monotone:=true;var finite:=true
			for index in before_dig.size():
				removed+=(float(before_dig[index])-float(after_dig[index]))*AREA
				monotone=monotone and after_dig[index]<=before_dig[index]
				finite=finite and is_finite(after_dig[index]) and after_dig[index]>=0.0
			check("raw_dig_never_adds_sand",monotone);check("raw_sand_finite_nonnegative",finite)
			check("raw_volume_within_request",removed<=nominal+result.eps_sand_m3)
			check("receipt_matches_raw_volume",absf(removed-result.removed_m3)<=maxf(1e-7,result.eps_sand_m3))
			check("excluded_thin_center_unchanged",before_dig[CENTER]==after_dig[CENTER])
			if probe_case=="limited":check("limited_supply_does_not_overdraw",removed>0.0 and removed<nominal and after_dig[CENTER+1]<=before_dig[CENTER+1])
			metrics={"requested_m3":nominal,"raw_removed_m3":removed,"receipt_removed_m3":result.removed_m3,"eps_sand_m3":result.eps_sand_m3,"thin_center_before_m":before_dig[CENTER],"thin_center_after_m":after_dig[CENTER]}
		check("sand_slots_match",fields.sand==fields.sand1)
	if pipeline.fault_reason().is_empty():
		# A following unrelated edit must still be accepted and completed.
		serial+=1;await submit("followup_fill",request(serial,&"fill_v1",Vector2(3,3),0.01))
		pipeline.close_admission();RenderingServer.call_on_render_thread(pipeline.release_render)
		var end:=Time.get_ticks_msec()
		while not pipeline.released and Time.get_ticks_msec()-end<10000:await process_frame
		check("released",pipeline.released)
	finish()

func submit(label: String, command: Dictionary, mode: String="", settle: bool=true) -> void:
	var admission: Dictionary=pipeline.submit_intent(command) if mode.is_empty() else pipeline.submit_control(mode,command)
	check(label+"_admitted",admission.accepted)
	if settle:
		await await_idle()
		var result:=pipeline.result(command.command_id)
		check(label+"_valid_result",not result.is_empty() and result.get("error_code",-1)==0)
		if label=="followup_fill":check("followup_fill_applied",result.get("outcome")==L.Outcome.APPLIED)
	records.append({"label":label,"command":command,"admission":admission,"result":pipeline.result(command.command_id),"fault":String(pipeline.fault_reason())})

func read_raw() -> void:
	var rd: RenderingDevice=pipeline.transport.rd
	for pair in [["sand",pipeline.state.textures.sand[0]],["sand1",pipeline.state.textures.sand[1]]]:
		if rd.texture_get_data_async(pair[1],0,_field_render.bind(pair[0]))!=OK:call_deferred("_read_failed",pair[0])
	for slot in 3:
		if rd.buffer_get_data_async(pipeline.transport.resources[slot].output,_field_render.bind("output_"+str(slot)),0,L.OUTPUT_BYTES)!=OK:call_deferred("_read_failed","output_"+str(slot))
	if rd.buffer_get_data_async(pipeline.executor.buffers.decision,_field_render.bind("decision"),0,128)!=OK:call_deferred("_read_failed","decision")
	if rd.buffer_get_data_async(pipeline.executor.buffers.command,_field_render.bind("command"),0,L.COMMAND_BYTES)!=OK:call_deferred("_read_failed","command")

func capture(label: String) -> void:
	fields={};remaining=7;RenderingServer.call_on_render_thread(read_raw)
	var begin:=Time.get_ticks_msec()
	while remaining>0 and Time.get_ticks_msec()-begin<10000:await process_frame
	check(label+"_readback",remaining==0 and fields.size()==7)
	for field in fields:FileAccess.open(output.get_base_dir().path_join(label+"_"+field+".bin"),FileAccess.WRITE).store_buffer(fields[field])

func finish() -> void:
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"case":probe_case,"checks":checks,"records":records,"metrics":metrics,"fault":String(pipeline.fault_reason()),"frozen_dig":frozen_dig,"source_hashes":source_hashes,"engine":Engine.get_version_info(),"scope":"Actual D3D12 production GPU kernels, shovel/dig ordering, thin-donor authorization, raw volume and continued edits. Not a visual/performance gate."},"\t"))
	quit(1 if failed else 0)
