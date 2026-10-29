extends RefCounted

const Base = preload("res://tests/shape_brushes/fixtures.gd")
const ROIS = [
	{"id":"wall","bounds":[-8.0,-4.0,-1.25,1.25]},
	{"id":"castle_sample","bounds":[-2.5,2.5,-2.5,2.5]},
	{"id":"tower_nw","bounds":[-2.0,-0.5,-2.0,-0.5]},
	{"id":"tower_ne","bounds":[0.5,2.0,-2.0,-0.5]},
	{"id":"tower_sw","bounds":[-2.0,-0.5,0.5,2.0]},
	{"id":"tower_se","bounds":[0.5,2.0,0.5,2.0]},
	{"id":"ordinary_compacted","bounds":[4.0,8.0,-2.0,2.0]}
]

static func build(mode: String) -> Dictionary:
	var data := Base.build("dry_flat")
	for z in 256:
		for x in 256:
			var i := z*256+x
			var p := Vector2((x+0.5-128)*0.125,(z+0.5-128)*0.125)
			var h := 0.0
			if absf(p.x)<=2.0 and absf(p.y)<=2.0:
				h=0.08
				if (absf(p.x)>=1.5 or absf(p.y)>=1.5): h=0.4
				for sx in [-1.0,1.0]:
					for sz in [-1.0,1.0]:
						var q := p-Vector2(sx*1.25,sz*1.25)
						if absf(q.x)<=0.75 and absf(q.y)<=0.75:
							h=maxf(h,0.55)
							if absf(q.x)>=0.25 and absf(q.y)>=0.25: h=0.7
			var nearest := Vector2(clampf(p.x,-7.0,-5.0),0.0)
			var distance := p.distance_to(nearest)
			var profile := 1.0 if distance<=0.25 else clampf((0.5-distance)/0.25,0.0,1.0)
			h=maxf(h,0.6*profile)
			var molded := h>0.0
			# This is a legal existing ordinary compacted heap, with no molded
			# identity. It distinguishes global cohesion from a local strategy.
			if absf(p.x-6.0)<=0.75 and absf(p.y)<=0.75:
				h=0.7; data.fields.compaction[i]=0.95
			elif molded and mode in ["compact","cohesion"]: data.fields.compaction[i]=0.95
			data.fields.sand[i]+=h
	data["mode"]=mode; data["rois"]=ROIS.duplicate(true)
	return data
