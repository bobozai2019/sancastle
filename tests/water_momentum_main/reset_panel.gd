extends VBoxContainer
func _on_switch_pressed() -> void:
 var beach=get_tree().current_scene
 if beach==null or not beach.has_method("shutdown"):return
 $Actions/Switch.disabled=true
 await beach.shutdown()
 get_tree().reload_current_scene()
