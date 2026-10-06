extends Control
## 稳定根入口：内容校验 -> 设置主题 -> 主菜单。


func _ready() -> void:
	var loaded := ContentDB.load_catalog()
	var errors := ContentValidator.validate(ContentDB, load(RunSession.CAMPAIGN_PATH))
	if not loaded or not errors.is_empty():
		var message := Label.new()
		message.text = "内容加载失败，请修复后重新启动。\n" + "\n".join(errors)
		add_child(message)
		return
	SettingsService.changed.connect(_apply_theme)
	_apply_theme()
	var flow := RunFlow.new()
	flow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(flow)
	flow.show_main_menu()


func _apply_theme() -> void:
	var ui_theme := Theme.new()
	ui_theme.default_font_size = roundi(22 * SettingsService.text_scale)
	theme = ui_theme
