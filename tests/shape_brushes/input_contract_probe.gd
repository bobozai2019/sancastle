extends SceneTree

const Spec = preload("res://scripts/sand/brushes/brush_spec.gd")
const Registry = preload("res://scripts/sand/brushes/brush_registry.gd")
const Stroke = preload("res://scripts/sand/brushes/stroke_controller.gd")
const BrushProtocol = preload("res://scripts/simulation/brushes/brush_protocol.gd")
var checks := []
var output := ""
var trajectories := {}

func check(name: String, ok: bool, detail: Variant = null) -> void:
	checks.append({"name": name, "pass": ok, "detail": detail})
	print("BRUSH_INPUT_CHECK ", name, " ", ok)

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	call_deferred("run")

func drain(controller) -> Array:
	var result := []
	var frame := 0
	var identity := 1
	while controller.buffer_points() > 0:
		controller.begin_frame(frame)
		var emitted := 0
		while true:
			var segment: Dictionary = controller.peek_segment()
			if segment.is_empty(): break
			result.append(segment.duplicate(true))
			controller.acknowledge_admission(segment, identity)
			controller.settle_command(identity, controller.generation)
			identity += 1; emitted += 1
		check("frame_submission_bound", emitted <= 8)
		frame += 1
	return result

func trajectory(hz: int) -> Array:
	var controller = Stroke.new()
	var path := [Vector2.ZERO, Vector2(3,0), Vector2(3,2), Vector2(1,2)]
	check("begin_%d" % hz, controller.begin_stroke(&"wall_v1", {"height_m":0.3,"bottom_width_m":1.0,"top_width_m":0.5}, path[0], 1, 1).is_empty())
	var accepted := true
	for leg in range(1, path.size()):
		for sample in range(1, hz + 1): accepted = accepted and controller.append_path_sample(path[leg-1].lerp(path[leg], float(sample)/hz)).is_empty()
	controller.end_stroke()
	var result := drain(controller)
	var length := 0.0
	var correct := accepted
	for segment in result:
		var a: Vector2 = segment.start_xz_m
		var b: Vector2 = segment.end_xz_m
		length += a.distance_to(b)
		correct = correct and a.distance_to(b) <= 2.0 + 0.00001
		# Every emitted segment belongs to exactly one analytic leg.
		correct = correct and ((absf(a.y)<1e-5 and absf(b.y)<1e-5) or (absf(a.x-3.0)<1e-5 and absf(b.x-3.0)<1e-5) or (absf(a.y-2.0)<1e-5 and absf(b.y-2.0)<1e-5))
	check("analytic_polyline_%d" % hz, correct and absf(length-7.0)<0.00005 and controller.state==&"settled", {"length":length,"commands":result.size(),"buffer_peak":controller.peak_buffer_points})
	return result

func shovel_samples(streaming:bool) -> Array:
	var controller=Stroke.new()
	controller.begin_stroke(&"shovel_v1",{"trench_width_m":0.5,"depth_m":0.15,"shoulder_width_m":0.5},Vector2.ZERO,7,1)
	var result:=[]
	for i in range(1,41):
		controller.append_path_sample(Vector2(float(i)*0.05,0))
		if streaming:result.append_array(drain(controller))
	controller.end_stroke();result.append_array(drain(controller))
	return result

func run() -> void:
	var frozen:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/shape_brushes/contract_v1.json"))
	var current:=Spec.specification()
	check("castle_fixed_target_policy",current.brushes.castle_v1.placement_policy=="fixed_world_target_max_existing_v1" and current.brushes.castle_v1.placement_datum_y_m==0.0 and current.brushes.castle_v1.placement_relief_m==0.0 and Spec.budget(&"castle_v1",current.brushes.castle_v1.default,0)==48.0)
	current.brushes.castle_v1.erase("placement_policy");current.brushes.castle_v1.erase("placement_datum_y_m")
	current.brushes.castle_v1.placement_relief_m=frozen.brushes.castle_v1.placement_relief_m
	current.budget_formulas.castle_v1=frozen.budget_formulas.castle_v1
	check("runtime_other_spec_matches_frozen",current==frozen)
	var registry = Registry.new()
	for id in [&"castle_v1",&"wall_v1",&"shovel_v1"]:
		var definition = registry.definition(id)
		check("definition_"+String(id), definition != null and definition.validate_definition().is_empty() and definition.definition_hash().length()==64)
	check("unknown_resource_rejected", registry.definition(&"place_sand")==null)
	var params := {"height_m":0.3,"bottom_width_m":1.0,"top_width_m":0.5}
	var protected = Stroke.new()
	var original_params := params.duplicate(true)
	protected.begin_stroke(&"wall_v1",original_params,Vector2.ZERO,1,1)
	original_params.height_m = 0.6
	var returned_params: Dictionary = protected.params
	returned_params.height_m = 0.15
	check("stroke_parameter_snapshot_is_immutable",protected.params.height_m==0.3)
	var external_spec := Spec.specification()
	external_spec.brushes.wall_v1.max_add_m3 = 1000.0
	check("specification_cannot_be_mutated_by_consumer",Spec.specification().brushes.wall_v1.max_add_m3==8.0)
	var command := BrushProtocol.make_command(&"wall_v1",params,Vector2.ZERO,Vector2(1,0),&"main_beach",1,9007199254740993,4294967297,0,2,4294967298)
	check("valid_request", BrushProtocol.command_error(command).is_empty())
	var wire := BrushProtocol.encode(command,4294967299,4294967300)
	check("exact_wire_identities", wire.size()==256 and wire.decode_s64(24)==9007199254740993 and wire.decode_s64(32)==4294967297 and wire.decode_s64(64)==4294967298 and wire.decode_s64(56)==4294967300)
	check("wire_budget_not_rounded_up", wire.size()==256 and wire.decode_float(152)<=command.add_budget_m3)
	for field in ["height_m","add_budget_m3","speed_m_s"]:
		var bad := command.duplicate(true); bad[field]=NAN
		check("nonfinite_"+field, not BrushProtocol.command_error(bad).is_empty())
	var bad := command.duplicate(true); bad.schema_version=99
	check("unknown_version", BrushProtocol.command_error(bad)==&"unsupported_brush_version")
	bad=command.duplicate(true); bad.amount_m3=1.0
	check("unknown_field", BrushProtocol.command_error(bad)==&"invalid_command")
	bad=command.duplicate(true); bad.definition_hash="0".repeat(64)
	check("hash_mismatch", BrushProtocol.command_error(bad)==&"template_mismatch")
	bad=command.duplicate(true); bad.add_budget_m3=100.0
	check("permission_not_inflated", BrushProtocol.command_error(bad)==&"budget_exceeded")
	bad=command.duplicate(true); bad.start_xz_m=Vector2(15.75,0); bad.end_xz_m=bad.start_xz_m
	check("whole_footprint_boundary", BrushProtocol.command_error(bad)==&"out_of_domain")
	bad=command.duplicate(true); bad.brush_id=123
	check("brush_id_type", BrushProtocol.command_error(bad)==&"invalid_command")
	var shovel := BrushProtocol.make_command(&"shovel_v1",{"trench_width_m":0.5,"depth_m":0.15,"shoulder_width_m":0.5},Vector2.ZERO,Vector2(1,0),&"main_beach",1,2,1,0,0,1)
	check("shovel_internal_permission", BrushProtocol.command_error(shovel).is_empty() and shovel.add_budget_m3==0.0 and shovel.transfer_budget_m3>0.0)
	shovel.add_budget_m3=0.001
	check("shovel_external_permission_refused", BrushProtocol.command_error(shovel)==&"budget_exceeded")
	var receipt := PackedByteArray(); receipt.resize(256); receipt.fill(0)
	receipt.encode_u32(0,BrushProtocol.RECEIPT_MAGIC); receipt.encode_u32(4,2); receipt.encode_u32(8,256); receipt.encode_u32(12,2)
	for field in [[16,4294967299],[24,command.command_id],[32,command.stroke_id],[40,1],[48,4294967300],[56,4294967300],[64,2],[72,command.baseline_token]]: receipt.encode_s64(field[0],field[1])
	var decoded := BrushProtocol.decode_receipt(receipt)
	check("no_change_receipt_identity", BrushProtocol.receipt_matches(decoded,command,4294967299,4294967300))
	receipt.encode_float(128,0.1)
	check("no_change_cannot_settle_mass", not BrushProtocol.decode_receipt(receipt).ok)
	receipt.encode_float(128,0.0); receipt.encode_u32(252,1)
	check("reserved_receipt_refused", not BrushProtocol.decode_receipt(receipt).ok)
	for hz in [30,60,240]: trajectories[str(hz)]=trajectory(hz)
	var controller = Stroke.new()
	controller.begin_stroke(&"wall_v1",params,Vector2.ZERO,1,1)
	for i in 300: controller.append_path_sample(Vector2.ZERO)
	check("stationary_no_segments",controller.buffer_points()==0)
	controller.append_path_sample(Vector2(1,0)); controller.append_path_sample(Vector2(5,0),false); controller.append_path_sample(Vector2(6,0)); controller.append_path_sample(Vector2(7,0)); controller.end_stroke()
	var segments := drain(controller)
	check("invalid_region_is_not_bridged",segments.size()==2 and segments[0].end_xz_m.distance_to(Vector2(1,0))<1e-5 and segments[1].start_xz_m==Vector2(6,0))
	controller=Stroke.new(); controller.begin_stroke(&"castle_v1",{"scale_xz":1.0,"height_m":0.7,"yaw_rad":0.0},Vector2.ZERO,2,1)
	for i in 300: controller.append_path_sample(Vector2(i*0.01,0))
	controller.end_stroke(); segments=drain(controller)
	check("castle_once_on_press",segments.size()==1 and segments[0].start_xz_m==segments[0].end_xz_m)
	controller=Stroke.new(); controller.begin_stroke(&"wall_v1",params,Vector2.ZERO,3,1)
	controller.append_path_sample(Vector2(1,0)); controller.begin_frame(1)
	var segment: Dictionary=controller.peek_segment()
	controller.acknowledge_admission(segment,101); controller.end_stroke(false)
	controller.settle_command(101,0)
	check("old_generation_cannot_finish_stroke",controller.state==&"draining" and controller.outstanding==1)
	controller.settle_command(101,1); controller.settle_command(101,1)
	check("cancel_and_duplicate_settlement",controller.state==&"settled" and controller.outstanding==0 and controller.buffer_points()==0)
	controller=Stroke.new(); controller.begin_stroke(&"wall_v1",params,Vector2.ZERO,4,1)
	var overflow: StringName=&""
	for i in 40:
		var error: StringName=controller.append_path_sample(Vector2(1 if i%2==0 else 0,0))
		if not error.is_empty(): overflow=error; break
	check("bounded_buffer_rejects_overflow",overflow==&"stroke_buffer_full" and controller.buffer_points()<=256 and controller.state in [&"draining",&"settled"],controller.peak_buffer_points)
	var batched:=shovel_samples(false);var streamed:=shovel_samples(true)
	var same:bool=batched.size()==16 and streamed.size()==16
	for i in mini(batched.size(),streamed.size()):
		var a:Vector2=batched[i].start_xz_m;var b:Vector2=batched[i].end_xz_m
		same=same and a.distance_to(Vector2(float(i)*0.125,0))<1e-5 and b.distance_to(Vector2(float(i+1)*0.125,0))<1e-5 and batched[i].take_count==1 and streamed[i].take_count==1 and a.distance_to(streamed[i].start_xz_m)<1e-5 and b.distance_to(streamed[i].end_xz_m)<1e-5
	check("shovel_fixed_samples_ignore_submission_timing",same,{"batched":batched.size(),"streaming":streamed.size()})
	var passed := true
	for row in checks: passed=passed and row.pass
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		var file := FileAccess.open(output.path_join("input_result.json"),FileAccess.WRITE)
		file.store_string(JSON.stringify({"pass":passed,"checks":checks,"trajectories":trajectories,"scope":"CPU resource/path/protocol; GPU framework follows separately"},"\t")); file.close()
	print("BRUSH_INPUT_COMPLETE ",passed)
	quit(0 if passed else 1)
