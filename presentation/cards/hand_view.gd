class_name HandView
extends HBoxContainer
## 手牌只展示 DeckState.hand；点击只上报 UID，由 BattleInput 构造命令。

signal card_pressed(card_uid: int)

var _labels: Dictionary = {}


func set_card_labels(labels: Dictionary) -> void:
	_labels = labels.duplicate()


func render_hand(
	state: BattleState,
	card_defs: Dictionary,
	selected_uids: Array[int],
	busy: bool = false
) -> void:
	for child: Node in get_children():
		child.free()
	if state == null:
		return

	for uid: int in state.deck.hand:
		var card := state.deck.get_card(uid)
		if card == null:
			continue
		var definition: CardDef = card_defs.get(card.card_id)
		if definition == null:
			continue
		var button := Button.new()
		button.custom_minimum_size = Vector2(150, 88)
		button.toggle_mode = true
		button.button_pressed = selected_uids.has(uid)
		button.disabled = busy or not state.accepts_input()
		var order := selected_uids.find(uid)
		var prefix := "[%d] " % (order + 1) if order >= 0 else ""
		button.text = prefix + String(_labels.get(card.card_id, String(card.card_id)))
		button.tooltip_text = "UID %d · %s" % [uid, String(card.card_id)]
		button.pressed.connect(_on_card_button_pressed.bind(uid))
		add_child(button)


func _on_card_button_pressed(uid: int) -> void:
	card_pressed.emit(uid)
