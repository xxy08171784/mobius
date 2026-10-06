@tool
extends EditorPlugin
var dock: Control


func _enter_tree() -> void:
	dock = preload("res://addons/mobius_workbench/workbench.tscn").instantiate()
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)


func _exit_tree() -> void:
	if is_instance_valid(dock):
		remove_control_from_docks(dock)
		dock.queue_free()
