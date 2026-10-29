extends "res://tests/integration/water_execution_exact_probe.gd"
const Upload=preload("res://tools/muscl_performance/fixture_upload.gd")

# Mixed wet/dry cells cross both workgroup and domain boundaries. The same
# deliberate initial input is installed into each independently built owner.
func prepare_test_tick(spec: Dictionary, iteration: int) -> void:
	if iteration!=0:return
	var rd: RenderingDevice=owner.state.rd
	for name in ["water","momentum_x","momentum_z","sediment"]:
		for rid in owner.state.textures[name]:
			var bytes:=rd.texture_get_data(rid,0)
			for z in 256:
				for x in 128:bytes.encode_float((z*256+x)*4,0.0)
			check("mixed_input_uploaded",Upload.r32_256(rd,rid,bytes).pass)

func capture_received(value: Dictionary) -> void:
	value.cpu_completion_and_ledger=var_to_bytes({"generation":owner._generation,"state_seq":owner.completed_state_seq,"sim_tick":owner.completed_tick,"revision":owner.completed_revision,"advanced_time_s":owner.advanced_time_s,"ledger":owner.ledger_snapshot()})
	super.capture_received(value)

func run() -> void:
	reference=load(reference_root+"scripts/simulation/unified_edit/water_muscl.gd")
	var created: Dictionary=load("res://assets/unified_edit/default_catalog.tres").instantiate_registry();registry=created.registry
	for retention in [0.0,0.5,1.0]:
		var spec:={"name":"mixed_dry_"+str(retention),"retention":retention,"boundary":true,"erosion":true,"momentum":0.15}
		var before: Array=await fixture(spec,true)
		var after: Array=await fixture(spec,false)
		check(spec.name+"_count",before.size()==5 and after.size()==5)
		for i in mini(before.size(),after.size()):
			var differences: Array=[];var hashes: Dictionary={}
			for name in before[i]:
				if not after[i].has(name) or before[i][name]!=after[i][name]:differences.append(name)
				var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(before[i][name]);hashes[name]=hash.finish().hex_encode()
			check(spec.name+"_exact_"+str(i),differences.is_empty() and before[i].size()==after[i].size())
			observations.append({"case":spec.name,"tick":i+1,"differences":differences,"hashes":hashes})
	DirAccess.make_dir_recursive_absolute(output)
	FileAccess.open(output.path_join("exact.json"),FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"checks":checks,"observations":observations,"reference_root":reference_root,"scope":"Mixed wet/dry interface, domain edge, workgroup boundary, retention 0/.5/1, two RK phases, public double slots/control/audit plus CPU completion and ledger"},"\t"))
	quit(1 if failed else 0)
