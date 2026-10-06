class_name NodeChoiceScreen
extends Control
## rest/shop/event/reward/history/encyclopedia 的共用可视化页面。
signal chose(data: Dictionary)
signal leave_requested
@onready var _title: Label = %Title
@onready var _body: Label = %Body
@onready var _status: Label = %Status
@onready var _options_box: VBoxContainer = %Options
@onready var _leave_button: Button = %Leave


func _ready() -> void:
	_leave_button.pressed.connect(func() -> void: leave_requested.emit())


func set_content(title: String, body: String) -> void:
	_title.text = title
	_body.text = body
	_body.visible = not body.is_empty()
	_status.text = ""


func set_options(options: Array) -> void:
	for child: Node in _options_box.get_children():
		_options_box.remove_child(child)
		child.queue_free()
	var first: Button = null
	for option: Dictionary in options:
		var button := Button.new()
		button.text = String(option.get("text", ""))
		button.disabled = bool(option.get("disabled", false))
		button.add_theme_color_override("font_disabled_color", Color(0.7, 0.72, 0.76))
		button.tooltip_text = String(option.get("tooltip", ""))
		button.custom_minimum_size = Vector2(0, 48)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var data: Dictionary = option.get("data", {})
		button.pressed.connect(func() -> void: chose.emit(data))
		_options_box.add_child(button)
		if first == null and not button.disabled:
			first = button
	if first != null:
		UIFocus.take_later(first)
	else:
		UIFocus.take_later(_leave_button)


func set_status(text: String) -> void:
	_status.text = text


func set_leave_text(text: String) -> void:
	_leave_button.text = text


func set_leave_visible(value: bool) -> void:
	_leave_button.visible = value
