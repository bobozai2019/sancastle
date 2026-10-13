class_name SandcastleCheckpointStore
extends RefCounted

## Create-only, checksummed checkpoint envelope. The payload contains only
## Variant value types; object deserialization is deliberately disabled.

const MAGIC := "SANDCP01"
const FORMAT_VERSION := 1
const GRID_SIZE := 256
const CELL_COUNT := GRID_SIZE * GRID_SIZE
const MAX_PAYLOAD_BYTES := 32 * 1024 * 1024
const SNAPSHOT_FIELDS := ["rock", "sand", "water", "sediment", "wetness",
	"compaction", "obstacle", "flux_left", "flux_right", "flux_up", "flux_down"]
const GPU_FIELDS := ["water", "momentum_x", "momentum_z"]
const STAGING_FIXTURES := [&"water_render_demo_v2", &"water_render_coupled_v2"]


static func save(path: String, checkpoint: Dictionary,
		prefix_commands: Array[Dictionary], enable_erosion: bool) -> StringName:
	var envelope := {"format_version": FORMAT_VERSION,
		"enable_erosion": enable_erosion, "checkpoint": checkpoint,
		"prefix_commands": prefix_commands}
	var validation := _validate(envelope)
	if not validation.is_empty():
		return validation
	if FileAccess.file_exists(path):
		return &"already_exists"
	var payload := var_to_bytes(envelope)
	if payload.is_empty() or payload.size() > MAX_PAYLOAD_BYTES:
		return &"invalid_payload_size"
	var hash := HashingContext.new()
	if hash.start(HashingContext.HASH_SHA256) != OK:
		return &"hash_init_failed"
	hash.update(payload)
	var digest := hash.finish()
	var temp_path := path + ".tmp." + str(Time.get_ticks_usec())
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return &"open_failed"
	file.store_buffer(MAGIC.to_ascii_buffer())
	file.store_32(FORMAT_VERSION)
	file.store_32(payload.size())
	file.store_buffer(digest)
	file.store_buffer(payload)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
		return &"write_failed"
	var rename_error := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temp_path),
		ProjectSettings.globalize_path(path))
	if rename_error != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
		return &"rename_failed"
	return StringName()


static func load(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": &"open_failed"}
	if file.get_length() < 48 or file.get_length() > 48 + MAX_PAYLOAD_BYTES:
		return {"error": &"invalid_file_size"}
	var magic := file.get_buffer(8).get_string_from_ascii()
	var version := file.get_32()
	var payload_size := file.get_32()
	if magic != MAGIC or version != FORMAT_VERSION or payload_size < 1 or \
			payload_size > MAX_PAYLOAD_BYTES or file.get_length() != 48 + payload_size:
		return {"error": &"invalid_header"}
	var stored_digest := file.get_buffer(32)
	var payload := file.get_buffer(payload_size)
	file.close()
	if payload.size() != payload_size or stored_digest.size() != 32:
		return {"error": &"truncated"}
	var hash := HashingContext.new()
	if hash.start(HashingContext.HASH_SHA256) != OK:
		return {"error": &"hash_init_failed"}
	hash.update(payload)
	if hash.finish() != stored_digest:
		return {"error": &"checksum_mismatch"}
	var envelope: Variant = bytes_to_var(payload)
	if not envelope is Dictionary:
		return {"error": &"invalid_payload"}
	var validation := _validate(envelope)
	if not validation.is_empty():
		return {"error": validation}
	return {"error": StringName(), "checkpoint": envelope.checkpoint,
		"prefix_commands": envelope.prefix_commands,
		"enable_erosion": envelope.enable_erosion}


static func _validate(envelope: Dictionary) -> StringName:
	if envelope.get("format_version", -1) != FORMAT_VERSION or \
			typeof(envelope.get("enable_erosion")) != TYPE_BOOL or \
			not envelope.get("checkpoint") is Dictionary or \
			not envelope.get("prefix_commands") is Array:
		return &"invalid_envelope"
	var checkpoint: Dictionary = envelope.checkpoint
	if typeof(checkpoint.get("tick")) != TYPE_INT or checkpoint.tick < 0 or \
			typeof(checkpoint.get("preset_index")) != TYPE_INT or \
			checkpoint.preset_index not in [0, 1, 2] or \
			typeof(checkpoint.get("highwater_id")) != TYPE_INT or \
			checkpoint.highwater_id < 0 or \
			typeof(checkpoint.get("revision")) != TYPE_INT or \
			checkpoint.revision < 0 or \
			not checkpoint.get("command_ids") is PackedInt32Array or \
			not checkpoint.get("fields") is Dictionary or \
			not checkpoint.get("shadow") is Dictionary:
		return &"invalid_checkpoint_header"
	for ledger_key in ["water_source_m3", "water_sink_m3"]:
		if typeof(checkpoint.get(ledger_key)) not in [TYPE_FLOAT, TYPE_INT] or \
				not is_finite(float(checkpoint[ledger_key])):
			return &"invalid_checkpoint_ledger"
	var shadow: Dictionary = checkpoint.shadow
	if shadow.get("format_version", -1) != 1 or \
			shadow.get("grid_size", -1) != GRID_SIZE or \
			shadow.get("sim_tick", -1) != checkpoint.tick or \
			typeof(shadow.get("cell_size_m")) not in [TYPE_FLOAT, TYPE_INT] or \
			absf(float(shadow.get("cell_size_m", 0.0)) - 0.125) > 0.000001:
		return &"invalid_shadow_header"
	for ledger_key in ["tool_inventory_m3", "water_source_m3", "water_sink_m3",
			"sand_source_m3", "sand_sink_m3"]:
		if typeof(shadow.get(ledger_key)) not in [TYPE_FLOAT, TYPE_INT] or \
				not is_finite(float(shadow[ledger_key])) or \
				float(shadow[ledger_key]) < -0.000001:
			return &"invalid_shadow_ledger"
	for field in SNAPSHOT_FIELDS:
		if not shadow.get(field) is PackedFloat32Array or \
				shadow[field].size() != CELL_COUNT:
			return &"invalid_shadow_field"
		for value in shadow[field]:
			if not is_finite(value) or \
					(field in ["sand", "water", "sediment"] and value < -0.000001):
				return &"invalid_shadow_value"
	if typeof(checkpoint.get("structures", {})) != TYPE_DICTIONARY:
		return &"invalid_structures"
	var fixture_id := StringName(checkpoint.get("fixture_id", &""))
	if fixture_id not in [&"", &"water_v1", &"sand_v1", &"sand_coupled_v1",
			&"water_render_demo_v2", &"water_render_coupled_v2"]:
		return &"invalid_fixture_id"
	if fixture_id in STAGING_FIXTURES:
		var render_profile: Variant = checkpoint.get("render_profile", {})
		var profile_identity_valid: bool = (render_profile.get("profile_id") == \
				"water_render_staging_v1" and render_profile.get("schema_version") == 1) or \
				(render_profile.get("profile_id") == "water_render_staging_v2" and \
				render_profile.get("schema_version") == 2) or \
				(render_profile.get("profile_id") == "water_render_staging_v3" and \
				render_profile.get("schema_version") == 3) or \
				(render_profile.get("profile_id") == "water_render_staging_v4" and \
				render_profile.get("schema_version") == 4) or \
				(render_profile.get("profile_id") == "water_render_staging_v5" and \
				render_profile.get("schema_version") == 5) or \
				(render_profile.get("profile_id") == "water_render_staging_v6" and \
				render_profile.get("schema_version") == 6) or \
				(render_profile.get("profile_id") == "water_render_staging_v7" and \
				render_profile.get("schema_version") == 7) or \
				(render_profile.get("profile_id") == "water_render_staging_v8" and \
				render_profile.get("schema_version") == 8) if render_profile is Dictionary else false
		if not render_profile is Dictionary or render_profile.size() != 5 or \
				not profile_identity_valid or \
				typeof(render_profile.get("source_path")) != TYPE_STRING or \
				not String(render_profile.source_path).begins_with("res://") or \
				typeof(render_profile.get("source_sha256")) != TYPE_STRING or \
				String(render_profile.source_sha256).length() != 64 or \
				typeof(render_profile.get("visual_time_s")) not in [TYPE_INT, TYPE_FLOAT] or \
				not is_finite(float(render_profile.visual_time_s)) or \
				not is_equal_approx(float(render_profile.visual_time_s),
					float(checkpoint.tick) / 30.0):
			return &"invalid_render_profile"
	var cohesion: Variant = checkpoint.get("sand_cohesion_yield_height_m", 0.0)
	if typeof(cohesion) not in [TYPE_FLOAT, TYPE_INT] or \
			not is_finite(float(cohesion)) or float(cohesion) < 0.0 or \
			float(cohesion) > 2.0:
		return &"invalid_sand_profile"
	var support_schema: Variant = checkpoint.get("support_event_schema_version", 0)
	var support_events: Variant = checkpoint.get("support_loss_events", [])
	var support_highwater: Variant = checkpoint.get("support_loss_highwater_id", 0)
	if support_schema not in [0, 1, 2] or typeof(support_events) != TYPE_ARRAY or \
			typeof(support_highwater) != TYPE_INT or support_highwater < 0 or \
			(support_schema == 0 and not (support_events as Array).is_empty()) or \
			(fixture_id not in [&"sand_v1", &"sand_coupled_v1",
				&"water_render_coupled_v2"] and \
					not (support_events as Array).is_empty()) or \
			(support_schema == 2 and fixture_id not in [&"sand_coupled_v1",
				&"water_render_coupled_v2"]):
		return &"invalid_support_history"
	var previous_support_id := 0
	for event in support_events:
		if typeof(event) != TYPE_DICTIONARY or \
				typeof(event.get("request_id")) != TYPE_INT or \
				event.request_id <= previous_support_id or \
				event.request_id > support_highwater or \
				typeof(event.get("tick")) != TYPE_INT or \
				event.tick < 0 or event.tick > checkpoint.tick or \
				typeof(event.get("generation")) != TYPE_INT or \
				typeof(event.get("revision")) != TYPE_INT or \
				event.revision < 0 or event.revision > checkpoint.revision or \
				event.get("affected_cells", -1) != \
					(102 if support_schema == 2 else 289) or \
				typeof(event.get("compaction_after")) not in [TYPE_FLOAT, TYPE_INT] or \
				absf(float(event.compaction_after) - 0.1) > 0.000001:
			return &"invalid_support_history"
		if support_schema == 2 and (event.get("cause", "") != "erosion_toe_loss" or \
				typeof(event.get("sensor_revision")) != TYPE_INT or \
				event.sensor_revision < 0 or event.sensor_revision > event.revision or \
				typeof(event.get("toe_initial_m3")) not in [TYPE_FLOAT, TYPE_INT] or \
				typeof(event.get("toe_at_trigger_m3")) not in [TYPE_FLOAT, TYPE_INT] or \
				not is_finite(float(event.toe_initial_m3)) or \
				not is_finite(float(event.toe_at_trigger_m3)) or \
				float(event.toe_initial_m3) - float(event.toe_at_trigger_m3) < 0.015):
			return &"invalid_support_history"
		previous_support_id = event.request_id
	var waves: Variant = checkpoint.get("wave_requests", [])
	var wave_highwater: Variant = checkpoint.get("wave_highwater_id", 0)
	if typeof(waves) != TYPE_ARRAY or typeof(wave_highwater) != TYPE_INT or \
			wave_highwater < 0:
		return &"invalid_wave_history"
	var previous_wave_id := 0
	for wave in waves:
		if typeof(wave) != TYPE_DICTIONARY or \
				typeof(wave.get("request_id")) != TYPE_INT or \
				wave.request_id <= previous_wave_id or wave.request_id > wave_highwater or \
				typeof(wave.get("start_tick")) != TYPE_INT or wave.start_tick < 1 or \
				typeof(wave.get("seed")) != TYPE_INT or \
				typeof(wave.get("generation")) != TYPE_INT or \
				StringName(wave.get("domain_id", &"")) != StringName(checkpoint.shadow.get("domain_id", &"")) or \
				typeof(wave.get("amplitude_m")) not in [TYPE_FLOAT, TYPE_INT] or \
				typeof(wave.get("duration_s")) not in [TYPE_FLOAT, TYPE_INT]:
			return &"invalid_wave_history"
		var profile_id := StringName(wave.get("profile_id", &""))
		var amp := float(wave.amplitude_m)
		var duration := float(wave.duration_s)
		if not is_finite(amp) or not is_finite(duration) or \
				(profile_id == &"small_packet" and (amp < 0.0 or amp > 0.06 or duration < 0.5 or duration > 3.0)) or \
				(profile_id == &"test_packet" and (amp < 0.0 or amp > 0.20 or duration < 0.5 or duration > 6.0)) or \
				profile_id not in [&"small_packet", &"test_packet"]:
			return &"invalid_wave_history"
		previous_wave_id = wave.request_id
	var structures: Variant = checkpoint.get("structures", {})
	if typeof(structures) == TYPE_DICTIONARY and not (structures as Dictionary).is_empty():
		var entries: Variant = (structures as Dictionary).get("structures", [])
		if typeof(entries) != TYPE_ARRAY:
			return &"invalid_structures"
		for entry in entries:
			if typeof(entry) != TYPE_DICTIONARY:
				return &"invalid_structures"
			var damage: Variant = entry.get("damage", 0.0)
			var height: Variant = entry.get("height_m", 0.0)
			if typeof(damage) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(damage)) or 					float(damage) < 0.0 or float(damage) > 1.0:
				return &"invalid_structures"
			if typeof(height) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(height)) or 					float(height) < 0.0:
				return &"invalid_structures"
	for field in GPU_FIELDS:
		if not checkpoint.fields.get(field) is PackedFloat32Array or \
				checkpoint.fields[field].size() != CELL_COUNT:
			return &"invalid_gpu_field"
		for value in checkpoint.fields[field]:
			if not is_finite(value) or (field == "water" and value < -0.000001):
				return &"invalid_gpu_value"
	if checkpoint.fields["water"] != shadow["water"]:
		return &"water_shadow_mismatch"
	if checkpoint.has("foam_history"):
		var foam: Variant = checkpoint.foam_history
		if not foam is PackedFloat32Array or foam.size() != CELL_COUNT * 2:
			return &"invalid_foam_history"
		for i in foam.size():
			var value: float = foam[i]
			if not is_finite(value) or (i % 2 == 0 and \
					(value < 0.0 or value > 1.0)) or \
					(i % 2 == 1 and value < 0.0):
				return &"invalid_foam_history"
	if fixture_id in STAGING_FIXTURES and not checkpoint.has("local_front_history"):
		return &"invalid_local_front_history"
	if checkpoint.has("local_front_history"):
		var front: Variant = checkpoint.local_front_history
		if not front is PackedFloat32Array or front.size() != CELL_COUNT * 2:
			return &"invalid_local_front_history"
		for value in front:
			if not is_finite(value):
				return &"invalid_local_front_history"
	var commands: Array = envelope.prefix_commands
	var ids: PackedInt32Array = checkpoint.command_ids
	if commands.size() != ids.size():
		return &"command_prefix_mismatch"
	for i in commands.size():
		if not commands[i] is Dictionary or commands[i].get("command_id", -1) != ids[i] or \
				ids[i] < 1 or ids[i] > checkpoint.highwater_id or \
				(i > 0 and ids[i] <= ids[i - 1]) or \
				typeof(commands[i].get("sim_tick")) != TYPE_INT or \
				commands[i].get("sim_tick", -1) < 0 or \
				commands[i].get("sim_tick", -1) > checkpoint.tick or \
				not commands[i].has("kind") or not commands[i].has("shape") or \
				not commands[i].get("transform") is Dictionary:
			return &"invalid_command_prefix"
	return StringName()
