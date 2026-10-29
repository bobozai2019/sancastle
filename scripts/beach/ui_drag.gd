extends Node

var dragging: Control
var pointer_offset := Vector2.ZERO
@onready var interface: CanvasLayer = get_parent().get_node("Interface")

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			if is_instance_valid(dragging):
				dragging = null
				get_viewport().set_input_as_handled()
			return
		if not interface.visible:
			return
		var hovered := get_viewport().gui_get_hovered_control()
		var ancestor := hovered
		while ancestor != null:
			if ancestor is BaseButton or ancestor is Range or ancestor is LineEdit or ancestor is TextEdit:
				return
			ancestor = ancestor.get_parent() as Control
		# Reverse draw order for panels which the player has moved over each other.
		var panels := interface.get_children()
		panels.reverse()
		for node in panels:
			if not node is Control or not node.is_visible_in_tree():
				continue
			if not node.get_global_rect().has_point(event.position):
				continue
			if hovered != null and hovered != node and not node.is_ancestor_of(hovered):
				continue
			dragging = node
			pointer_offset = event.position - node.global_position
			get_viewport().gui_release_focus()
			get_viewport().set_input_as_handled()
			return
	elif event is InputEventMouseMotion and is_instance_valid(dragging):
		if not interface.visible or not dragging.is_visible_in_tree():
			dragging = null
			return
		var bounds := get_viewport().get_visible_rect().size
		var target: Vector2 = event.position - pointer_offset
		# Keep the title reachable even when a panel is taller than the window.
		target.x = clampf(target.x, 0.0, maxf(0.0, bounds.x - dragging.size.x))
		target.y = clampf(target.y, 0.0, maxf(0.0, bounds.y - 36.0))
		dragging.global_position = target
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		dragging = null
