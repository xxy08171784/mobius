class_name OffenseCardRules
extends CardRuleSupport

static func resolve(
	state: BattleState,
	rng: Variant,
	actor_id: int,
	card: BattleCardState,
	definition: CardDef,
	target: Variant,
	command: PlayCardsCommand,
	combo_metadata: Dictionary,
	card_defs: Dictionary
) -> Dictionary:
	var choices := _choice_array(command, card.battle_uid)
	match definition.card_id:
		STARTER_CHARGE:
			return _resolve_starter_charge(state, rng, actor_id, card, target)
		STARTER_RELENTLESS:
			return _resolve_starter_relentless(state, rng, actor_id, card, target)
	match definition.card_number:
		13:
			return _resolve_dash_slash(state, rng, actor_id, card, target)
		14:
			return _resolve_kick_backflip(state, rng, actor_id, card, target)
		15:
			return _resolve_hook(state, rng, actor_id, card, target)
		16:
			return _resolve_whirlwind(state, rng, actor_id, card)
		17:
			return _resolve_throwing_knife(state, rng, actor_id, card, target)
		18:
			return _resolve_blood_sword(state, rng, actor_id, card, target)
		19:
			return _resolve_demon_blade(state, rng, actor_id, card, target)
		20:
			return _resolve_damage_status(state, rng, actor_id, card, target, 12.0, StatusRules.STUN)
		21:
			var amount := 6.0 + 3.0 * float(maxi(0, command.card_uids.size() - 1))
			return _damage(state, rng, actor_id, card, target, amount)
		22:
			var unit := state.get_unit(_target_unit_id(target))
			var amount := 18.0 if StatusRules.has_negative_status(unit) else 6.0
			return _damage(state, rng, actor_id, card, target, amount)
		23:
			var result := _damage(state, rng, actor_id, card, target, 15.0)
			if bool(result.get("ok", false)):
				var out := result["state_out"] as BattleState
				out.scheduled_effects.append({
					"round": out.round_index + 1,
					"kind": &"draw",
					"count": 1,
					"source_unit_id": actor_id,
				})
			return result
		25:
			return _damage(state, rng, actor_id, card, target, 13.0)
		26:
			return _success(state, rng)
		27:
			return _resolve_technique_synergy(
				state, rng, actor_id, card, target, command, card_defs
			)
		30:
			var amount := float(_enemies_within(state, actor_id, 2).size() * 5)
			return _damage(state, rng, actor_id, card, target, amount)
		31:
			return _resolve_damage_status(state, rng, actor_id, card, target, 9.0, StatusRules.SLOW)
		33:
			return _resolve_overflow(state, rng, actor_id, card, target)
		35:
			return _resolve_rooted_attack(state, rng, actor_id, card, target)
		_:
			return {"handled": false}


static func _resolve_dash_slash(
	state: BattleState, rng: Variant, actor_id: int, card: BattleCardState, target: Variant
) -> Dictionary:
	var direction: Variant = EffectStateAccess.target_direction(_context(actor_id, target))
	if not direction is Vector2i or (direction as Vector2i) == Vector2i.ZERO:
		return _failure(state, rng)
	var dir := direction as Vector2i
	var board := state.board
	var from := board.get_unit_cell(actor_id)
	var cur := from
	var moved := 0
	var hit_id := -1
	for _step in range(3):
		var next := cur + dir
		if not board.is_inside(next) or not board.is_traversable(next):
			break
		if board.is_occupied(next):
			var candidate := board.get_unit_at(next)
			var unit := state.get_unit(candidate)
			if unit != null and unit.team == UnitState.Team.ENEMY and unit.is_alive():
				hit_id = candidate
			break
		cur = next
		moved += 1
	var events := EventBatch.new()
	if cur != from:
		board.move_unit(actor_id, cur)
		events.push_back(EffectEvent.create(
			EffectStateAccess.allocate_event_seq(state),
			&"unit_moved",
			actor_id,
			actor_id,
			{"cell": from},
			{"cell": cur},
			{"path": [from, cur], "move_points": moved}
		))
	if hit_id < 0:
		return _success(state, rng, events)
	var amount := 10.0 + float(moved * 5)
	return _damage(state, rng, actor_id, card, hit_id, amount, events)

static func _resolve_starter_charge(
	state: BattleState, rng: Variant, actor_id: int, card: BattleCardState, target: Variant
) -> Dictionary:
	var target_id := _target_unit_id(target)
	if target_id < 0:
		return _failure(state, rng)
	var destination := _starter_charge_destination(state, actor_id, target_id)
	if destination == BoardState.INVALID_CELL:
		return _failure(state, rng)
	var board := state.board
	var from := board.get_unit_cell(actor_id)
	var events := EventBatch.new()
	if destination != from:
		var displacement := Displacement.move(board, actor_id, destination, 2)
		if not displacement.moved:
			return _failure(state, rng)
		events.push_back(EffectEvent.create(
			EffectStateAccess.allocate_event_seq(state),
			&"unit_moved",
			actor_id,
			actor_id,
			{"cell": displacement.from_cell},
			{"cell": displacement.to_cell},
			{
				"path": displacement.path.duplicate(),
				"move_points": maxi(0, displacement.path.size() - 1),
			}
		))
	return _damage(state, rng, actor_id, card, target, 5.0, events)

static func _resolve_starter_relentless(
	state: BattleState, rng: Variant, actor_id: int, card: BattleCardState, target: Variant
) -> Dictionary:
	var used_once := bool(card.runtime_data.get("relentless_used_once", false))
	var amount := 11.0 if used_once else 6.0
	var result := _damage(state, rng, actor_id, card, target, amount)
	if bool(result.get("ok", false)):
		var out := result["state_out"] as BattleState
		var out_card := out.deck.get_card(card.battle_uid)
		if out_card != null:
			out_card.runtime_data["relentless_used_once"] = true
	return result

static func _resolve_kick_backflip(
	state: BattleState, rng: Variant, actor_id: int, card: BattleCardState, target: Variant
) -> Dictionary:
	var target_id := _target_unit_id(target)
	var target_cell := state.board.get_unit_cell(target_id)
	var source_cell := state.board.get_unit_cell(actor_id)
	var result := _damage(state, rng, actor_id, card, target, 9.0)
	if not bool(result.get("ok", false)):
		return result
	var out := result["state_out"] as BattleState
	var events := result["events"] as EventBatch
	var target_unit := out.get_unit(target_id)
	if target_unit != null and target_unit.is_alive():
		var pushed := _apply(
			out, result["rng_out"], actor_id, card.battle_uid, target,
			[{"type_key": &"push", "params": {"steps": 1, "direction_mode": &"away_from_source"}}],
			events
		)
		if not bool(pushed.get("ok", false)):
			return pushed
		out = pushed["state_out"]
		result = pushed
	var retreat := Vector2i(signi(source_cell.x - target_cell.x), signi(source_cell.y - target_cell.y))
	if retreat != Vector2i.ZERO:
		var self_push := _apply(
			out, result["rng_out"], actor_id, card.battle_uid, actor_id,
			[{"type_key": &"push", "direction": retreat, "params": {"steps": 1}}],
			result["events"]
		)
		if bool(self_push.get("ok", false)):
			return self_push
	return result

static func _resolve_hook(
	state: BattleState, rng: Variant, actor_id: int, card: BattleCardState, target: Variant
) -> Dictionary:
	var target_id := _target_unit_id(target)
	var before := state.board.get_unit_cell(target_id)
	var source := state.board.get_unit_cell(actor_id)
	var direction := Vector2i(signi(source.x - before.x), signi(source.y - before.y))
	var pulled := _apply(
		state, rng, actor_id, card.battle_uid, target,
		[{"type_key": &"push", "direction": direction, "params": {"steps": 2}}]
	)
	if not bool(pulled.get("ok", false)):
		return pulled
	var out := pulled["state_out"] as BattleState
	var after := out.board.get_unit_cell(target_id)
	var moved := maxi(absi(after.x - before.x), absi(after.y - before.y))
	var amount := 5.0 * (1.0 + 0.12 * float(moved))
	return _damage(
		out, pulled["rng_out"], actor_id, card, target, amount, pulled["events"]
	)

static func _resolve_whirlwind(
	state: BattleState, rng: Variant, actor_id: int, card: BattleCardState
) -> Dictionary:
	var hits := _enemies_adjacent(state, actor_id)
	var effects: Array = []
	for enemy_id: int in hits:
		effects.append({
			"type_key": &"damage",
			"target": enemy_id,
			"params": {"amount": _damage_amount(card, state.round_index, 5.0)},
		})
	if not hits.is_empty():
		effects.append({
			"type_key": &"block",
			"params": {"amount": hits.size() * 2 + card.block_modifier, "target_mode": &"source"},
		})
	return _apply(state, rng, actor_id, card.battle_uid, null, effects)

static func _resolve_throwing_knife(
	state: BattleState, rng: Variant, actor_id: int, card: BattleCardState, target: Variant
) -> Dictionary:
	return _apply(
		state, rng, actor_id, card.battle_uid, target,
		[
			{"type_key": &"damage", "params": {"amount": _damage_amount(card, state.round_index, 8.0)}},
			{"type_key": &"apply_status", "params": {
				"status_id": StatusRules.KNIFE_MARK, "stacks": 1, "persistent": true
			}},
		]
	)

static func _resolve_blood_sword(
	state: BattleState, rng: Variant, actor_id: int, card: BattleCardState, target: Variant
) -> Dictionary:
	var target_id := _target_unit_id(target)
	var result := _damage(state, rng, actor_id, card, target, 9.0)
	if not bool(result.get("ok", false)):
		return result
	var out := result["state_out"] as BattleState
	var target_unit := out.get_unit(target_id)
	if target_unit != null and target_unit.is_alive():
		return result
	var actor := out.get_unit(actor_id)
	if actor == null:
		return result
	actor.max_hp += 3
	out.run_changes["max_hp_delta"] = int(out.run_changes.get("max_hp_delta", 0)) + 3
	return _apply(
		out, result["rng_out"], actor_id, card.battle_uid, null,
		[{"type_key": &"heal", "params": {"amount": 3, "target_mode": &"source"}}],
		result["events"]
	)

static func _resolve_demon_blade(
	state: BattleState, rng: Variant, actor_id: int, card: BattleCardState, target: Variant
) -> Dictionary:
	var target_id := _target_unit_id(target)
	var before := state.get_unit(target_id)
	var hp_before := before.hp if before != null else 0
	var result := _damage(state, rng, actor_id, card, target, 6.0)
	if bool(result.get("ok", false)):
		var after := (result["state_out"] as BattleState).get_unit(target_id)
		if after != null and after.hp < hp_before:
			var out_card := (result["state_out"] as BattleState).deck.get_card(card.battle_uid)
			if out_card != null:
				out_card.damage_modifier += 4
	return result

static func _resolve_damage_status(
	state: BattleState,
	rng: Variant,
	actor_id: int,
	card: BattleCardState,
	target: Variant,
	amount: float,
	status_id: StringName
) -> Dictionary:
	return _apply(
		state, rng, actor_id, card.battle_uid, target,
		[
			{"type_key": &"damage", "params": {"amount": _damage_amount(card, state.round_index, amount)}},
			{"type_key": &"apply_status", "params": {"status_id": status_id, "stacks": 1, "duration": 1}},
		]
	)

static func _resolve_technique_synergy(
	state: BattleState,
	rng: Variant,
	actor_id: int,
	card: BattleCardState,
	target: Variant,
	command: PlayCardsCommand,
	card_defs: Dictionary
) -> Dictionary:
	var technique_value := 0.0
	for index: int in range(command.card_uids.size()):
		var uid := command.card_uids[index]
		if uid == card.battle_uid:
			continue
		var other := state.deck.get_card(uid)
		var other_def := _def_for_card(card_defs, other)
		if other_def != null and other_def.card_category == CardDef.CardCategory.TECHNIQUE:
			var other_target: Variant = command.targets[index] if index < command.targets.size() else null
			technique_value = _estimate_technique_damage(state, other, other_def, other_target)
			break
	return _damage(state, rng, actor_id, card, target, technique_value * 1.5)

static func _resolve_overflow(
	state: BattleState, rng: Variant, actor_id: int, card: BattleCardState, target: Variant
) -> Dictionary:
	var target_id := _target_unit_id(target)
	var target_unit := state.get_unit(target_id)
	if target_unit == null:
		return _failure(state, rng)
	var hp_before := target_unit.hp
	var target_cell := state.board.get_unit_cell(target_id)
	var result := _damage(state, rng, actor_id, card, target, 7.0)
	if not bool(result.get("ok", false)):
		return result
	var out := result["state_out"] as BattleState
	var after := out.get_unit(target_id)
	if after != null and after.is_alive():
		return result
	var overflow := 0
	var batch := result["events"] as EventBatch
	for event: GameEvent in batch.events:
		if event is EffectEvent and event.type_key == &"damage" and event.target_id == target_id:
			overflow = maxi(0, int((event as EffectEvent).payload.get("hp_damage", 0)) - hp_before)
	if overflow <= 0:
		return result
	var effects: Array = []
	for enemy_id: int in out.alive_enemy_ids():
		if enemy_id == target_id:
			continue
		var cell := out.board.get_unit_cell(enemy_id)
		if maxi(absi(cell.x - target_cell.x), absi(cell.y - target_cell.y)) <= 1:
			effects.append({"type_key": &"damage", "target": enemy_id, "params": {"amount": overflow}})
	return _apply(out, result["rng_out"], actor_id, card.battle_uid, null, effects, batch)

static func _resolve_rooted_attack(
	state: BattleState, rng: Variant, actor_id: int, card: BattleCardState, target: Variant
) -> Dictionary:
	var actor := state.get_unit(actor_id)
	if actor == null:
		return _failure(state, rng)
	var move := maxi(0, actor.get_resource(TurnSystem.MOVE_RESOURCE))
	actor.set_resource(TurnSystem.MOVE_RESOURCE, 0)
	return _damage(state, rng, actor_id, card, target, float(move * 4))
