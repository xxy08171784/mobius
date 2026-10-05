class_name BattleInput
extends Node
## 将鼠标/UI 意图转换为 GameCommand；不直接改 BattleState。

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
	_card_defs = card_defs
	_presenter = presenter
	_sync_selection()


func on_card_pressed(uid: int) -> void:
	if _busy or _session == null or not _session.state.accepts_input():
		return
	if _selected_cards.has(uid):
		_selected_cards.erase(uid)
	else:
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
		return
	if _selected_cards.is_empty():
		_submit_move(cell)
	else:
		_sync_selection()


func play_selected() -> void:
	if _busy or _session == null or _selected_cards.is_empty():
		return
	var command := _build_play_command(_allocate_command_id())
	_submit(command)


func _build_play_command(command_id: int) -> PlayCardsCommand:
	var command := PlayCardsCommand.new()
	command.command_id = command_id
	command.actor_id = _player_id()
	command.card_uids = _selected_cards.duplicate()
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
				unit_target.unit_id = _selected_target_unit
			targets.append(unit_target)
		elif rule is TargetSpec.CellTarget:
			var cell_target := TargetSpec.CellTarget.new()
			cell_target.cell = _selected_cell
			targets.append(cell_target)
		else:
			targets.append(null)
	command.targets = targets
	return command


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
	await _presenter.present_result(result)
	if result != null and result.accepted:
		_session.finish_presentation()
		_selected_cards.clear()
		_selected_target_unit = -1
		_selected_cell = Vector2i(-1, -1)
	_busy = false
	_sync_selection()
	_presenter.set_busy(false)


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
	return _session.preview(_build_play_command(-1))
