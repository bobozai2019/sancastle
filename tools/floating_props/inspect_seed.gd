extends SceneTree

func _initialize() -> void:
	var value: Dictionary=bytes_to_var(FileAccess.get_file_as_bytes("res://assets/unified_edit/presentation/main.variant"))
	print("SEED_KEYS ",value.keys())
	for x in [-8.0,-5.0,-3.0,-1.0,0.0,1.0,3.0]:
		var index: int=128*256+int((x+16.0)/0.125)
		print("SEED ",x," sand ",value.sand[index]," rock ",value.rock[index]," water ",value.water[index])
	for center_x in [0.7,1.0,1.6]:
		var maximum:=-INF
		for z in range(125,132):
			for x in range(floori((center_x-0.65+16.0)/0.125),ceili((center_x+0.65+16.0)/0.125)+1):
				var index: int=z*256+x;maximum=maxf(maximum,value.rock[index]+value.sand[index])
		print("PLANK_INITIAL_SUPPORT ",center_x," max_bed_m ",maximum," equilibrium_bottom_m ",0.14+0.004-0.04)
	for z in [-3.0,-1.5,0.0,1.5,3.0,4.5]:
		var row: Array=[]
		for x in [-4.0,-2.0,0.0,1.0,1.6,2.0,3.0,4.0]:
			var index: int=clampi(int((z+16.0)/0.125),0,255)*256+clampi(int((x+16.0)/0.125),0,255)
			row.append([x,value.rock[index]+value.sand[index],value.water[index]])
		print("SEED_ROW ",z," ",row)
	quit()
