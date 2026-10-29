extends RefCounted

static func broad(mask: Array) -> PackedInt32Array:
	var selected := {}
	for chunk in 64:
		if (int(mask[chunk/32]) & (1 << (chunk%32)))==0: continue
		for dz in range(-1,2):
			for dx in range(-1,2):
				var x: int=chunk%8+dx
				var z: int=chunk/8+dz
				if x>=0 and x<8 and z>=0 and z<8: selected[z*8+x]=true
	var result:=PackedInt32Array(selected.keys());result.sort();return result

static func bounded(mask: Array, dirty: Rect2i) -> PackedInt32Array:
	if dirty.size.x<=0 or dirty.size.y<=0 or not Rect2i(0,0,256,256).encloses(dirty): return broad(mask)
	var selected := {}
	for chunk in 64:
		if (int(mask[chunk/32]) & (1 << (chunk%32)))==0: continue
		var cx: int=chunk%8
		var cz: int=chunk/8
		var possible:=dirty.intersection(Rect2i(cx*32,cz*32,32,32))
		if not possible.has_area(): return broad(mask)
		# A 33x33 heightmap samples [base,base+32]. Changes inside this
		# 32x32 cell tile can also belong to its left/upper shared edge.
		for dz in [-1,0]:
			for dx in [-1,0]:
				var x: int=cx+dx
				var z: int=cz+dz
				if x<0 or z<0: continue
				if possible.intersects(Rect2i(x*32,z*32,33,33)): selected[z*8+x]=true
	var result:=PackedInt32Array(selected.keys());result.sort();return result
