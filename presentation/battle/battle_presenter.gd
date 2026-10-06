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
	_board_view.set_threat_cells(_threat_cells(state))
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
	var monster_label := _ui.get("monster_label") as Label

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
	if monster_label != null:
		monster_label.text = _monster_text(state)
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
			var dot_id: StringName = payload.get("status_id", &"")
			var dot_label := &""
			if dot_id == StatusRules.BLEED:
				dot_label = &"流血"
			elif dot_id == StatusRules.POISON:
				dot_label = &"中毒"
			var dmg := int(payload.get("hp_damage", payload.get("amount", 0)))
			if dot_label != &"":
				_append_log("%s 的%s造成 %d 点伤害。" % [target, dot_label, dmg])
			else:
				_append_log("%s 对 %s 造成 %d 点伤害。" % [actor, target, dmg])
		&"block_gained":
			_append_log("%s 获得 %d 点护盾。" % [target, int(payload.get("amount", 0))])
		&"unit_moved":
			_append_log("%s 发生移动。" % target)
		&"unit_summoned":
			var def_id: String = String(payload.get("def_id", ""))
			var kind := def_id.get_slice(".", -1) if not def_id.is_empty() else "小怪"
			_append_log("%s 在 %s 刷新了一只 %s。" % [actor, str(payload.get("cell", Vector2i(-1, -1))), kind])
		_:
			_append_log("事件：%s" % String(event.type_key))


## 返回 Tween 时，动画队列会等它播完（见 BattleAnimationQueue.play）。
func _present_visual_event(event: GameEvent) -> Variant:
	if _board_view == null:
		return null
	match event.type_key:
		&"unit_moved":
			var mover := event.source_id if event.source_id >= 0 else event.target_id
			if mover < 0:
				return null
			var path := _move_path_of(event)
			if path.size() < 2:
				return null
			# 逐格走：每步 0.35s；步数由 path 长度决定。
			return _board_view.animate_unit_move(mover, path)
		&"damage":
			# 致命一击：受击反馈（闪红+后弹）→ 死亡动画（缓缓上升 + 虚化）。
			if event.target_id >= 0 and int(event.after.get("hp", 1)) <= 0 \
					and _board_view.unit_view(event.target_id) != null:
				return _death_sequence(event)
			# 目标受击：闪红 + 往后弹；攻击方前冲撞击。
			var tween: Tween = null
			if event.target_id >= 0:
				tween = _board_view.play_hit(event.target_id, event.source_id)
			if event.source_id >= 0 and event.source_id != event.target_id:
				var lunge := _board_view.bump_attack(event.source_id, event.target_id)
				if tween == null:
					tween = lunge
			return tween
		_:
			var unit_id := event.target_id if event.target_id >= 0 else event.source_id
			if unit_id >= 0:
				return _board_view.pulse_unit(unit_id)
	return null


## 致命一击的表现串联：受击反馈（闪红+后弹）→ 死亡动画（上升+虚化）。返回合并 Tween 供队列等待。
func _death_sequence(event: GameEvent) -> Tween:
	var seq: Tween = _board_view.create_tween()
	if event.source_id >= 0 and event.source_id != event.target_id:
		seq.tween_callback(_board_view.bump_attack.bind(event.source_id, event.target_id))
	if event.target_id >= 0:
		seq.tween_callback(_board_view.play_hit.bind(event.target_id, event.source_id))
	seq.tween_interval(0.25)
	if event.target_id >= 0:
		seq.tween_callback(_board_view.animate_death.bind(event.target_id))
	seq.tween_interval(0.8)
	return seq


## 取移动事件的真实路径（棋盘格序列）；缺失时回退为 [起点, 终点]。
func _move_path_of(event: GameEvent) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if event is EffectEvent:
		var raw: Variant = (event as EffectEvent).payload.get("path", [])
		if raw is Array:
			for cell: Variant in raw:
				if cell is Vector2i:
					out.append(cell)
	if out.size() >= 2:
		return out
	out.clear()
	var from_cell: Variant = event.before.get("cell")
	var to_cell: Variant = event.after.get("cell")
	if from_cell is Vector2i:
		out.append(from_cell)
	if to_cell is Vector2i:
		out.append(to_cell)
	return out


func _append_log(message: String) -> void:
	var log := _ui.get("event_log") as RichTextLabel
	if log != null:
		log.append_text("\n%s" % message)
		log.scroll_to_line(maxi(0, log.get_line_count() - 1))


## 当前选中怪物的可打击格（威胁格显示）。无选中 / 非敌人 / 会话缺失 -> 空。
func _threat_cells(state: BattleState) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if _session == null or _target_unit_id < 0:
		return empty
	var unit := state.get_unit(_target_unit_id)
	if unit == null or not unit.is_alive() or unit.is_player():
		return empty
	return EnemyPlanner.threat_cells(
		state.board,
		_target_unit_id,
		_session.enemy_actions_for(_target_unit_id)
	)


## 选中敌人的数值面板文本（名字 / HP / 技能摘要）。未选中 / 非敌人 -> 空。
func _monster_text(state: BattleState) -> String:
	if _session == null or _target_unit_id < 0:
		return ""
	var unit := state.get_unit(_target_unit_id)
	if unit == null or unit.is_player() or not unit.is_alive():
		return ""
	var lines: Array[String] = []
	lines.append(_monster_name(unit))
	var hp_line := "HP %d/%d" % [unit.hp, unit.max_hp]
	if unit.block > 0:
		hp_line += "  盾 %d" % unit.block
	lines.append(hp_line)
	var skills: Array[String] = []
	for action: EnemyActionDef in _session.enemy_actions_for(_target_unit_id):
		var text := _monster_skill_text(action)
		if not text.is_empty() and not skills.has(text):
			skills.append(text)
	if not skills.is_empty():
		lines.append("技能：" + " / ".join(skills))
	return "\n".join(lines)


func _monster_name(unit: UnitState) -> String:
	if ContentDB.is_loaded() and not unit.enemy_id.is_empty():
		var definition: EnemyDef = ContentDB.get_enemy(unit.enemy_id)
		if definition != null and not definition.display_name.is_empty():
			return definition.display_name
	return String(unit.enemy_id) if not unit.enemy_id.is_empty() else "怪物"


## 把行动翻译成中文文案（意图预告与怪物数值面板共用）：
## "造成 7 伤害" / "获得 5 护盾" / "冲撞（造成 6 伤害，每步+3）" / "召唤小怪" / "接近玩家"。
func _monster_skill_text(action: EnemyActionDef) -> String:
	match action.kind:
		EnemyActionDef.Kind.ATTACK:
			var parts: Array[String] = []
			if _damage_value(action) > 0:
				var dmg := "造成 %s 伤害" % _damage_text(action)
				if action.hit_count > 1:
					dmg += "×%d" % action.hit_count
				parts.append(dmg)
			if not action.apply_status_id.is_empty() and action.apply_status_stacks > 0:
				parts.append("附带%s%d" % [_status_label(action.apply_status_id), action.apply_status_stacks])
			if action.pierce:
				parts.append("贯穿身后一格")
			if action.range_shape == BoardQuery.RangeShape.UNLIMITED:
				parts.append("无视距离")
			return "，".join(parts) if not parts.is_empty() else "攻击"
		EnemyActionDef.Kind.DEFEND:
			var defend := "获得 %s 护盾" % _block_text(action)
			if action.cleanse:
				defend += "，清除自身负面状态"
			return defend
		EnemyActionDef.Kind.DASH:
			return "冲撞（造成 %d 伤害，每步+%d）" % [action.damage, action.dash_damage_per_step]
		EnemyActionDef.Kind.PULL:
			return "勾魂（拉近 %d 格，每格+%d 伤害）" % [action.move_steps, action.dash_damage_per_step]
		EnemyActionDef.Kind.SUMMON:
			return "召唤小怪"
		EnemyActionDef.Kind.CHARGE:
			return "蓄力（造成 %s 伤害）" % _damage_text(action)
		EnemyActionDef.Kind.APPROACH:
			return "接近玩家"
		_:
			return String(action.id)


## 伤害显示：有区间则 "9-12"，否则固定值。
func _damage_text(action: EnemyActionDef) -> String:
	if action.damage_max >= action.damage_min and action.damage_max > 0:
		return "%d-%d" % [action.damage_min, action.damage_max]
	return str(action.damage)


## 伤害代表值（用于判断是否为纯状态攻击）：有区间取上限，否则固定值。
func _damage_value(action: EnemyActionDef) -> int:
	if action.damage_max >= action.damage_min and action.damage_max > 0:
		return action.damage_max
	return action.damage


## 护盾显示：有区间则 "8-12"，否则固定值。
func _block_text(action: EnemyActionDef) -> String:
	if action.block_max >= action.block_min and action.block_max > 0:
		return "%d-%d" % [action.block_min, action.block_max]
	return str(action.block)


func _status_label(status_id: StringName) -> String:
	match status_id:
		StatusRules.POISON:
			return "中毒"
		StatusRules.BLEED:
			return "流血"
		StatusRules.VULNERABLE:
			return "易伤"
		StatusRules.FOCUS:
			return "专注"
		StatusRules.WEAK:
			return "虚弱"
		StatusRules.SLOW:
			return "减速"
		StatusRules.ENTANGLE:
			return "缠绕"
		StatusRules.CORRODE:
			return "腐蚀"
		StatusRules.IGNITE:
			return "着火"
		_:
			return String(status_id)


## 敌人意图预告：列出每只存活怪物的中文意图（"引魂灯：造成 6 伤害"）。
func _intent_text(state: BattleState) -> String:
	var lines: Array[String] = []
	for enemy_id: int in state.alive_enemy_ids():
		var unit := state.get_unit(enemy_id)
		var intent: IntentState = state.enemy_intents.get(enemy_id)
		var name := _monster_name(unit) if unit != null else "敌人"
		if intent == null or intent.is_empty():
			lines.append("%s：等待" % name)
			continue
		var action := _intent_action(enemy_id, intent.action_id)
		if action == null:
			lines.append("%s：%s" % [name, String(intent.action_id)])
			continue
		lines.append("%s：%s" % [name, _monster_skill_text(action)])
	if lines.is_empty():
		return "敌人意图：无"
	return "敌人意图：\n" + "\n".join(lines)


## 把某敌人意图的 action_id 还原成行动定义（预告翻译 / 威胁格用）。
func _intent_action(enemy_id: int, action_id: StringName) -> EnemyActionDef:
	if _session == null:
		return null
	for action: EnemyActionDef in _session.enemy_actions_for(enemy_id):
		if action.id == action_id:
			return action
	return null


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
