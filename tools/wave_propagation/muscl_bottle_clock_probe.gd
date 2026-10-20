extends "res://tests/floating_props/bottle_clock_probe.gd"
func _environment() -> Dictionary:
	return {"engine":Engine.get_version_info().string,"probe":probe_case,"water_numerics":{"schema":1,"solver_id":"muscl_mc_ssprk2_v1"}}
func _extra_sources() -> PackedStringArray:
	return PackedStringArray([get_script().resource_path,"res://tests/floating_props/bottle_clock_probe.gd"])
func _configure_domain(domain) -> void:
	var qx: PackedFloat32Array=domain.get_meta("edit_validation_initial_qx").duplicate()
	for z in 256:
		for x in 256:
			var px:=(float(x)+.5-128)*.125;var pz:=(float(z)+.5-128)*.125;var i:=z*256+x
			var eta:=.001*sin(PI*px)*exp(-pz*pz/16.0)
			domain.water[i]+=eta;qx[i]+=sqrt(9.81*.8)*eta
	domain.set_meta("edit_validation_initial_qx",qx)
func _extra_final_checks() -> void:
	check("actual_muscl_bottle_domain",runtime.current.water.muscl!=null and runtime.current.state.water_solver_id=="muscl_mc_ssprk2_v1")
	var low:=INF;var high:=-INF;var forces:=0;var max_age:=0.0
	for row in service.events:
		if row.kind==&"point_force":low=minf(low,row.data.sample_eta);high=maxf(high,row.data.sample_eta);forces+=1
		elif row.kind==&"admit":max_age=maxf(max_age,row.data.force_age_s)
	check("wave_eta_reaches_real_force_samples",forces>0 and high-low>0.00001)
	check("sample_age_budget_preserved",max_age<=0.15+1e-6)
	observations.wave_samples={"minimum_eta_m":low,"maximum_eta_m":high,"force_records":forces,"maximum_force_sample_age_s":max_age,"initial_amplitude_m":.001,"initial_wavelength_m":2.0,"scope":"Sample and force clock integration; paired shovel-response experience remains G5"}
