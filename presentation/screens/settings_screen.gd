class_name SettingsScreen
extends Control
signal closed
var _capture: String = ""


func _ready() -> void:
	%Master.value = SettingsService.master
	%Music.value = SettingsService.music
	%SFX.value = SettingsService.sfx
	%TextScale.value = SettingsService.text_scale
	%Fullscreen.button_pressed = SettingsService.fullscreen
	%ReducedMotion.button_pressed = SettingsService.reduced_motion
	%Locale.add_item("简体中文", 0)
	%Locale.add_item("English (界面)", 1)
	%Locale.select(1 if SettingsService.locale == "en" else 0)
	%PlayKey.pressed.connect(_begin_capture.bind("battle_play"))
	%EndKey.pressed.connect(_begin_capture.bind("battle_end_turn"))
	%ClearKey.pressed.connect(_begin_capture.bind("battle_clear"))
	%Back.pressed.connect(_save)
	_update_keys()
	UIFocus.take_later(%Back)


func _begin_capture(action: String) -> void:
	_capture = action
	%Status.text = "按下新的按键；Esc 取消。"


func _input(event: InputEvent) -> void:
	if _capture.is_empty() or not event is InputEventKey or not event.pressed or event.echo:
		return
	get_viewport().set_input_as_handled()
	if event.physical_keycode == KEY_ESCAPE:
		_capture = ""
		%Status.text = "已取消。"
		return
	if SettingsService.set_key(_capture, event.physical_keycode):
		_capture = ""
		%Status.text = "按键已更新，返回时保存。"
		_update_keys()
	else:
		%Status.text = "按键已占用或不可用，请换一个。"


func _update_keys() -> void:
	%PlayKey.text = "出牌：" + OS.get_keycode_string(SettingsService.keys["battle_play"])
	%EndKey.text = "结束回合：" + OS.get_keycode_string(SettingsService.keys["battle_end_turn"])
	%ClearKey.text = "清除选择：" + OS.get_keycode_string(SettingsService.keys["battle_clear"])


func _save() -> void:
	SettingsService.master = %Master.value
	SettingsService.music = %Music.value
	SettingsService.sfx = %SFX.value
	SettingsService.text_scale = %TextScale.value
	SettingsService.fullscreen = %Fullscreen.button_pressed
	SettingsService.reduced_motion = %ReducedMotion.button_pressed
	SettingsService.locale = "en" if %Locale.selected == 1 else "zh_CN"
	SettingsService.apply()
	if SettingsService.save_settings():
		closed.emit()
	else:
		%Status.text = "保存失败，请检查磁盘空间与权限后重试。"
