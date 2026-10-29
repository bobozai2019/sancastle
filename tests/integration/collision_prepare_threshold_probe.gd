extends "res://tests/integration/collision_thread_lifecycle_probe.gd"

func _run() -> void:
	var proxy=make_proxy("worker2")
	proxy.prepare_policy="worker2";proxy.prepare_min_chunks=16
	for count in [1,4,15,16]:
		var chunks:=PackedInt32Array()
		for i in count:chunks.append(i)
		var heights:=values(count,float(count))
		var completed_before: int=proxy.completed_batches
		apply(proxy,heights,chunks,count)
		check("threshold_"+str(count)+"_immediate_or_worker",proxy.has_prepare_in_flight()==(count==16))
		check("threshold_"+str(count)+"_settled",await settled(proxy))
		check("threshold_"+str(count)+"_exact_bytes",matches(proxy,heights,chunks))
		check("threshold_"+str(count)+"_one_completion",proxy.completed_batches==completed_before+1)
		check("threshold_"+str(count)+"_sample_mode",proxy.cost_samples[-1].mode==("worker2" if count==16 else "baseline"))
	check("metric_bound",proxy.cost_samples.size()<=256)
	await proxy.stop_prepare_and_drain()
	proxy.queue_free();await process_frame;await process_frame
	check("all_tasks_reclaimed",Scheduler.detached.is_empty())
	var pass_all:=true
	for item in checks:pass_all=pass_all and item.pass
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var file:=FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":pass_all,"checks":checks},"\t"));file.close()
	quit(0 if pass_all else 1)
