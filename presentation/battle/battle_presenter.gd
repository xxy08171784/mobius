class_name BattlePresenter
extends Node
## 将 BattleState / EventBatch 投影到占位 UI；不直接修改 HP、牌区或 phase。

var _session: BattleSession = null
var _card_defs: Dictionary = {}
var _board_view: BoardView = null
var _hand_view: HandView = null
var _ui: Dictionary = {}
var _selected_cards: Array[int] = []
var _target_unit_id: int = -1
var _busy: bool = false
var _preview_result: CommandResult = null
var _animation_queue := BattleAnimationQueue.new()


func _ready() -> void:
	add_child(_animation_queue)


func bind(
	session: BattleSession,
	card_defs: Dictionary,
	card_labels: Dictionary,
	board_view: BoardView,
	hand_view: HandView,
	ui: Dictionary
) -> void:
	_session = session
	_card_defs = card_defs
	_board_view = board_view
	_hand_view = hand_view
	_ui = ui
	_hand_view.set_card_labels(card_labels)
	reset_log()
	refresh()


func set_selection(cards: Array[int], target_unit_id: int) -> void:
	_selected_cards = cards.duplicate()
	_target_unit_id = target_unit_id
	refresh()


func set_preview(result: CommandResult) -> void:
	_preview_result = result
	refresh()


func set_busy(value: bool) -> void:
	_busy = value
	refresh()


func refresh() -> void:
	if _session == null or _session.state == null:
		return
	var state := _session.state
	_board_view.render_state(state, _target_unit_id, _busy)
	_hand_view.render_hand(state, _card_defs, _selected_cards, _busy)

	var round_label := _ui.get("round_label") as Label
	var player_label := _ui.get("player_label") as Label
	var intent_label := _ui.get("intent_label") as Label
	var selection_label := _ui.get("selection_label") as Label
	var preview_label := _ui.get("preview_label") as Label
	var result_label := _ui.get("result_label") as Label
	var play_button := _ui.get("play_button") as Button
	var clear_button := _ui.get("clear_button") as Button
	var end_turn_button := _ui.get("end_turn_button") as Button

	if round_label != null:
		round_label.text = "回合 %d · %s" % [state.round_index, _phase_text(state.phase)]
	var players := state.player_ids()
	if player_label != null and not players.is_empty():
		var player := state.get_unit(int(players[0]))
		player_label.text = "玩家 HP %d/%d  护盾 %d  能量 %d  移动 %d" % [
			player.hp,
			player.max_hp,
			player.block,
			player.get_resource(TurnSystem.ENERGY_RESOURCE),
			player.get_resource(TurnSystem.MOVE_RESOURCE),
		]
	if intent_label != null:
		intent_label.text = _intent_text(state)
	if selection_label != null:
		selection_label.text = _selection_text()
	if preview_label != null:
		preview_label.text = _preview_text()

	if result_label != null:
		if state.phase == BattleState.Phase.VICTORY:
			result_label.text = "胜利！可以点击“重新开始”再打一局。"
		elif state.phase == BattleState.Phase.DEFEAT:
			result_label.text = "失败。可以点击“重新开始”重试。"
		else:
			result_label.text = ""

	var can_input := state.accepts_input() and not _busy
	if play_button != null:
		play_button.disabled = not can_input or _selected_cards.is_empty()
	if clear_button != null:
		clear_button.disabled = not can_input or (_selected_cards.is_empty() and _target_unit_id < 0)
	if end_turn_button != null:
		end_turn_button.disabled = not can_input


func present_result(result: CommandResult) -> void:
	await get_tree().process_frame
	if result == null:
		_append_log("命令没有返回结果。")
		return
	if not result.accepted:
		_append_log("操作被拒绝：%s" % _error_text(result.error_code))
		return
	if result.events == null or result.events.size() == 0:
		_append_log("动作已执行。")
		return
	await _animation_queue.play(
		result.events,
		Callable(self, "_present_event"),
		Callable(self, "_present_visual_event")
	)


func reset_log() -> void:
	var log := _ui.get("event_log") as RichTextLabel
	if log != null:
		log.clear()
		log.append_text("[b]战斗记录[/b]\n选择卡牌后点敌人，再点击“打出所选”。没有选牌时点击空格可移动。\n")


func _present_event(event: GameEvent) -> void:
	var actor := "玩家" if event.source_id == 1 else ("状态" if event.source_id < 0 else "敌人")
	var target := "玩家" if event.target_id == 1 else "敌人"
	var payload: Dictionary = {}
	if event is EffectEvent:
		payload = (event as EffectEvent).payload
	match event.type_key:
		&"damage":
			if payload.get("status_id", &"") == StatusRules.BLEED:
				_append_log("%s 的流血造成 %d 点伤害。" % [target, int(payload.get("hp_damage", payload.get("amount", 0)))])
			else:
				_append_log("%s 对 %s 造成 %d 点伤害。" % [actor, target, int(payload.get("hp_damage", payload.get("amount", 0)))])
		&"block_gained":
			_append_log("%s 获得 %d 点护盾。" % [target, int(payload.get("amount", 0))])
		&"unit_moved":
			_append_log("%s 发生移动。" % target)
		_:
			_append_log("事件：%s" % String(event.type_key))


func _present_visual_event(event: GameEvent) -> void:
	if _board_view == null:
		return
	var unit_id := event.target_id if event.target_id >= 0 else event.source_id
	if unit_id >= 0:
		_board_view.pulse_unit(unit_id)


func _append_log(message: String) -> void:
	var log := _ui.get("event_log") as RichTextLabel
	if log != null:
		log.append_text("\n%s" % message)
		log.scroll_to_line(maxi(0, log.get_line_count() - 1))


func _intent_text(state: BattleState) -> String:
	var enemy_ids := state.alive_enemy_ids()
	if enemy_ids.is_empty():
		return "敌人意图：无"
	var enemy_id := int(enemy_ids[0])
	var intent: IntentState = state.enemy_intents.get(enemy_id)
	if intent == null or intent.is_empty():
		return "敌人意图：等待"
	return "敌人意图：%s · 数值 %d · 目标格 %s" % [
		String(intent.action_id),
		intent.magnitude,
		str(intent.locked_cell),
	]


func _selection_text() -> String:
	var text := "已选卡牌："
	if _selected_cards.is_empty():
		text += "无"
	else:
		text += str(_selected_cards)
	if _target_unit_id >= 0:
		text += "  · 目标单位 %d" % _target_unit_id
	return text


func _preview_text() -> String:
	if _selected_cards.is_empty():
		return "预览：选择卡牌后显示结算结果"
	if _preview_result == null:
		return "预览：等待目标"
	if not _preview_result.accepted:
		return "预览：%s" % _error_text(_preview_result.error_code)
	if _preview_result.events == null or _preview_result.events.size() == 0:
		return "预览：可执行（无直接数值事件）"
	var parts: Array[String] = []
	var damage := 0
	var block := 0
	var draw_count := 0
	var statuses: Array[String] = []
	for event: GameEvent in _preview_result.events.events:
		var payload: Dictionary = {}
		if event is EffectEvent:
			payload = (event as EffectEvent).payload
		match event.type_key:
			&"damage":
				damage += int(payload.get("hp_damage", payload.get("amount", 0)))
			&"block_gained":
				block += int(payload.get("amount", 0))
			&"cards_drawn":
				draw_count += Array(payload.get("cards", [])).size()
			&"status_applied":
				statuses.append(String(payload.get("status_id", "")))
	if damage > 0:
		parts.append("造成 %d HP 伤害" % damage)
	if block > 0:
		parts.append("获得 %d 护盾" % block)
	if draw_count > 0:
		parts.append("抽 %d 张牌" % draw_count)
	if not statuses.is_empty():
		parts.append("施加 %s" % ", ".join(statuses))
	if parts.is_empty():
		parts.append("%d 个事件" % _preview_result.events.size())
	return "预览：" + "；".join(parts)


func _phase_text(phase: BattleState.Phase) -> String:
	match phase:
		BattleState.Phase.PLAYER_INPUT:
			return "玩家行动"
		BattleState.Phase.RESOLVING:
			return "结算中"
		BattleState.Phase.VICTORY:
			return "胜利"
		BattleState.Phase.DEFEAT:
			return "失败"
		_:
			return BattleState.Phase.keys()[phase]


func _error_text(code: CommandResult.ErrorCode) -> String:
	match code:
		CommandResult.ErrorCode.BUSY:
			return "结算动画尚未结束"
		CommandResult.ErrorCode.COST:
			return "能量或移动点不足"
		CommandResult.ErrorCode.TARGET:
			return "目标非法或不在攻击范围"
		CommandResult.ErrorCode.COMBO:
			return "卡牌组合非法"
		CommandResult.ErrorCode.PHASE:
			return "当前阶段不能操作"
		_:
			return CommandResult.ErrorCode.keys()[code]
