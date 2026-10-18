extends SceneTree
const Config=preload("res://scripts/simulation/unified_edit/configuration.gd")
func _initialize() -> void:
	var first:={&"z":{&"resource_identity":1,"profile_hash":2},"a":3}
	var second:={"a":3,"z":{"profile_hash":2,"resource_identity":1}}
	var third:={&"a":3,&"z":{&"profile_hash":2,&"resource_identity":1}}
	var same: bool=Config.digest_data(first)==Config.digest_data(second) and Config.digest_data(second)==Config.digest_data(third)
	print("CONFIGURATION_STRING_KEY_ORDER ",same," hash ",Config.digest_data(first));quit(0 if same else 1)
