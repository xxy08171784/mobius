class_name BoardView
extends GridContainer
## Phase 4 占位棋盘：按钮网格只投影 BattleState，不修改规则状态。

signal cell_pressed(cell: Vector2i)

var _buttons: Dictionary = {}
var _last_state: BattleState = null


func render_state(state: BattleState, selected_target_unit: int = -1, busy: bool = false) -> void:
	if state == null:
		return
	_last_state = state
	if _buttons.size() != state.board.cols * state.board.rows:
		_rebuild(state.board)

	var reachable: Array[Vector2i] = []
	var players := state.alive_player_ids()
	if state.accepts_input() and not players.is_empty():
		var player_id := int(players[0])
		var from_cell := state.board.get_unit_cell(player_id)
		var budget := state.get_unit(player_id).get_resource(TurnSystem.MOVE_RESOURCE)
		reachable = BoardQuery.reachable_cells(state.board, from_cell, budget)

	var intent_cells: Dictionary = {}
	for enemy_id: int in state.enemy_intents:
		var intent: IntentState = state.enemy_intents[enemy_id]
		if intent == null:
			continue
		for cell: Vector2i in intent.affected_cells:
			intent_cells[cell] = true

	for y: int in range(state.board.rows):
		for x: int in range(state.board.cols):
			var cell := Vector2i(x, y)
			var button := _buttons[cell] as Button
			var text_parts: Array[String] = []
			if intent_cells.has(cell):
				text_parts.append("[意图]")
			if reachable.has(cell):
				text_parts.append("[可移动]")

			var unit_id := state.board.get_unit_at(cell)
			if unit_id >= 0:
				var unit := state.get_unit(unit_id)
				if unit_id == selected_target_unit:
					text_parts.append("[目标]")
				if unit != null and unit.is_player():
					text_parts.append("玩家")
				elif unit != null:
					text_parts.append("敌人")
				if unit != null:
					text_parts.append("HP %d/%d" % [unit.hp, unit.max_hp])
					if unit.block > 0:
						text_parts.append("盾 %d" % unit.block)
					var status_text := _status_text(unit)
					if not status_text.is_empty():
						text_parts.append(status_text)
			else:
				var cell_state := state.board.get_cell(cell)
				if cell_state != null and not cell_state.traversable:
					text_parts.append("墙")
				else:
					text_parts.append("%d,%d" % [x, y])

			button.text = "\n".join(text_parts)
			button.disabled = busy or state.is_terminal()
			button.tooltip_text = "棋盘格 (%d, %d)" % [x, y]


func pulse_unit(unit_id: int) -> void:
	if _last_state == null or _last_state.board == null:
		return
	var cell := _last_state.board.get_unit_cell(unit_id)
	if cell == BoardState.INVALID_CELL or not _buttons.has(cell):
		return
	var button := _buttons[cell] as Button
	button.pivot_offset = button.size * 0.5
	button.scale = Vector2(0.88, 0.88)
	var tween := create_tween()
	tween.tween_property(button, "scale", Vector2.ONE, 0.12)


func _status_text(unit: UnitState) -> String:
	if unit == null or unit.statuses.is_empty():
		return ""
	var parts: Array[String] = []
	for instance_id: int in unit.status_ids():
		var status := unit.get_status(instance_id)
		if status == null or status.is_expired():
			continue
		match status.status_id:
			StatusRules.BLEED:
				parts.append("流血%d(%d)" % [status.stacks, status.duration])
			StatusRules.VULNERABLE:
				parts.append("易伤(%d)" % status.duration)
			StatusRules.FOCUS:
				parts.append("专注%d(%d)" % [status.stacks, status.duration])
			_:
				parts.append(String(status.status_id))
	return " ".join(parts)


func _rebuild(board: BoardState) -> void:
	for child: Node in get_children():
		child.free()
	_buttons.clear()
	columns = board.cols
	for y: int in range(board.rows):
		for x: int in range(board.cols):
			var cell := Vector2i(x, y)
			var button := Button.new()
			button.custom_minimum_size = Vector2(72, 64)
			button.focus_mode = Control.FOCUS_NONE
			button.pressed.connect(_on_button_pressed.bind(button))
			button.set_meta(&"cell", cell)
			add_child(button)
			_buttons[cell] = button


func _on_button_pressed(button: Button) -> void:
	var cell: Vector2i = button.get_meta(&"cell", Vector2i(-1, -1))
	if cell != Vector2i(-1, -1):
		cell_pressed.emit(cell)
