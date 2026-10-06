class_name HandView
extends HBoxContainer
## 手牌只展示 DeckState.hand；点击只上报 UID，由 BattleInput 构造命令。

signal card_pressed(card_uid: int)

var _labels: Dictionary = {}
var _buttons_by_uid: Dictionary = {}


func set_card_labels(labels: Dictionary) -> void:
	_labels = labels.duplicate()


func render_hand(
	state: BattleState,
	card_defs: Dictionary,
	selected_uids: Array[int],
	busy: bool = false
) -> void:
	if state == null:
		_clear_buttons()
		return

	var visible_uids: Dictionary = {}
	var visual_index := 0
	for uid: int in state.deck.hand:
		var card := state.deck.get_card(uid)
		if card == null:
			continue
		var definition: CardDef = card_defs.get(card.card_id)
		if definition == null:
			continue

		visible_uids[uid] = true
		var button := _buttons_by_uid.get(uid) as Button
		if button == null:
			button = _create_card_button(uid)
			_buttons_by_uid[uid] = button
			add_child(button)

		button.button_pressed = selected_uids.has(uid)
		button.disabled = busy or not state.accepts_input()
		var order := selected_uids.find(uid)
		var prefix := "[%d] " % (order + 1) if order >= 0 else ""
		button.text = prefix + String(_labels.get(card.card_id, String(card.card_id)))
		button.tooltip_text = CardInfo.tooltip_for(definition, card.upgrade_level)
		move_child(button, visual_index)
		visual_index += 1

	# 只清理已经真正离开手牌的卡。queue_free() 可安全用于信号调用栈中的节点。
	for uid_value: Variant in _buttons_by_uid.keys():
		var uid := int(uid_value)
		if visible_uids.has(uid):
			continue
		var stale := _buttons_by_uid[uid] as Button
		_buttons_by_uid.erase(uid)
		if stale != null:
			stale.visible = false
			stale.queue_free()


func _create_card_button(uid: int) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(150, 88)
	button.toggle_mode = true
	button.pressed.connect(_on_card_button_pressed.bind(uid))
	return button


func _clear_buttons() -> void:
	for button_value: Variant in _buttons_by_uid.values():
		var button := button_value as Button
		if button != null:
			button.visible = false
			button.queue_free()
	_buttons_by_uid.clear()


func _on_card_button_pressed(uid: int) -> void:
	card_pressed.emit(uid)
