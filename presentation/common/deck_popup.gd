class_name DeckPopup
extends Control
## 卡组查看弹层（只读）。战斗内按牌区分组，地图屏看永久卡组。
## 每条为带悬浮详情的按钮；点击遮罩或「关闭」退出。用完即 queue_free。

var _title: String = "卡组"
var _groups: Array = []


static func for_run(run: RunState) -> DeckPopup:
	var popup := DeckPopup.new()
	popup._title = "卡组（%d 张）" % run.deck.size()
	var entries: Array = []
	for card: RunCardState in run.deck:
		entries.append({"def": ContentDB.get_card(card.card_id), "level": card.upgrade_level})
	popup._groups = [{"title": "永久卡组", "entries": entries}]
	return popup


static func for_battle(state: BattleState, card_defs: Dictionary) -> DeckPopup:
	var popup := DeckPopup.new()
	popup._title = "牌堆"
	var zones := [
		{"title": "手牌", "uids": state.deck.hand},
		{"title": "抽牌堆", "uids": state.deck.draw},
		{"title": "弃牌堆", "uids": state.deck.discard},
		{"title": "消耗", "uids": state.deck.exhaust},
		{"title": "结算中", "uids": state.deck.resolving},
	]
	var groups: Array = []
	for zone: Dictionary in zones:
		var entries: Array = []
		for uid_value: Variant in zone["uids"]:
			var card: BattleCardState = state.deck.get_card(int(uid_value))
			if card == null:
				continue
			entries.append({"def": _def_for(card_defs, card.card_id), "level": card.upgrade_level, "card": card, "state": state})
		groups.append({"title": "%s（%d）" % [zone["title"], entries.size()], "entries": entries})
	popup._groups = groups
	return popup


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(_on_dim_input)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(600, 620)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var title := Label.new()
	title.text = _title
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	box.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 500)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	_build_entries(list)

	var close := Button.new()
	close.text = "关闭"
	close.custom_minimum_size = Vector2(0, 40)
	close.pressed.connect(queue_free)
	box.add_child(close)


func _build_entries(list: VBoxContainer) -> void:
	for group_value: Variant in _groups:
		var group: Dictionary = group_value
		var header := Label.new()
		header.text = String(group.get("title", ""))
		header.add_theme_font_size_override("font_size", 18)
		header.modulate = Color(0.8, 0.85, 0.95)
		list.add_child(header)
		var entries: Array = group.get("entries", [])
		if entries.is_empty():
			var empty := Label.new()
			empty.text = "（空）"
			empty.modulate = Color(0.6, 0.6, 0.6)
			list.add_child(empty)
			continue
		for entry_value: Variant in entries:
			var entry: Dictionary = entry_value
			var definition := entry.get("def") as CardDef
			var level := int(entry.get("level", 0))
			var button := Button.new()
			button.text = _entry_text(definition, level)
			button.tooltip_text = CardInfo.tooltip_for(definition, level, entry.get("card"), entry.get("state"))
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.focus_mode = Control.FOCUS_NONE
			button.custom_minimum_size = Vector2(0, 34)
			list.add_child(button)


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		queue_free()


static func _entry_text(definition: CardDef, level: int) -> String:
	if definition == null:
		return "（未知卡牌）"
	var suffix := "+" if level > 0 else ""
	return "%s%s  （%d 费 · %s）" % [
		CardInfo.display_name_of(definition),
		suffix,
		definition.get_cost(level),
		CardInfo.effect_summary(definition, level),
	]


static func _def_for(card_defs: Dictionary, card_id: StringName) -> CardDef:
	if card_defs.has(card_id):
		return card_defs[card_id] as CardDef
	if card_defs.has(String(card_id)):
		return card_defs[String(card_id)] as CardDef
	return null
