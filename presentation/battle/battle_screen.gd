class_name BattleScreen
extends Control
## 可视化编辑的战斗屏；既可独立 demo，也可由 RunFlow 注入正式遭遇。

signal battle_finished(result: BattleResult)
signal checkpoint_requested(state: BattleState)
signal deployment_cell_chosen(cell: Vector2i)
signal deployment_cancelled

## false 时由 RunFlow 在 add_child 前关闭 demo，并随后调用 configure()。
@export var demo_autostart: bool = true
## 三幕背景使用素材/背景；透明度可在检查器调整。
@export_range(0.0, 1.0) var background_opacity: float = 0.32
@export_range(0, 2) var chapter_index: int = 0

const ENEMY_OPTIONS: Array = [
	[&"enemy.ring_stalker", "环影猎手"],
	[&"enemy.echo_guard", "回声守卫"],
	[&"enemy.loop_hound", "循环猎犬"],
	[&"enemy.mobius_warden", "莫比乌斯守望者 [Boss]"],
]
const SPEED_STEPS: Array[float] = [1.0, 2.0, 3.0]
const DEFAULT_BOARD_COLS := 8
const DEFAULT_BOARD_ROWS := 8

## 左右文字栏宽度（同宽 -> 中间棋盘居中）。
const SIDE_WIDTH := 300

var _session: BattleSession = null
var _presenter: BattlePresenter = null
var _battle_input: BattleInput = null
var _card_defs: Dictionary = {}
var _initial_battle_data: Dictionary = {}
var _deployment_mode: bool = false
@onready var _board_view: BoardView = $BoardZone/BoardView
@onready var _hand_view: HandView = $HandScroll/HandView
@onready var _battle_hud: BattleHud = $BattleHud
@onready var _battle_card_hud: BattleCardHud = $BattleCardHud
@onready var _deployment_ui: Control = $DeploymentUI
@onready var _deployment_back_button: Button = $DeploymentUI/BackButton
@onready var _enemy_selector: OptionButton = $DebugPanel/Margin/Side/EnemyRow/EnemySelector
@onready var _debug_panel: PanelContainer = $DebugPanel
@onready var _defeat_overlay: Control = $DefeatOverlay
@onready var _defeat_restart_button: Button = $DefeatOverlay/Center/Panel/Margin/Content/RestartButton
var _ui: Dictionary = {}
var _feedback: Label
var _feedback_tween: Tween


func _ready() -> void:
	set_chapter(chapter_index)
	$ActionButtons/PlayButton.set_meta("audio_cue", &"confirm")
	_battle_card_hud.end_turn_button.set_meta("audio_cue", &"confirm")
	_deployment_back_button.icon = UIArt.texture(&"back")
	_deployment_back_button.expand_icon = true
	_deployment_back_button.add_theme_constant_override("icon_max_width", 30)
	_cache_ui()
	_connect_ui()
	_populate_enemy_selector()
	_create_feedback()
	if demo_autostart:
		_start_demo()


func set_chapter(index: int) -> void:
	chapter_index = clampi(index, 0, 2)
	$ChapterBackground.texture = UIArt.background(chapter_index)
	$ChapterBackground.modulate.a = background_opacity


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
	_hand_view.drag_validator = func(uid: int) -> bool:
		return not _deployment_mode and _battle_input != null and _battle_input.can_start_drag(uid)
	_board_view.drop_validator = func(uid: int, cell: Vector2i) -> String:
		return "当前无法出牌" if _deployment_mode or _battle_input == null else _battle_input.drop_status(uid, cell)
	_board_view.card_dropped.connect(func(uid: int, cell: Vector2i) -> void:
		if _battle_input != null and not _deployment_mode:
			_battle_input.play_dropped(uid, cell)
	)
	_board_view.drop_rejected.connect(show_feedback)
	(_ui["play_button"] as Button).pressed.connect(_on_play_pressed)
	(_ui["clear_button"] as Button).pressed.connect(_on_clear_pressed)
	(_ui["end_turn_button"] as BaseButton).pressed.connect(_on_end_turn_pressed)
	(_ui["restart_button"] as Button).pressed.connect(_start_demo)
	(_ui["deck_button"] as Button).pressed.connect(_on_deck_pressed)
	(_ui["speed_button"] as Button).pressed.connect(_on_speed_pressed)
	_defeat_restart_button.pressed.connect(_on_defeat_restart_pressed)
	_deployment_back_button.pressed.connect(_on_deployment_back_pressed)
	_enemy_selector.item_selected.connect(_on_enemy_selected)
	_refresh_speed_button()


func _unhandled_input(event: InputEvent) -> void:
	if not _deployment_mode and _battle_input != null:
		if event.is_action_pressed("battle_play"):
			_battle_input.play_selected()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("battle_end_turn"):
			_battle_input.end_turn()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("battle_clear"):
			_battle_input.clear_selection()
			get_viewport().set_input_as_handled()
		if event is InputEventKey and event.pressed and not event.echo:
			var index: int = event.physical_keycode - KEY_1
			if index >= 0 and index < mini(9, _session.state.deck.hand.size()):
				_battle_input.on_card_pressed(_session.state.deck.hand[index])
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
	_set_deployment_mode(false)
	_start_battle(data, true)


## RunFlow 的开战前部署接缝。部署标题/提示/返回按钮都在 BattleScreen.tscn 里，
## 与正式战斗复用同一个 BoardZone，因此编辑器中拖动 BoardZone 后两种模式天然一致。
func configure_deployment(preview: Dictionary) -> void:
	_set_deployment_mode(true)
	var cols := int(preview.get("cols", DEFAULT_BOARD_COLS))
	var rows := int(preview.get("rows", DEFAULT_BOARD_ROWS))
	var enemy_cells: Array[Vector2i] = []
	for cell_value: Variant in preview.get("enemy_cells", []):
		enemy_cells.append(cell_value as Vector2i)
	var allowed: Array[Vector2i] = []
	for y in range(rows):
		for x in range(cols):
			if x == 0 or y == 0 or x == cols - 1 or y == rows - 1:
				allowed.append(Vector2i(x, y))
	_board_view.render_deployment(cols, rows, allowed, enemy_cells)


func _set_deployment_mode(enabled: bool) -> void:
	_deployment_mode = enabled
	_deployment_ui.visible = enabled
	_battle_hud.visible = not enabled
	_battle_card_hud.visible = not enabled
	$HandScroll.visible = not enabled
	$ActionButtons.visible = not enabled
	$PreviewLabel.visible = false
	$ResultLabel.visible = not enabled
	$SelectionLabel.visible = false
	$DebugPanel.visible = false
	_defeat_overlay.visible = false


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
	var fresh := (data["state"] as BattleState).phase == BattleState.Phase.SETUP
	_session.setup(
		data["rng"],
		data["state"],
		data["card_defs"],
		data["enemy_behaviors"],
		data["enemy_actions"],
		Callable(self, "_validate_card_target"),
		data.get("summon_pool", [])
	)
	_card_defs = data["card_defs"]

	_presenter = BattlePresenter.new()
	_presenter.audio_feedback.default_surface = &"grass" if chapter_index == 0 else &"stone"
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
	_battle_input.feedback_requested.connect(show_feedback)
	_battle_input.checkpoint_requested.connect(func(state: BattleState) -> void: checkpoint_requested.emit(state))
	checkpoint_requested.emit(_session.state)
	if fresh and not _session.state.deck.hand.is_empty():
		AudioService.play_cue(&"card_draw")
	if _session.state.is_terminal():
		_on_battle_input_finished.call_deferred(_session.battle_result())


func _create_feedback() -> void:
	_feedback = Label.new()
	_feedback.name = "ActionFeedback"
	_feedback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feedback.z_index = 100
	_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feedback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_feedback.add_theme_font_size_override("font_size", 32)
	_feedback.add_theme_color_override("font_color", Color("ffe0a8"))
	_feedback.add_theme_color_override("font_outline_color", Color("171b24"))
	_feedback.add_theme_constant_override("outline_size", 6)
	add_child(_feedback)
	_feedback.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_feedback.offset_left = -380
	_feedback.offset_right = 380
	_feedback.offset_top = -40
	_feedback.offset_bottom = 40
	_feedback.hide()


func show_feedback(message: String) -> void:
	if _feedback == null or message.is_empty():
		return
	if _feedback_tween != null:
		_feedback_tween.kill()
	_feedback.text = message
	_feedback.modulate.a = 1.0
	_feedback.show()
	_feedback_tween = create_tween()
	_feedback_tween.tween_interval(1.1)
	_feedback_tween.tween_property(_feedback, "modulate:a", 0.0, 0.25)
	_feedback_tween.tween_callback(_feedback.hide)


func _on_battle_input_finished(result: BattleResult) -> void:
	if demo_autostart and result != null and not result.victory:
		_defeat_overlay.visible = true
		return
	battle_finished.emit(result)


func _on_defeat_restart_pressed() -> void:
	if not demo_autostart:
		return
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
	return CardTargetRules.validate_range(state, card, definition, target)

func _on_card_pressed(uid: int) -> void:
	if _battle_input != null:
		_battle_input.on_card_pressed(uid)


func _on_cell_pressed(cell: Vector2i) -> void:
	if _deployment_mode:
		deployment_cell_chosen.emit(cell)
		return
	if _battle_input != null:
		_battle_input.on_cell_pressed(cell)


func _on_deployment_back_pressed() -> void:
	if _deployment_mode:
		deployment_cancelled.emit()


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
