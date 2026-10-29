class_name SandcastleAuditRecorder
extends RefCounted

## Append-only CPU reference ledger. It observes the domain and never changes it.

const HEADER := "sim_tick,command_id,kind,shape,status,requested_m3,tool_delta_m3,terrain_and_sediment_m3,bucket_m3,source_m3,sink_m3,total_m3,expected_m3,error_pct,error_code"

var initial_total_m3: float
var rows: PackedStringArray = PackedStringArray()


func _init(domain: SandWaterDomain) -> void:
	initial_total_m3 = domain.total_sand_m3()
	rows.append(HEADER)


func record_tool(command: Dictionary, result: Dictionary, domain: SandWaterDomain) -> void:
	var expected := initial_total_m3 + domain.sand_source_m3 - domain.sand_sink_m3
	var actual := domain.total_sand_m3()
	var error_pct := absf(actual - expected) / maxf(absf(expected), 0.000001) * 100.0
	rows.append("%d,%d,%s,%s,%s,%.9f,%.9f,%.9f,%.9f,%.9f,%.9f,%.9f,%.9f,%.9f,%s" % [
		domain.sim_tick, int(command.get("command_id", -1)),
		String(command.get("kind", &"")), String(command.get("shape", &"circle")),
		String(result.get("status", &"rejected")), float(command.get("amount_m3", 0.0)),
		float(result.get("sand_delta_m3", 0.0)), domain.total_sand_m3(false),
		domain.tool_inventory_m3, domain.sand_source_m3, domain.sand_sink_m3,
		actual, expected, error_pct, String(result.get("error_code", &""))])


func save_csv(path: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string("\n".join(rows) + "\n")
	file.close()
	return OK
