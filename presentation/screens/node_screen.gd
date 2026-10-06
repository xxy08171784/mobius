class_name NodeChoiceScreen
extends Control
## 通用节点选择屏：标题 + 正文 + 一组按钮。rest / shop / event 共用。
## 只上报选择（携带 data），规则由 RunFlow 调对应 System 执行；本屏不改 RunState。

signal chose(data: Dictionary)
signal leave_requested()

var _title: Label = null
var _body: Label = null
var _status: Label = null
var _options_box: VBoxContainer = null
var _leave_button: Button = null


func _ready() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_top", 32)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_bottom", 32)
	add_child(margin)

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	margin.add_child(panel)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(560, 0)
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 26)
	box.add_child(_title)

	_body = Label.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_body)

	_options_box = VBoxContainer.new()
	_options_box.add_theme_constant_override("separation", 8)
	box.add_child(_options_box)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.modulate = Color(0.85, 0.9, 1.0)
	box.add_child(_status)

	_leave_button = Button.new()
	_leave_button.text = "离开"
	_leave_button.custom_minimum_size = Vector2(0, 40)
	_leave_button.pressed.connect(func() -> void: leave_requested.emit())
	box.add_child(_leave_button)


func set_content(title: String, body: String) -> void:
	_title.text = title
	_body.text = body
	_body.visible = not body.is_empty()
	_status.text = ""


## options: Array[Dictionary]，每项 { "text": String, "disabled": bool=false, "data": Dictionary }。
func set_options(options: Array) -> void:
	for child: Node in _options_box.get_children():
		child.queue_free()
	for option: Dictionary in options:
		var button := Button.new()
		button.text = String(option.get("text", ""))
		button.disabled = bool(option.get("disabled", false))
		button.tooltip_text = String(option.get("tooltip", ""))
		button.custom_minimum_size = Vector2(0, 40)
		var data: Dictionary = option.get("data", {})
		button.pressed.connect(func() -> void: chose.emit(data))
		_options_box.add_child(button)


func set_status(text: String) -> void:
	_status.text = text


func set_leave_text(text: String) -> void:
	if _leave_button != null:
		_leave_button.text = text
