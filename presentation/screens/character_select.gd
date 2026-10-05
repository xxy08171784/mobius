class_name CharacterSelectScreen
extends Control
## 选角：列出可用角色，选择后发 chosen。只上报选择。

signal chosen(character_id: StringName)
signal back()


## characters: Array[Dictionary]，每项 { "id": StringName, "label": String }。
func setup(characters: Array) -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_bottom", 40)
	add_child(margin)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.custom_minimum_size = Vector2(420, 0)
	box.add_theme_constant_override("separation", 12)
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	margin.add_child(box)

	var title := Label.new()
	title.text = "选择角色"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)

	for character: Dictionary in characters:
		var button := Button.new()
		button.text = String(character.get("label", ""))
		button.custom_minimum_size = Vector2(0, 44)
		var id := StringName(String(character.get("id", "")))
		button.pressed.connect(func() -> void: chosen.emit(id))
		box.add_child(button)

	var back_button := Button.new()
	back_button.text = "返回"
	back_button.custom_minimum_size = Vector2(0, 36)
	back_button.pressed.connect(func() -> void: back.emit())
	box.add_child(back_button)
