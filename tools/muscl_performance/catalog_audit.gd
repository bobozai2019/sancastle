extends SceneTree

# Inspect offline pins and available fixtures; never add trust learned from a
# file being opened. Missing evidence is retained as missing, not a PASS.
func _initialize() -> void:
	var output:=OS.get_cmdline_user_args()[0]
	var rows: Array=[]
	for path in ["res://assets/unified_edit/legacy_source_catalog.variant","res://assets/unified_edit/numerics_source_catalog.variant","res://assets/unified_edit/floating_props_source_catalog.variant"]:
		var value: Variant=bytes_to_var(FileAccess.get_file_as_bytes(path))
		var entry:={"path":path,"sha256":FileAccess.get_sha256(path),"fixtures":[],"target_source_matches":[]}
		if not value is Dictionary:entry.error="invalid_catalog";rows.append(entry);continue
		if value.get("fixture") is Dictionary:
			var fixture: Dictionary=value.fixture
			var actual:=FileAccess.get_sha256(fixture.path) if FileAccess.file_exists(fixture.path) else ""
			entry.fixtures.append({"format":"native_v6","path":fixture.path,"expected_sha256":fixture.sha256,"available":not actual.is_empty(),"actual_sha256":actual,"matched":actual==fixture.sha256})
		for key in ["sources","native_sources","additional_sources"]:
			if not value.get(key) is Array:continue
			for row in value[key]:
				if not row is Dictionary or not row.get("fixture") is Dictionary:continue
				var fixture: Dictionary=row.fixture
				var actual:=FileAccess.get_sha256(fixture.path) if FileAccess.file_exists(fixture.path) else ""
				entry.fixtures.append({"format":row.get("format","native_v6"),"path":fixture.path,"expected_sha256":fixture.sha256,"available":not actual.is_empty(),"actual_sha256":actual,"matched":actual==fixture.sha256})
		if value.get("targets") is Array:
			for target in value.targets:
				var mismatches: Array=[]
				for source in target.get("sources",{}):
					if not FileAccess.file_exists(source) or FileAccess.get_sha256(source)!=target.sources[source]:mismatches.append(source)
				entry.target_source_matches.append({"all_match":mismatches.is_empty(),"mismatches":mismatches})
		if value.get("target_sources") is Dictionary:
			var mismatches: Array=[]
			for source in value.target_sources:
				if not FileAccess.file_exists(source) or FileAccess.get_sha256(source)!=value.target_sources[source]:mismatches.append(source)
			entry.target_source_matches.append({"all_match":mismatches.is_empty(),"mismatches":mismatches})
		rows.append(entry)
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"catalogs":rows,"scope":"Offline pinned fixture availability and exact target source hashes only; does not assert successful migration or widen any source allowlist"},"\t"))
	quit()
