extends SceneTree
const Selection=preload("res://scripts/simulation/edit_validation/collision_chunk_selection.gd")

func _init() -> void:
	var cases:=0
	for z in 256:
		for x in 256:
			var chunk: int=(z/32)*8+x/32
			var mask: Array=[0,0];mask[chunk/32]=1 << (chunk%32)
			var actual: PackedInt32Array=Selection.bounded(mask,Rect2i(x,z,1,1))
			var expected:=PackedInt32Array()
			# Independent oracle: test each physical 33x33 sampled heightmap.
			for candidate in 64:
				var bx: int=(candidate%8)*32
				var bz: int=(candidate/8)*32
				if x>=bx and x<=mini(bx+32,255) and z>=bz and z<=mini(bz+32,255): expected.append(candidate)
			if actual!=expected:
				printerr("selection mismatch at ",Vector2i(x,z)," actual=",actual," expected=",expected);quit(1);return
			cases+=1
	for rect in [Rect2i(31,31,3,3),Rect2i(0,0,256,256),Rect2i(111,126,4,4),Rect2i(224,224,32,32),Rect2i(0,0,1,256)]:
		var mask: Array=[0,0]
		for z in range(rect.position.y,rect.end.y):
			for x in range(rect.position.x,rect.end.x):
				var chunk: int=(z/32)*8+x/32
				mask[chunk/32]=int(mask[chunk/32])|(1 << (chunk%32))
		var expected:=PackedInt32Array()
		for candidate in 64:
			var bx: int=(candidate%8)*32
			var bz: int=(candidate/8)*32
			var covered:=false
			for z in range(bz,mini(bz+32,255)+1):
				for x in range(bx,mini(bx+32,255)+1):
					covered=covered or rect.has_point(Vector2i(x,z))
			if covered: expected.append(candidate)
		if Selection.bounded(mask,rect)!=expected: printerr("rectangle mismatch ",rect);quit(1);return
		cases+=1
	if Selection.bounded([1,0],Rect2i(-1,0,2,2))!=Selection.broad([1,0]): quit(1);return
	if Selection.bounded([1,0],Rect2i(100,100,1,1))!=Selection.broad([1,0]): quit(1);return
	print("COLLISION_SELECTION_PASS singleton_cases=65536 rectangle_cases=5 negative_fallbacks=2 total=",cases+2)
	quit(0)
