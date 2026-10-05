extends Control
## Phase 4 最小可玩战斗屏。正式美术未到位前全部使用 Godot Control 占位。

const BOARD_VIEW_SCENE := preload("res://presentation/battle/board_view.tscn")
const HAND_VIEW_SCENE := preload("res://presentation/cards/hand_view.tscn")
const ENEMY_OPTIONS: Array = [
	[&"enemy.ring_stalker", "环影猎手"],
	[&"enemy.echo_guard", "回声守卫"],
	[&"enemy.loop_hound", "循环猎犬"],
	[&"enemy.mobius_warden", "莫比乌斯守望者 [Boss]"],
]

var _session: BattleSession = null
var _presenter: BattlePresenter = null
var _battle_input: BattleInput = null
var _board_view: BoardView = null
var _hand_view: HandView = null
var _enemy_selector: OptionButton = null
var _ui: Dictionary = {}


func _ready() -> void:
	_build_ui()
	_populate_enemy_selector()
	_start_demo()


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	var title := Label.new()
	title.text = "GAMEGAM · Phase 4 占位战斗原型（无需正式美术）"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	root.add_child(title)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 18)
	root.add_child(top)
	_ui["round_label"] = _label_into(top, "回合")
	_ui["player_label"] = _label_into(top, "玩家")
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	_ui["intent_label"] = _label_into(top, "敌人意图")

	var content := HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	root.add_child(content)

	var board_panel := PanelContainer.new()
	board_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(board_panel)
	_board_view = BOARD_VIEW_SCENE.instantiate() as BoardView
	board_panel.add_child(_board_view)

	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(330, 0)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(side)

	var help := Label.new()
	help.text = "操作：\n1. 不选牌时点击空格 = 移动\n2. 点击卡牌选择组合顺序\n3. 点击敌人锁定目标\n4. 点击“打出所选”\n5. 点击“结束回合”看敌人行动\n6. 下方可切换敌人/Boss测试"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(help)

	var enemy_row := HBoxContainer.new()
	enemy_row.add_theme_constant_override("separation", 8)
	side.add_child(enemy_row)
	_label_into(enemy_row, "测试敌人：")
	_enemy_selector = OptionButton.new()
	_enemy_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	enemy_row.add_child(_enemy_selector)
	_enemy_selector.item_selected.connect(_on_enemy_selected)

	_ui["result_label"] = _label_into(side, "")
	var event_log := RichTextLabel.new()
	event_log.bbcode_enabled = true
	event_log.custom_minimum_size = Vector2(320, 250)
	event_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(event_log)
	_ui["event_log"] = event_log

	var hand_title := Label.new()
	hand_title.text = "手牌"
	root.add_child(hand_title)
	var hand_scroll := ScrollContainer.new()
	hand_scroll.custom_minimum_size = Vector2(0, 105)
	hand_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	hand_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(hand_scroll)
	_hand_view = HAND_VIEW_SCENE.instantiate() as HandView
	_hand_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hand_scroll.add_child(_hand_view)

	_ui["selection_label"] = _label_into(root, "已选卡牌：无")
	_ui["preview_label"] = _label_into(root, "预览：选择卡牌后显示结算结果")
	var controls := HBoxContainer.new()
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	controls.add_theme_constant_override("separation", 12)
	root.add_child(controls)
	_ui["play_button"] = _button_into(controls, "打出所选")
	_ui["clear_button"] = _button_into(controls, "清空选择")
	_ui["end_turn_button"] = _button_into(controls, "结束回合")
	_ui["restart_button"] = _button_into(controls, "重新开始")

	_board_view.cell_pressed.connect(_on_cell_pressed)
	_hand_view.card_pressed.connect(_on_card_pressed)
	(_ui["play_button"] as Button).pressed.connect(_on_play_pressed)
	(_ui["clear_button"] as Button).pressed.connect(_on_clear_pressed)
	(_ui["end_turn_button"] as Button).pressed.connect(_on_end_turn_pressed)
	(_ui["restart_button"] as Button).pressed.connect(_start_demo)


func _start_demo() -> void:
	if _presenter != null:
		_presenter.queue_free()
	if _battle_input != null:
		_battle_input.queue_free()

	var data := DemoBattleSetup.build("phase5-content-demo", _selected_enemy_id())
	if data.is_empty():
		(_ui["result_label"] as Label).text = "正式内容加载失败，请查看错误日志。"
		return
	_session = BattleSession.new()
	_session.setup(
		data["rng"],
		data["state"],
		data["card_defs"],
		data["enemy_behaviors"],
		data["enemy_actions"],
		Callable(self, "_validate_card_target")
	)

	_presenter = BattlePresenter.new()
	add_child(_presenter)
	_presenter.bind(
		_session,
		data["card_defs"],
		data["card_labels"],
		_board_view,
		_hand_view,
		_ui
	)

	_battle_input = BattleInput.new()
	add_child(_battle_input)
	_battle_input.bind(_session, data["card_defs"], _presenter)


func _populate_enemy_selector() -> void:
	if _enemy_selector == null:
		return
	_enemy_selector.clear()
	for option: Array in ENEMY_OPTIONS:
		var index := _enemy_selector.item_count
		_enemy_selector.add_item(String(option[1]))
		_enemy_selector.set_item_metadata(index, option[0])
	if _enemy_selector.item_count > 0:
		_enemy_selector.select(0)


func _selected_enemy_id() -> StringName:
	if _enemy_selector == null or _enemy_selector.item_count == 0:
		return &"enemy.ring_stalker"
	return StringName(String(_enemy_selector.get_item_metadata(_enemy_selector.selected)))


func _on_enemy_selected(_index: int) -> void:
	if is_node_ready():
		_start_demo()


func _validate_card_target(
	state: Variant,
	card: BattleCardState,
	definition: CardDef,
	target: Variant
) -> Dictionary:
	if not state is BattleState:
		return {"ok": false}
	if not definition.get_tags().has(&"attack"):
		return {"ok": true}
	if not target is TargetSpec.UnitTarget:
		return {"ok": false}
	var battle := state as BattleState
	var players := battle.alive_player_ids()
	if players.is_empty():
		return {"ok": false}
	var actor_cell := battle.board.get_unit_cell(int(players[0]))
	var target_id := (target as TargetSpec.UnitTarget).unit_id
	var target_cell := battle.board.get_unit_cell(target_id)
	if target_cell == BoardState.INVALID_CELL:
		return {"ok": false, "fizzle": true}
	var distance := absi(actor_cell.x - target_cell.x) + absi(actor_cell.y - target_cell.y)
	var attack_range := definition.get_attack_range(card.upgrade_level)
	var los_ok := (
		not definition.needs_line_of_sight(card.upgrade_level)
		or BoardQuery.has_line_of_sight(battle.board, actor_cell, target_cell)
	)
	return {
		"ok": distance <= attack_range and los_ok,
		"fizzle": false,
	}


func _on_card_pressed(uid: int) -> void:
	if _battle_input != null:
		_battle_input.on_card_pressed(uid)


func _on_cell_pressed(cell: Vector2i) -> void:
	if _battle_input != null:
		_battle_input.on_cell_pressed(cell)


func _on_play_pressed() -> void:
	if _battle_input != null:
		_battle_input.play_selected()


func _on_clear_pressed() -> void:
	if _battle_input != null:
		_battle_input.clear_selection()


func _on_end_turn_pressed() -> void:
	if _battle_input != null:
		_battle_input.end_turn()


func _label_into(parent: Control, value: String) -> Label:
	var label := Label.new()
	label.text = value
	parent.add_child(label)
	return label


func _button_into(parent: Control, text_value: String) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(120, 38)
	parent.add_child(button)
	return button
