extends "res://tests/integration/unified_edit_extension_probe.gd"

var feature_case:=""
var selected_water:=0
var selected_material:=0

func _run() -> void:
	feature_case=probe_case
	var parts:=feature_case.split("_")
	selected_water=int(parts[1]);selected_material=int(parts[2])
	probe_case=parts[0]+"_new"
	await super._run()

func _command(id: int, profile: Dictionary) -> Dictionary:
	observations.full_configuration=pipeline._configuration.duplicate(true)
	var bytes:=var_to_bytes(Config.canonical(pipeline._configuration))
	var path:=output.get_base_dir()+"/configuration.variant"
	FileAccess.open(path,FileAccess.WRITE).store_buffer(bytes)
	observations.configuration_bytes={"path":path,"sha256":FileAccess.get_sha256(path)}
	var value:=super._command(id,profile)
	value.features={"water_policy":selected_water,"material_policy":selected_material}
	if selected_water!=3:value.parameters.speed_m_s=0.0
	# Independent legal numeric variation inside each immutable resource range.
	match profile.operation:
		L.Profile.Operation.VOLUME_DELTA:value.parameters.amount_m3=0.2;value.parameters.radius_m=1.25
		L.Profile.Operation.TARGET_HEIGHT:value.parameters.height_m=0.95;value.parameters.scale_xz=1.25;value.parameters.yaw_rad=0.5
		L.Profile.Operation.TRANSFER:value.parameters.depth_m=0.2;value.parameters.trench_width_m=0.7;value.parameters.shoulder_width_m=1.0
	var bad:=value.duplicate(true);bad.features.material_policy=99
	check("unadvertised_material_rejected",not Intent.freeze(registry,bad,"main_beach",9007199254740993).error.is_empty())
	for key in profile.ranges:
		bad=value.duplicate(true);bad.parameters[key]=float(profile.ranges[key][1])+1.0
		check("out_of_range_rejected_"+key,not Intent.freeze(registry,bad,"main_beach",9007199254740993).error.is_empty())
	if selected_water!=3:
		bad=value.duplicate(true);bad.parameters.speed_m_s=0.5
		check("speed_requires_velocity_policy",not Intent.freeze(registry,bad,"main_beach",9007199254740993).error.is_empty())
	return value

func finish() -> void:
	observations.feature_case=feature_case
	observations.selected_features={"water_policy":selected_water,"material_policy":selected_material}
	probe_case=feature_case
	super.finish()
