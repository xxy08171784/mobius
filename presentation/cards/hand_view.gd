class_name HandView
extends HBoxContainer
## 手牌只展示 DeckState.hand；点击只上报 UID，由 BattleInput 构造命令。

signal card_pressed(card_uid: int)

const CARD_VIEW_SCENE := preload("res://presentation/cards/battle_card_view.tscn")

var _labels: Dictionary = {}
var _views_by_uid: Dictionary = {}
var drag_validator: Callable


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
	var remaining := CardSelectionBudget.energy(state) - CardSelectionBudget.total_cost(state, card_defs, selected_uids)
	for uid: int in state.deck.hand:
		var card := state.deck.get_card(uid)
		if card == null:
			continue
		var definition: CardDef = card_defs.get(card.card_id)
		if definition == null:
			continue

		visible_uids[uid] = true
		var card_view := _views_by_uid.get(uid) as BattleCardView
		if card_view == null:
			card_view = CARD_VIEW_SCENE.instantiate() as BattleCardView
			card_view.card_pressed.connect(_on_card_button_pressed)
			_views_by_uid[uid] = card_view
			add_child(card_view)
		var order := selected_uids.find(uid)
		card_view.setup(card, definition, order, busy or not state.accepts_input(), state)
		card_view.drag_validator = drag_validator
		card_view.set_affordable(order >= 0 or card.effective_cost(definition) <= remaining)
		move_child(card_view, visual_index)
		visual_index += 1

	# 只清理已经真正离开手牌的卡。
	for uid_value: Variant in _views_by_uid.keys():
		var uid := int(uid_value)
		if visible_uids.has(uid):
			continue
		var stale := _views_by_uid[uid] as BattleCardView
		_views_by_uid.erase(uid)
		if stale != null:
			stale.visible = false
			stale.queue_free()


func _clear_buttons() -> void:
	for view_value: Variant in _views_by_uid.values():
		var card_view := view_value as BattleCardView
		if card_view != null:
			card_view.visible = false
			card_view.queue_free()
	_views_by_uid.clear()


func _on_card_button_pressed(uid: int) -> void:
	card_pressed.emit(uid)
