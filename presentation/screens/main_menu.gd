class_name MainMenuScreen
extends Control
## 主菜单：新游戏 / 继续 / 退出。只发信号，规则与存档由 RunFlow 处理。

signal new_game()
signal continue_run()
signal quit()


func setup(has_save: bool) -> void:
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
	box.add_theme_constant_override("separation", 16)
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	margin.add_child(box)

	var title := Label.new()
	title.text = "莫比乌斯"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "穿行回环，直到尽头。"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.modulate = Color(0.75, 0.78, 0.85)
	box.add_child(subtitle)

	box.add_child(HSeparator.new())

	var new_button := Button.new()
	new_button.text = "开始新游戏"
	new_button.custom_minimum_size = Vector2(0, 46)
	new_button.pressed.connect(func() -> void: new_game.emit())
	box.add_child(new_button)

	var continue_button := Button.new()
	continue_button.text = "继续冒险"
	continue_button.disabled = not has_save
	continue_button.custom_minimum_size = Vector2(0, 46)
	continue_button.pressed.connect(func() -> void: continue_run.emit())
	box.add_child(continue_button)

	var quit_button := Button.new()
	quit_button.text = "退出"
	quit_button.custom_minimum_size = Vector2(0, 46)
	quit_button.pressed.connect(func() -> void: quit.emit())
	box.add_child(quit_button)
