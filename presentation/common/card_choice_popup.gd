class_name CardChoicePopup
extends Window
## 正式卡的通用“额外选择牌”窗口。只收集 UI 意图，不修改任何规则状态。

signal choice_finished(result: Dictionary)

var _selected: Array[int] = []
var _min_count: int = 0
var _max_count: int = 1
var _confirm: Button = null
var _finished: bool = false


func setup(
	state: BattleState,
	card_defs: Dictionary,
	request: Dictionary
) -> void:
	title = String(request.get("title", "选择卡牌"))
	size = Vector2i(760, 520)
	_min_count = maxi(0, int(request.get("min_count", 0)))
	_max_count = maxi(_min_count, int(request.get("max_count", 1)))
	close_requested.connect(_cancel)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 16)
	add_child(root)

	var hint := Label.new()
	hint.text = "%s（选择 %d~%d 张）" % [title, _min_count, _max_count]
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(hint)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)

	for value: Variant in request.get("candidates", []):
		var uid := int(value)
		var card := state.deck.get_card(uid)
		if card == null:
			continue
		var definition: CardDef = card_defs.get(card.card_id) as CardDef
		if definition == null:
			definition = card_defs.get(String(card.card_id)) as CardDef
		if definition == null:
			continue
		var button := Button.new()
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(130, 175)
		button.tooltip_text = CardInfo.tooltip_for(definition, card.upgrade_level)
		var texture := CardVisuals.icon_for(definition)
		if texture != null:
			button.icon = texture
			button.expand_icon = true
		else:
			button.text = definition.display_name
		button.toggled.connect(_on_card_toggled.bind(uid, button))
		grid.add_child(button)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(actions)
	var cancel := Button.new()
	cancel.text = "取消"
	cancel.pressed.connect(_cancel)
	actions.add_child(cancel)
	_confirm = Button.new()
	_confirm.text = "确认"
	_confirm.pressed.connect(_confirm_choice)
	actions.add_child(_confirm)
	_update_confirm()


func show_centered() -> void:
	popup_centered()


func _on_card_toggled(pressed: bool, uid: int, button: Button) -> void:
	if pressed:
		if not _selected.has(uid):
			_selected.append(uid)
		if _selected.size() > _max_count:
			_selected.erase(uid)
			button.set_pressed_no_signal(false)
	else:
		_selected.erase(uid)
	_update_confirm()


func _update_confirm() -> void:
	if _confirm != null:
		_confirm.disabled = _selected.size() < _min_count or _selected.size() > _max_count


func _confirm_choice() -> void:
	_finish({"cancelled": false, "selected": _selected.duplicate()})


func _cancel() -> void:
	_finish({"cancelled": true, "selected": []})


func _finish(result: Dictionary) -> void:
	if _finished:
		return
	_finished = true
	choice_finished.emit(result)
	queue_free()
