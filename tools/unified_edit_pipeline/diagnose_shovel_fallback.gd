extends "res://tools/unified_edit_pipeline/diagnose_shovel_long.gd"

const FallbackObserver=preload("res://tools/unified_edit_pipeline/shovel_fallback_observer.gd")
var fallback_observer

func _initialize() -> void:
	super._initialize()
	for path in ["res://tools/unified_edit_pipeline/diagnose_shovel_fallback.gd","res://tools/unified_edit_pipeline/shovel_fallback_observer.gd","res://tools/unified_edit_pipeline/shovel_fallback_witness.glsl"]:probe_sources[path]=FileAccess.get_sha256(path)

func _configure_render() -> void:
	# Publish readiness only after the witness resources exist on the render thread.
	var owner=scene.runtime.current;device=owner.state.rd
	owner.diagnostics=timeline;owner.heights.diagnostics=timeline
	observer=Observer.new();observer.adopt(owner.executor)
	fallback_observer=FallbackObserver.new();fallback_observer.adopt(observer.response)
	fallback_observer.sparse=water_only
	observer.response=fallback_observer
	observer.original.response=fallback_observer;owner.executor=observer
	owner.state.profile_passes=sampling
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),sampling)
	call_deferred("_configured")

func _exercise() -> void:
	await super._exercise()
	RenderingServer.call_on_render_thread(fallback_observer.collect_render)
	var deadline:=Time.get_ticks_msec()+15000
	while not fallback_observer.witness_done and Time.get_ticks_msec()<deadline:await process_frame
	check("fallback_witness_readback",fallback_observer.witness_done and fallback_observer.witness_error==OK and fallback_observer.witness_bytes.size()==144+65536*32)
	if fallback_observer.witness_bytes.size()==144+65536*32:
		var bytes: PackedByteArray=fallback_observer.witness_bytes
		var path:=output.get_basename()+".fallback.bin"
		FileAccess.open(path,FileAccess.WRITE).store_buffer(bytes)
		observations.fallback_witness={"serial":bytes.decode_u32(0),"path":path,"sha256":FileAccess.get_sha256(path),"size":bytes.size(),"scope":"First actual packed failure before generic dispatch. Adds two private GPU dispatches per packed response; use for cause evidence, not baseline frame performance."}
