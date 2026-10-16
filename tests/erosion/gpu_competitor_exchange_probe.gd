extends SceneTree

# Fixed inputs isolate exchange from water acceleration and material relaxation.
const Domain = preload("res://scripts/simulation/sand_water_domain.gd")
const Solver = preload("res://scripts/simulation/gpu_shallow_solver.gd")
const Coupler = preload("res://scripts/simulation/erosion/gpu_sediment_coupler.gd")
const GRID := 32
const REFERENCE_STEP_S := 0.020716018974781036
const PATHS := ["shallow_edge_flux", "shallow_drain_scale", "shallow_update_state",
	"shallow_tide_boundary", "shallow_cfl_tiles", "shallow_gauge_depth",
	"shallow_audit_tiles", "shallow_tool_patch", "erosion/sediment_step",
	"erosion/copy_after_boundary"]
var output := "res://test_output/erosion_capacity_20261016/after.json"
var checks := []
var samples := {}
var spirvs: Array[RDShaderSPIRV] = []

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	call_deferred("_begin")

func _begin() -> void:
	RenderingServer.call_on_render_thread(_run)

func check(label: String, passed: bool, detail: Variant = null) -> void:
	checks.append({"name":label,"pass":passed,"detail":detail})

func sample(label: String, depth: float, velocity: Vector2, suspended := 0.0,
		wetness := 0.0, compaction := 0.0, steps := 1,
		delta_s := REFERENCE_STEP_S, cell_m := 0.125, sand_m := 0.3,
		outflow_m3_s := 0.0, sea := false) -> Dictionary:
	var domain := Domain.new(GRID, cell_m)
	domain.sand.fill(sand_m); domain.water.fill(depth)
	domain.sediment.fill(suspended); domain.wetness.fill(wetness)
	domain.compaction.fill(compaction)
	var qx := PackedFloat32Array(); qx.resize(GRID*GRID); qx.fill(velocity.x*depth)
	var qz := PackedFloat32Array(); qz.resize(GRID*GRID); qz.fill(velocity.y*depth)
	var solver := Solver.new()
	if not solver.initialize(RenderingServer.get_rendering_device(), domain,
			spirvs[0],spirvs[1],spirvs[2],spirvs[3],spirvs[4],spirvs[5],spirvs[6],spirvs[7],qx,qz):
		check(label+"_solver",false); return {}
	var flux := PackedFloat32Array(); flux.resize(GRID*GRID*4)
	for i in GRID*GRID: flux[i*4+1] = outflow_m3_s
	var held_textures: Array[RID] = []
	for index in 2:
		for field in ["water","momentum_x","momentum_z","flux"]:
			var values: PackedFloat32Array = domain.water if field=="water" else qx if field=="momentum_x" else qz if field=="momentum_z" else flux
			held_textures.append(solver.textures[field][index])
			var format_id := RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT if field=="flux" else RenderingDevice.DATA_FORMAT_R32_SFLOAT
			solver.textures[field][index] = solver._create_texture(format_id,values.to_byte_array())
	solver.prescribed_tide_boundary = sea
	var coupler := Coupler.new()
	if not coupler.initialize(solver,spirvs[8],spirvs[9]):
		check(label+"_coupler",false); solver.release(); return {}
	coupler.observe_pushes = true
	for step in steps:
		if step>0: solver.current_index = 1-solver.current_index
		check(label+"_dispatch_"+str(step),coupler.dispatch_after_water_substep(delta_s))
	var sand := solver.rd.texture_get_data(solver.current_texture("sand"),0).to_float32_array()
	var sediment := solver.rd.texture_get_data(solver.current_texture("sediment"),0).to_float32_array()
	var total := 0.0; var minimum := INF; var invalid := 0
	for i in GRID*GRID:
		total += float(sand[i])+float(sediment[i])
		minimum = minf(minimum,minf(sand[i],sediment[i]))
		if not is_finite(sand[i]) or not is_finite(sediment[i]): invalid+=1
	var middle := GRID/2*GRID+GRID/2
	var result := {"eroded_m":sand_m-float(sand[middle]),"suspended_m":float(sediment[middle]),
		"edge_eroded_m":sand_m-float(sand[GRID/2*GRID]),
		"mass_error_m3":absf(total-GRID*GRID*(sand_m+suspended))*cell_m*cell_m,
		"minimum_m":minimum,"invalid":invalid,"bound_pushes":coupler.bound_pushes.duplicate(true)}
	check(label+"_conserved_nonnegative",result.mass_error_m3<0.00001 and minimum>=0.0 and invalid==0,result)
	samples[label] = result
	var rd := solver.rd
	coupler.release(); solver.release()
	for rid in held_textures: rd.free_rid(rid)
	return result

func _run() -> void:
	for name in PATHS:
		var file: RDShaderFile = load("res://shaders/simulation/"+name+".glsl")
		if file==null or not file.get_spirv().get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE).is_empty():
			check("shader_"+name,false); call_deferred("_finish"); return
		spirvs.append(file.get_spirv())
	var still := sample("still_with_numerical_flux",0.2,Vector2.ZERO,0.0,0.0,0.0,1,REFERENCE_STEP_S,0.125,0.3,0.005)
	check("zero_velocity_does_not_erode",absf(still.eroded_m)<0.0000001,still)
	var base := sample("moving",0.2,Vector2(0.5,0),0.0,0.0,0.0,1,REFERENCE_STEP_S,0.125,0.3,0.0125)
	check("captured_exchange_fraction",absf(base.eroded_m-0.003*0.5*0.015)<0.0000001,base)
	var deep := sample("deep",0.8,Vector2(0.5,0),0.0,0.0,0.0,1,REFERENCE_STEP_S,0.125,0.3,0.05)
	check("depth_weight_saturates",absf(base.eroded_m-deep.eroded_m)<0.0000001,deep)
	var thin := sample("thin",1.0/60.0,Vector2(0.5,0))
	check("thin_water_half_capacity",absf(thin.eroded_m-base.eroded_m*0.5)<0.0000001,thin)
	var diagonal := sample("diagonal",0.2,Vector2(0.3,0.4))
	check("speed_uses_vector_length",absf(diagonal.eroded_m-base.eroded_m)<0.0000001,diagonal)
	var coarse := sample("coarse_grid",0.2,Vector2(0.5,0),0.0,0.0,0.0,1,REFERENCE_STEP_S,0.25,0.3,0.025)
	check("capacity_independent_of_grid",absf(coarse.eroded_m-base.eroded_m)<0.0000001,coarse)
	var compact := sample("wet_compact",0.2,Vector2(0.5,0),0.0,1.0,1.0)
	check("exchange_has_no_material_strength",absf(compact.eroded_m-base.eroded_m)<0.0000001,compact)
	var loaded := sample("overloaded",0.2,Vector2(0.5,0),0.01)
	check("loaded_water_deposits",loaded.eroded_m<0.0 and absf(loaded.suspended_m-(0.01-(0.01-0.0015)*0.005))<0.0000001,loaded)
	var dry := sample("dry",0.0,Vector2.ZERO,0.01)
	check("dry_settles_gradually",absf(dry.suspended_m-0.00995)<0.0000001 and dry.eroded_m<0.0,dry)
	var split := sample("dry_split",0.0,Vector2.ZERO,0.01,0.0,0.0,2,REFERENCE_STEP_S/2.0)
	check("exchange_time_partition",absf(split.suspended_m-dry.suspended_m)<0.0000001,split)
	var tiny := sample("limited_bed",0.2,Vector2(2,0),0.0,0.0,0.0,1,1.0,0.125,0.000001)
	check("erosion_limited_by_sand_stock",tiny.minimum_m>=0.0 and tiny.eroded_m<=0.00000101,tiny)
	var sea := sample("sea_reservoir",0.2,Vector2(0.5,0),0.0,0.0,0.0,1,REFERENCE_STEP_S,0.125,0.3,0.0,true)
	check("protection_only_at_actual_reservoir",absf(sea.edge_eroded_m)<0.0000001 and sea.eroded_m>0.0,sea)
	call_deferred("_finish")

func _finish() -> void:
	var passed := true
	for row in checks: passed = passed and row.pass
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var sources := {}
	for path in ["res://shaders/simulation/erosion/sediment_step.glsl","res://scripts/simulation/erosion/gpu_sediment_coupler.gd"]:
		sources[path] = FileAccess.get_sha256(path)
	var compiled := []
	for code in spirvs:
		var hash := HashingContext.new(); hash.start(HashingContext.HASH_SHA256)
		hash.update(code.get_stage_bytecode(RenderingDevice.SHADER_STAGE_COMPUTE))
		compiled.append(hash.finish().hex_encode())
	var file := FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":passed,"checks":checks,"samples":samples,"sources":sources,
		"compiled_shader_sha256":compiled,"engine":OS.get_executable_path(),"version":Engine.get_version_info(),"reference_step_s":REFERENCE_STEP_S},"\t"))
	print("COMPETITOR_EXCHANGE_COMPLETE ",passed," checks=",checks.size()," output=",output)
	for frame in 3: await process_frame
	quit(0 if passed else 1)
