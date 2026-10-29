extends RefCounted

const FIRST_ORDER="rusanov_first_order_v1"
const MUSCL="muscl_mc_ssprk2_v1"
const DEFAULT_SOLVER=MUSCL
const DEFAULT_CFL:=0.2
const MIN_CFL:=0.05
const MAX_CFL:=0.5
const DEFAULT_MAX_ATTEMPTS:=64
const SELF="res://scripts/simulation/unified_edit/water_numerics.gd"

static func configuration_error(environment: Dictionary) -> StringName:
	if not environment.has("water_numerics"):return &""
	var value: Variant=environment.water_numerics
	if not value is Dictionary or not value.has("schema") or not value.has("solver_id"):return &"invalid_water_numerics"
	if typeof(value.schema)!=TYPE_INT or typeof(value.solver_id)!=TYPE_STRING:return &"invalid_water_numerics"
	if value.schema not in [1,2,3]:return &"unsupported_water_numerics_schema"
	if value.solver_id not in [FIRST_ORDER,MUSCL]:return &"unknown_water_solver_id"
	if value.schema==1:
		if value.size()!=2:return &"invalid_water_numerics"
	else:
		if value.size()!=(3 if value.schema==2 else 5) or not value.has("wave_retention"):return &"invalid_water_numerics"
		var amount: Variant=value.wave_retention
		if typeof(amount) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(amount)) or amount<0.0 or amount>1.0:return &"invalid_wave_retention"
		if value.solver_id!=MUSCL:return &"unsupported_wave_retention_solver"
		if value.schema==3:
			if not value.has("cfl") or not value.has("max_attempts"):return &"invalid_water_numerics"
			var coefficient: Variant=value.cfl
			if typeof(coefficient) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(coefficient)) or coefficient<MIN_CFL or coefficient>MAX_CFL:return &"invalid_muscl_cfl"
			if typeof(value.max_attempts)!=TYPE_INT or value.max_attempts<1 or value.max_attempts>DEFAULT_MAX_ATTEMPTS:return &"invalid_muscl_max_attempts"
	return &""

static func retention(environment: Dictionary) -> float:
	return float(environment.get("water_numerics",{}).get("wave_retention",0.0))

static func cfl(environment: Dictionary) -> float:
	return float(environment.get("water_numerics",{}).get("cfl",DEFAULT_CFL))

static func max_attempts(environment: Dictionary) -> int:
	return int(environment.get("water_numerics",{}).get("max_attempts",DEFAULT_MAX_ATTEMPTS))

static func selection(id: String, amount: float, coefficient: float=DEFAULT_CFL, attempts: int=DEFAULT_MAX_ATTEMPTS) -> Dictionary:
	if coefficient!=DEFAULT_CFL or attempts!=DEFAULT_MAX_ATTEMPTS:
		return {"schema":3,"solver_id":id,"wave_retention":amount,"cfl":coefficient,"max_attempts":attempts}
	return {"schema":1,"solver_id":id} if amount==0.0 else {"schema":2,"solver_id":id,"wave_retention":amount}

static func solver_id(environment: Dictionary) -> String:
	return String(environment.get("water_numerics",{"solver_id":FIRST_ORDER}).solver_id)

static func effective(environment: Dictionary) -> Dictionary:
	var error:=configuration_error(environment)
	if not error.is_empty():return {"error":error}
	var value:=environment.duplicate(true)
	if not value.has("water_numerics"):value.water_numerics={"schema":1,"solver_id":DEFAULT_SOLVER}
	return {"error":&"","value":value}
