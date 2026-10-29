@tool
extends EditorPlugin

const SourceExport = preload("res://addons/runtime_source_export/source_export.gd")
var source_export: EditorExportPlugin

func _enter_tree() -> void:
	source_export = SourceExport.new()
	add_export_plugin(source_export)

func _exit_tree() -> void:
	remove_export_plugin(source_export)
	source_export = null
