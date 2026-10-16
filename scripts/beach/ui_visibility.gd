extends CanvasLayer

@onready var beach = get_parent()
@onready var interface: CanvasLayer = beach.get_node("Interface")
@onready var toggle: Button = $ToggleUI

func _ready() -> void:
	_sync()

func _process(_delta: float) -> void:
	_sync()

func _sync() -> void:
	interface.visible = not beach.hide_hud
	toggle.text = "显示 UI" if beach.hide_hud else "隐藏 UI"
	toggle.set_pressed_no_signal(beach.hide_hud)

func _on_toggle_pressed() -> void:
	beach.gpu_brush = &""
	beach._finish_ui_stroke(false)
	get_viewport().gui_release_focus()
	beach.hide_hud = not beach.hide_hud
	beach._update_status()
	_sync()
