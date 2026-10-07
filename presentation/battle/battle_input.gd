class_name BattleInput
extends Node
## 将鼠标/UI 意图转换为 GameCommand；不直接改 BattleState。

## 一场战斗进入终态时发出（携带 BattleResult）。B 线 RunFlow 据此回写 RunState。
signal battle_finished(result: BattleResult)
signal checkpoint_requested(state: BattleState)
signal feedback_requested(message: String)

var _session: BattleSession = null
var _card_defs: Dictionary = {}
var _presenter: BattlePresenter = null
var _selected_cards: Array[int] = []
var _selected_target_unit: int = -1
var _selected_cell: Vector2i = Vector2i(-1, -1)
var _next_command_id: int = 10000
var _busy: bool = false


func bind(session: BattleSession, card_defs: Dictionary, presenter: BattlePresenter) -> void:
	_session = session
	for id: int in session.state.seen_command_ids:
		_next_command_id = maxi(_next_command_id, id + 1)
	_card_defs = card_defs
	_presenter = presenter
	_sync_selection()


func on_card_pressed(uid: int) -> void:
	if _busy or _session == null or not _session.state.accepts_input():
		return
	if _selected_cards.has(uid):
		_selected_cards.erase(uid)
	else:
		if not _session.state.deck.hand.has(uid):
			return
		var candidate := _selected_cards.duplicate()
		candidate.append(uid)
		if CardSelectionBudget.total_cost(_session.state, _card_defs, candidate) > CardSelectionBudget.energy(_session.state):
			feedback_requested.emit("能量不足")
			return
		_selected_cards.append(uid)
	_sync_selection()


func on_cell_pressed(cell: Vector2i) -> void:
	if _busy or _session == null or not _session.state.accepts_input():
		return
	_selected_cell = cell
	var unit_id := _session.state.board.get_unit_at(cell)
	if unit_id >= 0:
		var unit := _session.state.get_unit(unit_id)
		if unit != null and unit.team == UnitState.Team.ENEMY and unit.is_alive():
			_selected_target_unit = unit_id
			_sync_selection()
		else:
			_selected_target_unit = -1
			_sync_selection()
		return
	_selected_target_unit = -1
	_sync_selection()
	if _selected_cards.is_empty():
		_submit_move(cell)
	else:
		_sync_selection()


func play_selected() -> void:
	if _busy or _session == null or _selected_cards.is_empty():
		return
	if CardSelectionBudget.total_cost(_session.state, _card_defs, _selected_cards) > CardSelectionBudget.energy(_session.state):
		feedback_requested.emit("能量不足")
		return
	_busy = true
	_presenter.set_busy(true)
	var choices: Dictionary = {}
	for uid: int in _selected_cards:
		var request := FormalCardRules.choice_request(
			_session.state, uid, _selected_cards, _card_defs
		)
		if request.is_empty():
			continue
		if Array(request.get("candidates", [])).size() < int(request.get("min_count", 0)):
			feedback_requested.emit("没有可选择的卡牌")
			_busy = false
			_presenter.set_busy(false)
			return
		var popup := CardChoicePopup.new()
		get_parent().add_child(popup)
		popup.setup(_session.state, _card_defs, request)
		popup.show_centered()
		var response: Dictionary = await popup.choice_finished
		if bool(response.get("cancelled", true)):
			_busy = false
			_presenter.set_busy(false)
			return
		choices[uid] = response.get("selected", [])
	var command := _build_play_command(_allocate_command_id())
	command.choices = choices
	_submit(command)


func _build_play_command(command_id: int) -> PlayCardsCommand:
	var command := PlayCardsCommand.new()
	command.command_id = command_id
	command.actor_id = _player_id()
	command.card_uids = _selected_cards.duplicate()
	return _fill_targets(command, _selected_cell, _selected_target_unit)


func _fill_targets(command: PlayCardsCommand, cell: Vector2i, target_unit: int) -> PlayCardsCommand:
	var targets: Array = []
	for uid: int in command.card_uids:
		var card := _session.state.deck.get_card(uid)
		var definition: CardDef = null if card == null else _card_defs.get(card.card_id)
		if definition == null:
			targets.append(null)
			continue
		var rule := definition.get_target_rule(card.upgrade_level)
		if rule == null:
			targets.append(null)
		elif rule is TargetSpec.UnitTarget:
			var unit_target := TargetSpec.UnitTarget.new()
			var unit_rule := rule as TargetSpec.UnitTarget
			if unit_rule.team == TargetSpec.UnitTarget.Team.SELF:
				unit_target.unit_id = command.actor_id
			else:
				unit_target.unit_id = target_unit
			targets.append(unit_target)
		elif rule is TargetSpec.CellTarget:
			var cell_target := TargetSpec.CellTarget.new()
			cell_target.cell = cell
			targets.append(cell_target)
		elif rule is TargetSpec.DirectionTarget:
			var direction_target := TargetSpec.DirectionTarget.new()
			var actor_cell := _session.state.board.get_unit_cell(command.actor_id)
			if cell != Vector2i(-1, -1) and actor_cell != BoardState.INVALID_CELL:
				var delta := cell - actor_cell
				direction_target.direction = Vector2i(signi(delta.x), signi(delta.y))
			targets.append(direction_target)
		else:
			targets.append(null)
	command.targets = targets
	return command


func can_start_drag(uid: int) -> bool:
	if _busy or _session == null or not _session.state.accepts_input() or not _session.state.deck.hand.has(uid):
		return false
	if CardSelectionBudget.total_cost(_session.state, _card_defs, [uid]) > CardSelectionBudget.energy(_session.state):
		feedback_requested.emit("能量不足")
		return false
	return true


## 悬停只预演；拖到盘外、无效目标或取消选择都不消耗卡牌/资源。
func drop_status(uid: int, cell: Vector2i) -> String:
	if _busy or _session == null or not _session.state.accepts_input() or not _session.state.deck.hand.has(uid):
		return "当前无法出牌"
	if CardSelectionBudget.total_cost(_session.state, _card_defs, [uid]) > CardSelectionBudget.energy(_session.state):
		return "能量不足"
	if not _session.state.board.is_inside(cell):
		return "请拖到棋盘上的有效目标"
	var command := PlayCardsCommand.new()
	command.command_id = -1
	command.actor_id = _player_id()
	command.card_uids = [uid]
	_fill_targets(command, cell, _session.state.board.get_unit_at(cell))
	var request := FormalCardRules.choice_request(_session.state, uid, [uid], _card_defs)
	if not request.is_empty():
		var candidates: Array = request.get("candidates", [])
		var count := int(request.get("min_count", 0))
		if candidates.size() < count:
			return "没有可选择的卡牌"
		# 只用于校验；真正释放时仍打开选择弹窗，由玩家确认目标牌。
		command.choices[uid] = candidates.slice(0, count)
	var result := _session.preview(command)
	return "" if result.accepted else _presenter._error_text(result.error_code)


func play_dropped(uid: int, cell: Vector2i) -> void:
	var reason := drop_status(uid, cell)
	if not reason.is_empty():
		feedback_requested.emit(reason)
		return
	_selected_cards = [uid]
	_selected_cell = cell
	_selected_target_unit = _session.state.board.get_unit_at(cell)
	_sync_selection()
	play_selected()


func end_turn() -> void:
	if _busy or _session == null:
		return
	var command := EndTurnCommand.new()
	command.command_id = _allocate_command_id()
	command.actor_id = _player_id()
	_submit(command)


func clear_selection() -> void:
	_selected_cards.clear()
	_selected_target_unit = -1
	_selected_cell = Vector2i(-1, -1)
	_sync_selection()


func _submit_move(cell: Vector2i) -> void:
	var command := MoveCommand.new()
	command.command_id = _allocate_command_id()
	command.actor_id = _player_id()
	command.destination = cell
	_submit(command)


func _submit(command: GameCommand) -> void:
	_busy = true
	_presenter.set_busy(true)
	var result := _session.submit(command)
	if result != null and result.accepted:
		checkpoint_requested.emit(_session.state)
	elif result != null:
		feedback_requested.emit(_presenter._error_text(result.error_code))
	await _presenter.present_result(result)
	if result != null and result.accepted:
		_session.finish_presentation()
		_selected_cards.clear()
		_selected_target_unit = -1
		_selected_cell = Vector2i(-1, -1)
	_busy = false
	_sync_selection()
	_presenter.set_busy(false)
	if _session.state.is_terminal():
		battle_finished.emit(_session.battle_result())


func _player_id() -> int:
	var players := _session.state.alive_player_ids()
	return -1 if players.is_empty() else int(players[0])


func _allocate_command_id() -> int:
	var value := _next_command_id
	_next_command_id += 1
	return value


func _sync_selection() -> void:
	if _presenter != null:
		_presenter.set_selection(_selected_cards, _selected_target_unit)
		_presenter.set_preview(_preview_selection())


func _preview_selection() -> CommandResult:
	if _session == null or _selected_cards.is_empty() or not _session.state.accepts_input():
		return null
	for uid: int in _selected_cards:
		if not FormalCardRules.choice_request(
			_session.state, uid, _selected_cards, _card_defs
		).is_empty():
			return null
	return _session.preview(_build_play_command(-1))
