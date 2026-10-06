class_name UIFocus
extends RefCounted


static func take_later(control: Control) -> void:
	var apply := func() -> void:
		if is_instance_valid(control) and control.is_inside_tree() and control.is_visible_in_tree():
			control.grab_focus()
	apply.call_deferred()
