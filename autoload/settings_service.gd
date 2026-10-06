extends Node
## 可持久化的显示、音量、语言、动画与按键设置。不会进入确定性玩法状态。
signal changed
const PATH := "user://settings.cfg"
const DEFAULT_KEYS := {"battle_play": KEY_Q, "battle_end_turn": KEY_E, "battle_clear": KEY_BACKSPACE}
var master: float = 0.8
var music: float = 0.7
var sfx: float = 0.8
var fullscreen: bool = false
var text_scale: float = 1.0
var reduced_motion: bool = false
var locale: String = "zh_CN"
var keys: Dictionary = DEFAULT_KEYS.duplicate()


func _ready() -> void:
	load_settings()
	apply()


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		config.load(PATH + ".bak")
	for property: String in ["master", "music", "sfx", "fullscreen", "text_scale", "reduced_motion", "locale"]:
		set(property, config.get_value("settings", property, get(property)))
	master = clampf(master, 0.0, 1.0)
	music = clampf(music, 0.0, 1.0)
	sfx = clampf(sfx, 0.0, 1.0)
	text_scale = clampf(text_scale, 0.85, 1.25)
	for action: String in DEFAULT_KEYS:
		keys[action] = int(config.get_value("keys", action, DEFAULT_KEYS[action]))


func save_settings() -> bool:
	var config := ConfigFile.new()
	for property: String in ["master", "music", "sfx", "fullscreen", "text_scale", "reduced_motion", "locale"]:
		config.set_value("settings", property, get(property))
	for action: String in keys:
		config.set_value("keys", action, keys[action])
	if config.save(PATH + ".tmp") != OK:
		return false
	if FileAccess.file_exists(PATH):
		if DirAccess.copy_absolute(ProjectSettings.globalize_path(PATH), ProjectSettings.globalize_path(PATH + ".bak")) != OK:
			return false
		if DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH)) != OK:
			return false
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(PATH + ".tmp"), ProjectSettings.globalize_path(PATH)) == OK


func apply() -> void:
	TranslationServer.set_locale(locale)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	for action: String in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		var event := InputEventKey.new()
		event.physical_keycode = int(keys[action])
		InputMap.action_add_event(action, event)
		var joy := InputEventJoypadButton.new()
		joy.button_index = JOY_BUTTON_X if action == "battle_play" else (JOY_BUTTON_Y if action == "battle_end_turn" else JOY_BUTTON_B)
		InputMap.action_add_event(action, joy)
	changed.emit()


func set_key(action: String, key: int) -> bool:
	if not keys.has(action) or key == KEY_ESCAPE or key == 0:
		return false
	for other: String in keys:
		if other != action and int(keys[other]) == key:
			return false
	keys[action] = key
	apply()
	return true
