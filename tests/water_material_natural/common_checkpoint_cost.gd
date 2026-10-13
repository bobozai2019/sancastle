extends "res://tests/water_material_natural/full_cost_probe.gd"

const Store:=preload("res://scripts/simulation/checkpoint_store.gd")

func _digest_variant(value: Variant) -> String:
	var ctx:=HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256);ctx.update(var_to_bytes(value))
	return ctx.finish().hex_encode()

func _prepare_preview() -> bool:
	var path:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--checkpoint="):path=arg.trim_prefix("--checkpoint=")
	if path.is_empty():_fail("missing common checkpoint");return false
	var loaded:=Store.load(path)
	if not String(loaded.error).is_empty():_fail("common checkpoint invalid: "+String(loaded.error));return false
	var cp:Dictionary=loaded.checkpoint.duplicate(true)
	if cp.tick!=target_tick:_fail("common checkpoint tick mismatch");return false
	var old_profile:Dictionary=cp.render_profile.duplicate(true)
	var physical:=cp.duplicate(true);physical.erase("render_profile")
	var before_hash:=_digest_variant(physical)
	var candidate:Variant=preview.get("style_profile_path")
	if candidate is String:
		var style:Variant=JSON.parse_string(FileAccess.get_file_as_string(candidate))
		if not style is Dictionary:_fail("missing candidate identity");return false
		cp.render_profile.source_path=style.base_profile
		cp.render_profile.source_sha256=FileAccess.get_sha256(style.base_profile)
	physical=cp.duplicate(true);physical.erase("render_profile")
	var after_hash:=_digest_variant(physical)
	if before_hash!=after_hash:_fail("measurement changed physical checkpoint");return false
	preview.replay_checkpoint=cp
	preview.replay_prefix_commands.assign(loaded.prefix_commands)
	preview.enable_erosion=loaded.enable_erosion
	preview.generation=int(cp.shadow.generation)+1
	var file:=FileAccess.open(output+"/common_restore_setup.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checkpoint":path,"checkpoint_sha256":FileAccess.get_sha256(path),"before_render_profile":old_profile,"after_render_profile":cp.render_profile,"physical_variant_hash_before":before_hash,"physical_variant_hash_after":after_hash,"scope":"Cost-only metadata identity substitution; original file read-only, ordinary formal compatibility NOT proved."},"\t"));file.close()
	return true
