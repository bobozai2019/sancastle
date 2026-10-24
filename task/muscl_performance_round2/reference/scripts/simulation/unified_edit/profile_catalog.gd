extends Resource

const Registry=preload("res://scripts/simulation/unified_edit/profile_registry.gd")
@export var profiles: Array[Resource]=[]

func instantiate_registry() -> Dictionary:
	if get_script()!=load("res://scripts/simulation/unified_edit/profile_catalog.gd"):return {"error":&"invalid_catalog_type"}
	var registry:=Registry.new()
	var error:=registry.initialize(profiles)
	return {"error":error,"registry":registry if error.is_empty() else null}
