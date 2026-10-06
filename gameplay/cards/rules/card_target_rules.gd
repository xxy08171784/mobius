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
		if not _straight_line(from, to) or _manhattan(from, to) > 2:
			return {"ok": false, "fizzle": false}
		var target_id := state.board.get_unit_at(to)
		var has_knife := target_id >= 0 and _knife_count(state.get_unit(target_id)) > 0
		var items: Variant = state.ground_items.get(to, [])
		return {"ok": has_knife or (items is Array and not (items as Array).is_empty()), "fizzle": false}
	if number in [15, 17]:
		var target_id := _target_unit_id(target)
		var from := state.board.get_unit_cell(actor_id)
		var to := state.board.get_unit_cell(target_id)
		return {"ok": _straight_line(from, to), "fizzle": false}
	if number == 25:
		var target_id := _target_unit_id(target)
		return {"ok": _adjacent(state, actor_id, target_id), "fizzle": false}
	return {"ok": true, "fizzle": false}
