extends SceneTree
## Directed final API/metadata checks; no physics-kernel or scheduling changes.
var lab
var suite

func _init() -> void:call_deferred("_begin")

func _begin() -> void:
	lab=load("res://scenes/experiments/water_momentum_lab.tscn").instantiate()
	lab.paused=true
	root.add_child(lab)
	while lab.busy:await process_frame
	suite=load("res://tests/water_momentum_lab/tests/suite.gd").new()
	suite.lab=lab
	var original: PackedByteArray=await suite.snapshot("invalid_before")
	for change in [["gain",NAN],["radius","bad"],["operation","fill"],["template_id","unknown"],["template_hash","bad"],["b",Vector2.INF],["target_tick",999999],["generation",-1]]:
		var c: Dictionary=lab.make_command(Vector2.ZERO,Vector2.ZERO)
		c[change[0]]=change[1]
		var error: String=lab.enqueue(c)
		suite.check(not error.is_empty(),"reject malformed "+change[0])
	var after: PackedByteArray=await suite.snapshot("invalid_after")
	suite.check(original==after,"invalid packets produce no partial state")
	await suite.reset(2,"thin")
	lab.gain=4.
	var dry_before: PackedByteArray=await suite.snapshot("dry_before")
	await suite.edit(Vector2.ZERO,Vector2.ZERO,1)
	var dry_after: PackedByteArray=await suite.snapshot("dry_after")
	var dry_unchanged := true
	for z in lab.grid:
		for x in lab.grid/2:
			var at: int=(z*lab.grid+x)*16+4
			dry_unchanged=dry_unchanged and dry_before.slice(at,at+12)==dry_after.slice(at,at+12)
	suite.check(dry_unchanged,"h <= .001 dry h/q byte preserved")
	await suite.reset(2)
	await suite.edit(Vector2.ZERO,Vector2.ZERO,1)
	await suite.edit(Vector2.ZERO,Vector2.ZERO,1)
	var capped: float=lab.latest[11]
	suite.check(capped>0.,"edit speed cap exercised")
	suite.check(lab.latest[5]<=4.00002,"speed cap bounded")
	await suite.snapshot("capped")
	var identities := true
	for c in lab.accepted:
		identities=identities and c.template_id==lab.template_id and c.template_hash==lab.template_hash and c.input_us<=c.queued_us and c.a_m[0]==c.a.x and c.b_m[1]==c.b.y
	suite.check(identities,"template identity and input/queue timestamps recorded")
	var file := FileAccess.open(ProjectSettings.globalize_path(lab.run_dir)+"/packet_suite.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(suite.results,"\t"))
	for result in suite.results:
		if not result["pass"]:lab.last_error="packet validation failed"
	lab.closing=true
