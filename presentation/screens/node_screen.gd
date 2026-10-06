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
	_leave_button.icon = UIArt.texture(&"back")
	_leave_button.expand_icon = true
	_leave_button.add_theme_constant_override("icon_max_width", 28)
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


## 使用同一套动态卡框/图标/文字展示奖励；只投影内容，不生成奖励或消费 RNG。
func set_card_options(options: Array) -> void:
	set_options([])
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	_options_box.add_child(row)
	_options_box.get_parent().get_parent().custom_minimum_size.x = maxf(640.0, options.size() * 230.0 + max(0, options.size() - 1) * 24.0)
	%Scroll.custom_minimum_size.y = 448
	for option: Dictionary in options:
		var definition: CardDef = ContentDB.get_card(StringName(option["card_id"]))
		var column := VBoxContainer.new()
		row.add_child(column)
		var holder := Control.new()
		holder.custom_minimum_size = Vector2(230, 334)
		column.add_child(holder)
		var view: BattleCardView = preload("res://presentation/cards/battle_card_view.tscn").instantiate()
		holder.add_child(view)
		view.position = Vector2(8, 10)
		view.scale = Vector2(1.7, 1.7)
		var card := BattleCardState.new()
		card.card_id = definition.card_id
		card.battle_uid = int(option.get("index", 0))
		view.setup(card, definition)
		var data: Dictionary = option["data"]
		view.card_pressed.connect(func(_uid: int) -> void: chose.emit(data))
		var button := Button.new()
		button.text = "选择此牌"
		button.custom_minimum_size.y = 46
		button.pressed.connect(func() -> void: chose.emit(data))
		column.add_child(button)
	var skip := Button.new()
	skip.text = "放弃奖励"
	skip.custom_minimum_size.y = 48
	skip.pressed.connect(func() -> void: chose.emit({"action": "reward_skip"}))
	_options_box.add_child(skip)
	set_leave_visible(false)
	UIFocus.take_later(skip)


func set_leave_text(text: String) -> void:
	_leave_button.text = text


func set_leave_visible(value: bool) -> void:
	_leave_button.visible = value
