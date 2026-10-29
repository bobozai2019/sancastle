extends SceneTree

# T02-only numerical probe: State, Transport, Water and Coupled on the real
# main RD. No editor, publication, Views, checkpoint or presentation assertion.
const State=preload("res://scripts/simulation/unified_edit/state.gd")
const Transport=preload("res://scripts/simulation/unified_edit/transport.gd")
const Water=preload("res://scripts/simulation/unified_edit/water.gd")
const Coupled=preload("res://scripts/simulation/unified_edit/coupled.gd")
const Domain=preload("res://scripts/simulation/sand_water_domain.gd")
var output:=""
var done:=false
var selected_case:=""
var failed:=false
var checks: Array=[]
var observations: Array=[]
var archive:=ZIPPacker.new()

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		if arg.begins_with("--case="):selected_case=arg.trim_prefix("--case=")
	call_deferred("run")

func check(label: String, passed: bool) -> void:
	checks.append({"name":label,"pass":passed});failed=failed or not passed
	if not passed:print("CORE_LOCAL_FAIL ",label)

func capture(state, water, coupled, transport, case_id: String, tick: int) -> void:
	var raw:={}
	for name in state.textures:
		var value=state.textures[name]
		if value is Array:
			for slot in value.size():raw[name+"_"+str(slot)]=state.rd.texture_get_data(value[slot],0)
		else:raw[name]=state.rd.texture_get_data(value,0)
	raw.decision=state.rd.buffer_get_data(water.decision);raw.control=state.rd.buffer_get_data(transport.control)
	raw.accepted_indirect=state.rd.buffer_get_data(water.indirect)
	if water.muscl!=null:
		for name in water.muscl.buffers:raw["muscl_"+name]=state.rd.buffer_get_data(water.muscl.buffers[name])
	for name in coupled.buffers:raw["coupled_"+name]=state.rd.buffer_get_data(coupled.buffers[name])
	if coupled.images.has("dirty"):raw.coupled_dirty=state.rd.texture_get_data(coupled.images.dirty,0)
	for name in raw:
		check("zip_start",archive.start_file(case_id+"/%02d/"%tick+name+".bin")==OK)
		check("zip_write",archive.write_file(raw[name])==OK);check("zip_close",archive.close_file()==OK)
	var d: PackedByteArray=raw.decision
	observations.append({"case":case_id,"capture":tick,"status":d.decode_u32(16),"accepted":d.decode_u32(4),"rejected":d.decode_u32(40)})
	if tick>0:check(case_id+"_advanced",d.decode_u32(4)>0 and d.decode_u32(16)!=2)

func render_run() -> void:
	check("zip_open",archive.open(output.path_join("states.zip"))==OK)
	var cases: Array=["still","coupled","dry","obstacle","retry","first_order"]
	if selected_case=="supplemental":cases=["boundary","invalid_qx_size","invalid_qz_size","invalid_qx_value","invalid_water"]
	for case_id in cases:
		var state:=State.new();var transport:=Transport.new();var water:=Water.new();var coupled:=Coupled.new()
		var domain:=Domain.new(256,0.125);domain.domain_id=&"main_beach";domain.generation=1;domain.sand.fill(0.4);domain.water.fill(0.1)
		var qx:=PackedFloat32Array();var qz:=PackedFloat32Array();qx.resize(65536);qz.resize(65536);qx.fill(0.015);qz.fill(-0.009)
		if case_id=="dry":domain.water.fill(0.0);qx.fill(0.0);qz.fill(0.0)
		if case_id=="obstacle":
			for z in 256:domain.obstacle[z*256+128]=1.0
		if case_id=="retry":
			for z in 256:
				for x in 256:domain.sand[z*256+x]=0.4+float(x)*2.0
			domain.water.fill(0.005);qx.fill(0.0);qz.fill(0.0)
		domain.set_meta("edit_validation_initial_qx",qx);domain.set_meta("edit_validation_initial_qz",qz)
		var expected_error:=""
		if case_id in ["invalid_qx_size","invalid_qz_size"]:
			domain.set_meta("edit_validation_initial_qx" if case_id=="invalid_qx_size" else "edit_validation_initial_qz",PackedFloat32Array([0.0]));expected_error="initial_momentum_size"
		if case_id=="invalid_qx_value":
			qx[0]=NAN;domain.set_meta("edit_validation_initial_qx",qx);expected_error="initial_momentum_value"
		if case_id=="invalid_water":domain.water[0]=-0.1;expected_error="initial_field_value"
		state.water_solver_id="rusanov_first_order_v1" if case_id=="first_order" else "muscl_mc_ssprk2_v1"
		state.wave_retention=1.0;state.cohesion_yield_height_m=2.0
		var ok:=transport.initialize(RenderingServer.get_rendering_device(),"main_beach",1)
		check(case_id+"_transport",ok)
		if ok:
			ok=state.initialize(transport.rd,domain,transport)
			if expected_error.is_empty():check(case_id+"_state:"+state.last_error,ok)
			else:
				check(case_id+"_rejected",not ok and state.last_error==expected_error)
				observations.append({"case":case_id,"capture":0,"expected_error":expected_error,"actual_error":state.last_error})
		if ok:ok=water.initialize(state);check(case_id+"_water:"+water.last_error,ok)
		if ok and case_id=="boundary":
			check("boundary_nonfinite_rejected",not water.configure_boundary(Vector3(NAN,0.1,0.35),[]))
			check("boundary_invalid_wave_rejected",not water.configure_boundary(Vector3(0.5,0.1,0.35),[Vector4(0.0,0.0,0.1,1.0)]))
			ok=water.configure_boundary(Vector3(0.5,0.1,0.35),[Vector4(0.0,3.0,0.1,1.0)])
			check("boundary_valid_config",ok)
		if ok and case_id in ["coupled","first_order"]:
			ok=coupled.initialize(state,water,{"cohesion_yield_height_m":0.9,"saturation_tagged_depth_m":0.125});check(case_id+"_coupled:"+coupled.last_error,ok)
		if ok:
			capture(state,water,coupled,transport,case_id,0)
			for tick in 3:
				water.record_tick(RID(),RID(),RID(),0,1.0/30.0)
				capture(state,water,coupled,transport,case_id,tick+1)
		water.release();coupled.release();state.release();transport.release()
		check(case_id+"_released",state.owned.is_empty() and water.owned.is_empty() and coupled.owned.is_empty() and transport.owned.is_empty())
		if failed:break
	check("zip_finish",archive.close()==OK)
	FileAccess.open(output.path_join("variant.json"),FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"checks":checks,"observations":observations,"injections":[],"scope":"Direct main-RD authority/water/coupling local probe only. No Views, editing, checkpoint, normal scene or cost assertion."},"\t"))
	call_deferred("finished")

func finished() -> void:done=true

func run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	RenderingServer.call_on_render_thread(render_run)
	while not done:await process_frame
	quit(1 if failed else 0)
