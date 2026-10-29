extends SceneTree

const Domain = preload("res://scripts/simulation/sand_water_domain.gd")
const Queue = preload("res://scripts/sand/tool_command_queue.gd")
const Scheduler = preload("res://scripts/simulation/edit_validation/gpu_edit_scheduler.gd")

class AdmissionFixture extends Node3D:
	var generation := 1
	var closed := false
	var ready_for_ticks := true
	var last_error := ""
	var water_policy := 3
	var signed_speed_m_s := 0.25
	var unrestricted_sand_tools := false
	var domain
	var command_queue
	func _init() -> void:
		domain = Domain.new(64, 0.125)
		domain.tool_inventory_m3 = 0.10
		command_queue = Queue.new(domain)
	func shutdown() -> void:
		closed = true

var checks := []
var output := ""

func check(name: String, passed: bool, detail: Variant = null) -> void:
	checks.append({"name": name, "pass": passed, "detail": detail})

func command(id: int, kind: StringName = &"place_sand", amount: float = 0.04) -> Dictionary:
	return {"domain_id": &"main_beach", "generation": 1, "sim_tick": 0, "command_id": id, "kind": kind, "shape": &"circle", "transform": {"position_m": Vector3.ZERO}, "radius_m": 0.3, "strength": 1.0, "amount_m3": amount, "seed": 101}

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	call_deferred("run")

func run() -> void:
	var lab := AdmissionFixture.new()
	var scheduler = Scheduler.new(lab)
	var sand: PackedByteArray = lab.domain.sand.to_byte_array()
	check("two_inventory_reservations", scheduler.submit(command(1)).is_empty() and scheduler.submit(command(2)).is_empty() and is_equal_approx(scheduler.reserved_total(), 0.08))
	var rejected: StringName = scheduler.submit(command(3, &"place_sand", 0.03))
	check("reservation_overdraw_atomic", rejected == &"insufficient_inventory" and lab.command_queue.last_command_id == 2 and lab.command_queue.pending.size() == 2 and is_equal_approx(scheduler.reserved_total(), 0.08), String(rejected))
	check("dig_requires_no_inventory_reservation", scheduler.submit(command(3, &"remove_sand", 0.5)).is_empty() and is_equal_approx(scheduler.reserved_total(), 0.08))
	check("duplicate_command_id_rejected", scheduler.submit(command(3)) == &"invalid_command" and lab.command_queue.pending.size() == 3)
	check("new_kind_cannot_fall_through_old_protocol", scheduler.submit(command(4, &"shovel_transfer")) == &"invalid_command" and lab.command_queue.last_command_id == 3)
	var old := command(4)
	old.generation = 0
	check("old_generation_rejected", scheduler.submit(old) == &"inactive_generation")
	var invalid := command(4)
	invalid.radius_m = NAN
	check("gpu_admission_rejects_nan", scheduler.submit(invalid) == &"invalid_command")
	check("admission_does_not_edit_or_settle", lab.domain.sand.to_byte_array() == sand and lab.domain.tool_inventory_m3 == 0.10 and lab.domain.sand_source_m3 == 0.0 and lab.domain.sand_sink_m3 == 0.0)
	scheduler.cancel_pending("contract_test")
	check("cancel_releases_reservations", scheduler.reserved_total() == 0.0 and lab.command_queue.pending.is_empty())
	lab.free()
	lab = AdmissionFixture.new()
	lab.unrestricted_sand_tools = true
	lab.domain.tool_inventory_m3 = 0.0
	scheduler = Scheduler.new(lab)
	var bounded := true
	for id in range(1, 65): bounded = bounded and scheduler.submit(command(id, &"place_sand", 1.0)).is_empty()
	check("external_64_pending_without_inventory", bounded and lab.command_queue.pending.size() == 64 and scheduler.reserved_total() == 0.0)
	check("shared_queue_bound", scheduler.submit(command(65)) == &"backend_unavailable" and lab.command_queue.pending.size() == 64 and lab.command_queue.last_command_id == 64)
	await scheduler.close()
	check("closed_queue_cancelled", lab.command_queue.pending.is_empty() and scheduler.submit(command(65)) == &"backend_unavailable")
	lab.free()
	var passed := true
	for row in checks: passed = passed and row.pass
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		var file := FileAccess.open(output.path_join("legacy_inventory.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify({"pass": passed, "checks": checks, "scope": "real scheduler CPU admission only; GPU receipt regression belongs to G2/G9"}, "\t")); file.close()
	print("LEGACY_INVENTORY_CONTRACT ", passed)
	quit(0 if passed else 1)
