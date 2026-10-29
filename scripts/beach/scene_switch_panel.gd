extends VBoxContainer

const Routes=preload("res://scripts/beach/unified_scene_routes.gd")
const KEYS=Routes.KEYS
var beach
@onready var service = get_node("/root/BeachScenes")
@onready var targets: OptionButton = $Actions/Targets
@onready var switch_button: Button = $Actions/Switch

func _ready() -> void:
	targets.clear()
	for key in KEYS:
		targets.add_item(Routes.LABELS.get(key,key))
	beach = get_parent()
	while beach != null and not beach.has_method("_domain_id"):
		beach = beach.get_parent()
	if beach == null:
		return
	targets.select(KEYS.find(beach.scene_key))
	service.attach(beach)
	service.status_changed.connect(_refresh)
	_refresh()

func _process(_delta: float) -> void:
	if beach != null:
		var blocked: bool = service.busy or not beach.ready_for_ticks or beach.closing
		if switch_button.disabled != blocked: switch_button.disabled = blocked
		if targets.disabled != service.busy: targets.disabled = service.busy

func _refresh() -> void:
	$Status.text = service.message

func _on_switch_pressed() -> void:
	get_viewport().gui_release_focus()
	if not service.request_switch(KEYS[targets.selected]):
		$Status.text = "请等待场景准备完成"

