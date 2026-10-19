extends SceneTree
func _init():
 var scene=load("res://scenes/experiments/water_momentum_lab.tscn").instantiate()
 var spin=scene.get_node("Interface/Panel/Rows/Radius")
 print("UI radius step/value/text ",spin.step," ",spin.value," ",spin.get_line_edit().text)
 for prop in spin.get_property_list():
  if "precision" in prop.name or "decimal" in prop.name:print(prop.name," ",spin.get(prop.name))
 scene.free()
 quit()
