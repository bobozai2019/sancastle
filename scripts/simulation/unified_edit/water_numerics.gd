extends RefCounted

const FIRST_ORDER="rusanov_first_order_v1"
const MUSCL="muscl_mc_ssprk2_v1"
const DEFAULT_SOLVER=FIRST_ORDER
const SELF="res://scripts/simulation/unified_edit/water_numerics.gd"

static func configuration_error(environment: Dictionary) -> StringName:
	if not environment.has("water_numerics"):return &""
	var value: Variant=environment.water_numerics
	if not value is Dictionary or value.size()!=2 or not value.has("schema") or not value.has("solver_id"):return &"invalid_water_numerics"
	if typeof(value.schema)!=TYPE_INT or typeof(value.solver_id)!=TYPE_STRING:return &"invalid_water_numerics"
	if value.schema!=1:return &"unsupported_water_numerics_schema"
	if value.solver_id not in [FIRST_ORDER,MUSCL]:return &"unknown_water_solver_id"
	return &""

static func solver_id(environment: Dictionary) -> String:
	return String(environment.get("water_numerics",{"solver_id":FIRST_ORDER}).solver_id)

static func effective(environment: Dictionary) -> Dictionary:
	var error:=configuration_error(environment)
	if not error.is_empty():return {"error":error}
	var value:=environment.duplicate(true)
	if not value.has("water_numerics"):value.water_numerics={"schema":1,"solver_id":DEFAULT_SOLVER}
	return {"error":&"","value":value}
