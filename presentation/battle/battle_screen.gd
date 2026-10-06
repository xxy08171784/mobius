extends Control
## 可视化编辑的战斗屏；既可独立 demo，也可由 RunFlow 注入正式遭遇。

signal battle_finished(result: BattleResult)

## false 时由 RunFlow 在 add_child 前关闭 demo，并随后调用 configure()。
@export var demo_autostart: bool = true

const ENEMY_OPTIONS: Array = [
	[&"enemy.ring_stalker", "环影猎手"],
	[&"enemy.echo_guard", "回声守卫"],
	[&"enemy.loop_hound", "循环猎犬"],
	[&"enemy.mobius_warden", "莫比乌斯守望者 [Boss]"],
]
const SPEED_STEPS: Array[float] = [1.0, 2.0, 3.0]

## 左右文字栏宽度（同宽 -> 中间棋盘居中）。
const SIDE_WIDTH := 300

var _session: BattleSession = null
var _presenter: BattlePresenter = null
var _battle_input: BattleInput = null
var _card_defs: Dictionary = {}
var _initial_battle_data: Dictionary = {}
@onready var _board_view: BoardView = $BoardZone/BoardView
@onready var _hand_view: HandView = $HandScroll/HandView
@onready var _battle_hud: BattleHud = $BattleHud
@onready var _battle_card_hud: BattleCardHud = $BattleCardHud
@onready var _enemy_selector: OptionButton = $DebugPanel/Margin/Side/EnemyRow/EnemySelector
@onready var _debug_panel: PanelContainer = $DebugPanel
@onready var _defeat_overlay: Control = $DefeatOverlay
@onready var _defeat_restart_button: Button = $DefeatOverlay/Center/Panel/Margin/Content/RestartButton
var _ui: Dictionary = {}


func _ready() -> void:
	_cache_ui()
	_connect_ui()
	_populate_enemy_selector()
	if demo_autostart:
		_start_demo()


func _cache_ui() -> void:
	_ui = {
		"battle_hud": _battle_hud,
		"battle_card_hud": _battle_card_hud,
		"selection_label": $SelectionLabel,
		"preview_label": $PreviewLabel,
		"result_label": $ResultLabel,
		"play_button": $ActionButtons/PlayButton,
		"end_turn_button": _battle_card_hud.end_turn_button,
		"clear_button": $ActionButtons/ClearButton,
		"restart_button": $DebugPanel/Margin/Side/RestartButton,
		"deck_button": $DebugPanel/Margin/Side/DeckButton,
		"speed_button": $DebugPanel/Margin/Side/SpeedButton,
		"monster_label": $DebugPanel/Margin/Side/MonsterLabel,
		"event_log": $DebugPanel/Margin/Side/EventLog,
	}



func _connect_ui() -> void:
	_board_view.cell_pressed.connect(_on_cell_pressed)
	_hand_view.card_pressed.connect(_on_card_pressed)
	(_ui["play_button"] as Button).pressed.connect(_on_play_pressed)
	(_ui["clear_button"] as Button).pressed.connect(_on_clear_pressed)
	(_ui["end_turn_button"] as BaseButton).pressed.connect(_on_end_turn_pressed)
	(_ui["restart_button"] as Button).pressed.connect(_start_demo)
	(_ui["deck_button"] as Button).pressed.connect(_on_deck_pressed)
	(_ui["speed_button"] as Button).pressed.connect(_on_speed_pressed)
	_defeat_restart_button.pressed.connect(_on_defeat_restart_pressed)
	_enemy_selector.item_selected.connect(_on_enemy_selected)
	_refresh_speed_button()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if key_event.pressed and not key_event.echo and key_event.keycode == KEY_F3:
		_debug_panel.visible = not _debug_panel.visible


func _start_demo() -> void:
	var data := DemoBattleSetup.build("phase5-content-demo", _selected_enemy_id())
	if data.is_empty():
		(_ui["result_label"] as Label).text = "正式内容加载失败，请查看错误日志。"
		return
	_start_battle(data, true)


## RunFlow 的正式接缝：接收 EncounterBuilder 生成的 BattleSession 装配数据。
func configure(data: Dictionary) -> void:
	if data.is_empty():
		var label := _ui.get("result_label") as Label
		if label != null:
			label.text = "战斗数据为空。"
		return
	if _enemy_selector != null and _enemy_selector.get_parent() is Control:
		(_enemy_selector.get_parent() as Control).visible = false
	var restart := _ui.get("restart_button") as Button
	if restart != null:
		restart.visible = false
	_start_battle(data, true)


func _start_battle(data: Dictionary, remember_initial: bool = false) -> void:
	if remember_initial:
		_initial_battle_data = _clone_battle_data(data)
	_defeat_overlay.visible = false
	var result_label := _ui.get("result_label") as Label
	if result_label != null:
		result_label.text = ""
	if _presenter != null:
		_presenter.queue_free()
	if _battle_input != null:
		_battle_input.queue_free()

	_session = BattleSession.new()
	_session.setup(
		data["rng"],
		data["state"],
		data["card_defs"],
		data["enemy_behaviors"],
		data["enemy_actions"],
		Callable(self, "_validate_card_target"),
		data.get("summon_pool", []),
		data.get("enemy_reactions", {})
	)
	_card_defs = data["card_defs"]

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
	_battle_input.battle_finished.connect(_on_battle_input_finished)


func _on_battle_input_finished(result: BattleResult) -> void:
	if result != null and not result.victory:
		_defeat_overlay.visible = true
		return
	battle_finished.emit(result)


func _on_defeat_restart_pressed() -> void:
	if _initial_battle_data.is_empty():
		_start_demo()
		return
	_start_battle(_clone_battle_data(_initial_battle_data), false)


func _clone_battle_data(data: Dictionary) -> Dictionary:
	var copy := data.duplicate(true)
	var state := data.get("state") as BattleState
	if state != null:
		copy["state"] = SaveCodec.new().clone_state(state) as BattleState
	var rng := data.get("rng") as RngStreams
	if rng != null:
		copy["rng"] = rng.clone()
	return copy


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
	var rule := definition.get_target_rule(card.upgrade_level)
	if rule == null or rule is TargetSpec.DirectionTarget:
		return {"ok": true}
	if not target is TargetSpec:
		return {"ok": false}
	var battle := state as BattleState
	var players := battle.alive_player_ids()
	if players.is_empty():
		return {"ok": false}
	var actor_cell := battle.board.get_unit_cell(int(players[0]))
	var target_cell := BoardState.INVALID_CELL
	if target is TargetSpec.UnitTarget:
		target_cell = battle.board.get_unit_cell((target as TargetSpec.UnitTarget).unit_id)
	elif target is TargetSpec.CellTarget:
		target_cell = (target as TargetSpec.CellTarget).cell
	else:
		return {"ok": true}
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


func _on_deck_pressed() -> void:
	if _session == null or _session.state == null:
		return
	add_child(DeckPopup.for_battle(_session.state, _card_defs))


## 只缩短棋子位移 tween，不改变 AnimatedSprite2D 帧率。
func _on_speed_pressed() -> void:
	if _board_view == null:
		return
	var index := SPEED_STEPS.find(_board_view.speed_multiplier)
	if index < 0:
		index = 0
	_board_view.set_speed_multiplier(SPEED_STEPS[(index + 1) % SPEED_STEPS.size()])
	_refresh_speed_button()


func _refresh_speed_button() -> void:
	var button := _ui.get("speed_button") as Button
	if button != null and _board_view != null:
		button.text = "速度 %d×" % int(_board_view.speed_multiplier)
