extends VBoxContainer

const KEYS := ["main", "test1_capture", "test1_backwash"]
var beach
@onready var service = get_node("/root/BeachScenes")
@onready var targets: OptionButton = $Actions/Targets
@onready var switch_button: Button = $Actions/Switch

func _ready() -> void:
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
		switch_button.disabled = service.busy or not beach.ready_for_ticks or beach.closing
		targets.disabled = service.busy

func _refresh() -> void:
	$Status.text = service.message

func _on_switch_pressed() -> void:
	get_viewport().gui_release_focus()
	if not service.request_switch(KEYS[targets.selected]):
		$Status.text = "请等待场景准备完成"

