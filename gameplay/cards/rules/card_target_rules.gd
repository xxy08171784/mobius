class_name CardTargetRules
extends CardRuleSupport

static func validate_target(
	state: BattleState,
	actor_id: int,
	definition: CardDef,
	target: Variant
) -> Dictionary:
	if state == null or definition == null:
		return {"ok": false, "fizzle": false}
	if definition.requires_active_movement and StatusRules.move_locked(state.get_unit(actor_id)):
		return {"ok": false, "fizzle": false}
	if definition.card_id == STARTER_CHARGE:
		var target_id := _target_unit_id(target)
		return {
			"ok": target_id >= 0 and _starter_charge_destination(state, actor_id, target_id) != BoardState.INVALID_CELL,
			"fizzle": false,
		}
	var number := definition.card_number
	if number == 1:
		var cell: Variant = EffectStateAccess.target_cell(_context(actor_id, target))
		if not cell is Vector2i:
			return {"ok": false, "fizzle": false}
		var from := state.board.get_unit_cell(actor_id)
		var to := cell as Vector2i
		if not _straight_line(from, to) or _manhattan(from, to) > definition.attack_range:
			return {"ok": false, "fizzle": false}
		var target_id := state.board.get_unit_at(to)
		var enemy := state.get_unit(target_id)
		var has_enemy := enemy != null and enemy.is_alive() and enemy.team == UnitState.Team.ENEMY
		var items: Variant = state.ground_items.get(to, [])
		return {"ok": has_enemy or (items is Array and not (items as Array).is_empty()), "fizzle": false}
	if number in [15, 17]:
		var target_id := _target_unit_id(target)
		var from := state.board.get_unit_cell(actor_id)
		var to := state.board.get_unit_cell(target_id)
		return {"ok": _straight_line(from, to), "fizzle": false}
	if number == 25:
		var target_id := _target_unit_id(target)
		return {"ok": _adjacent(state, actor_id, target_id), "fizzle": false}
	return {"ok": true, "fizzle": false}


static func validate_range(
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
	var battle := state as BattleState
	var players := battle.alive_player_ids()
	if players.is_empty():
		return {"ok": false}
	var actor_cell := battle.board.get_unit_cell(int(players[0]))
	var target_cell := BoardState.INVALID_CELL
	if rule is TargetSpec.UnitTarget:
		target_cell = battle.board.get_unit_cell(_target_unit_id(target))
	elif rule is TargetSpec.CellTarget:
		var cell: Variant = EffectStateAccess.target_cell(_context(int(players[0]), target))
		if cell is Vector2i:
			target_cell = cell
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
