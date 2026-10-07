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
	if definition.requires_active_movement and StatusRules.move_locked(state.get_unit(actor_id)):
		return _failure(state, rng)
	var choices := _choice_array(command, card.battle_uid)
	match definition.card_id:
		STARTER_CHARGE:
			return _resolve_starter_charge(state, rng, actor_id, card, definition, target)
		STARTER_RELENTLESS:
			return _resolve_starter_relentless(state, rng, actor_id, card, definition, target)
	match definition.card_number:
		13:
			return _resolve_dash_slash(state, rng, actor_id, card, definition, target)
		14:
			return _resolve_kick_backflip(state, rng, actor_id, card, definition, target)
		15:
			return _resolve_hook(state, rng, actor_id, card, definition, target)
		16:
			return _resolve_whirlwind(state, rng, actor_id, card, definition)
		17:
			return _resolve_throwing_knife(state, rng, actor_id, card, definition, target)
		18:
			return _resolve_blood_sword(state, rng, actor_id, card, definition, target)
		19:
			return _resolve_demon_blade(state, rng, actor_id, card, definition, target)
		20:
			return _resolve_damage_status(state, rng, actor_id, card, definition, target, definition.get_rule_value("damage", card.upgrade_level, 12), StatusRules.STUN)
		21:
			var amount := definition.get_rule_value("damage", card.upgrade_level, 6) + definition.get_rule_value("per_card", card.upgrade_level, 3) * float(combo_metadata.get("other_play_count", 0))
			return _damage(state, rng, actor_id, card, target, amount)
		22:
			var unit := state.get_unit(_target_unit_id(target))
			var amount := definition.get_rule_value("damage", card.upgrade_level, 6) * (2.0 if StatusRules.has_negative_status(unit) else 1.0)
			return _damage(state, rng, actor_id, card, target, amount)
		23:
			var result := _damage(state, rng, actor_id, card, target, definition.get_rule_value("damage", card.upgrade_level, 10))
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
			return _damage(state, rng, actor_id, card, target, definition.get_rule_value("damage", card.upgrade_level, 12))
		26:
			return _success(state, rng)
		27:
			return _resolve_technique_synergy(
				state, rng, actor_id, card, definition, target, command, card_defs
			)
		30:
			var amount := float(_enemies_within(state, actor_id, 2).size()) * definition.get_rule_value("per_enemy", card.upgrade_level, 5)
			return _damage(state, rng, actor_id, card, target, amount)
		31:
			return _resolve_damage_status(state, rng, actor_id, card, definition, target, definition.get_rule_value("damage", card.upgrade_level, 9), StatusRules.SLOW)
		33:
			return _resolve_overflow(state, rng, actor_id, card, definition, target)
		35:
			return _resolve_rooted_attack(state, rng, actor_id, card, definition, target)
		_:
			return {"handled": false}


static func _resolve_dash_slash(
	state: BattleState, rng: Variant, actor_id: int, card: BattleCardState, definition: CardDef, target: Variant
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
	var amount := definition.get_rule_value("damage", card.upgrade_level, 10) + float(moved) * definition.get_rule_value("per_step", card.upgrade_level, 4)
	return _damage(state, rng, actor_id, card, hit_id, amount, events)

static func _resolve_starter_charge(
	state: BattleState, rng: Variant, actor_id: int, card: BattleCardState, definition: CardDef, target: Variant
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
	return _damage(state, rng, actor_id, card, target, definition.get_rule_value("damage", card.upgrade_level, 5), events)

static func _resolve_starter_relentless(
	state: BattleState, rng: Variant, actor_id: int, card: BattleCardState, definition: CardDef, target: Variant
) -> Dictionary:
	var used_once := bool(card.runtime_data.get("relentless_used_once", false))
	var amount := definition.get_rule_value("repeat_damage", card.upgrade_level, 11) if used_once else definition.get_rule_value("damage", card.upgrade_level, 6)
	var result := _damage(state, rng, actor_id, card, target, amount)
	if bool(result.get("ok", false)):
		var out := result["state_out"] as BattleState
		var out_card := out.deck.get_card(card.battle_uid)
		if out_card != null:
			out_card.runtime_data["relentless_used_once"] = true
	return result

static func _resolve_kick_backflip(
	state: BattleState, rng: Variant, actor_id: int, card: BattleCardState, definition: CardDef, target: Variant
) -> Dictionary:
	var target_id := _target_unit_id(target)
	var target_cell := state.board.get_unit_cell(target_id)
	var source_cell := state.board.get_unit_cell(actor_id)
	var result := _damage(state, rng, actor_id, card, target, definition.get_rule_value("damage", card.upgrade_level, 9))
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
	state: BattleState, rng: Variant, actor_id: int, card: BattleCardState, definition: CardDef, target: Variant
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
	var amount := definition.get_rule_value("damage", card.upgrade_level, 6) + definition.get_rule_value("per_step", card.upgrade_level, 2) * float(moved)
	return _damage(
		out, pulled["rng_out"], actor_id, card, target, amount, pulled["events"]
	)

static func _resolve_whirlwind(
	state: BattleState, rng: Variant, actor_id: int, card: BattleCardState, definition: CardDef
) -> Dictionary:
	var hits := _enemies_adjacent(state, actor_id)
	var effects: Array = []
	for enemy_id: int in hits:
		effects.append({
			"type_key": &"damage",
			"target": enemy_id,
			"params": {"amount": _damage_amount(card, state.round_index, definition.get_rule_value("damage", card.upgrade_level, 5))},
		})
	if not hits.is_empty():
		effects.append({
			"type_key": &"block",
			"params": {"amount": hits.size() * definition.get_rule_value("per_enemy_block", card.upgrade_level, 2) + card.block_modifier, "target_mode": &"source"},
		})
	return _apply(state, rng, actor_id, card.battle_uid, null, effects)

static func _resolve_throwing_knife(
	state: BattleState, rng: Variant, actor_id: int, card: BattleCardState, definition: CardDef, target: Variant
) -> Dictionary:
	return _apply(
		state, rng, actor_id, card.battle_uid, target,
		[
			{"type_key": &"damage", "params": {"amount": _damage_amount(card, state.round_index, definition.get_rule_value("damage", card.upgrade_level, 7))}},
			{"type_key": &"apply_status", "params": {
				"status_id": StatusRules.POISON, "stacks": int(definition.get_rule_value("poison", card.upgrade_level, 2)), "persistent": true
			}},
		]
	)

static func _resolve_blood_sword(
	state: BattleState, rng: Variant, actor_id: int, card: BattleCardState, definition: CardDef, target: Variant
) -> Dictionary:
	var target_id := _target_unit_id(target)
	var result := _damage(state, rng, actor_id, card, target, definition.get_rule_value("damage", card.upgrade_level, 9))
	if not bool(result.get("ok", false)):
		return result
	var out := result["state_out"] as BattleState
	var target_unit := out.get_unit(target_id)
	if target_unit != null and target_unit.is_alive():
		return result
	var actor := out.get_unit(actor_id)
	if actor == null:
		return result
	if int(out.run_changes.get("max_hp_delta", 0)) >= 3:
		return result
	actor.max_hp += 3
	out.run_changes["max_hp_delta"] = int(out.run_changes.get("max_hp_delta", 0)) + 3
	return _apply(
		out, result["rng_out"], actor_id, card.battle_uid, null,
		[{"type_key": &"heal", "params": {"amount": 3, "target_mode": &"source"}}],
		result["events"]
	)

static func _resolve_demon_blade(
	state: BattleState, rng: Variant, actor_id: int, card: BattleCardState, definition: CardDef, target: Variant
) -> Dictionary:
	var target_id := _target_unit_id(target)
	var before := state.get_unit(target_id)
	var hp_before := before.hp if before != null else 0
	var result := _damage(state, rng, actor_id, card, target, definition.get_rule_value("damage", card.upgrade_level, 6))
	if bool(result.get("ok", false)):
		var after := (result["state_out"] as BattleState).get_unit(target_id)
		if after != null and after.hp < hp_before:
			var out_card := (result["state_out"] as BattleState).deck.get_card(card.battle_uid)
			if out_card != null:
				var growth := int(out_card.runtime_data.get("demon_growth", 0))
				var gain := mini(int(definition.get_rule_value("growth", card.upgrade_level, 2)), maxi(0, int(definition.get_rule_value("growth_cap", card.upgrade_level, 6)) - growth))
				out_card.damage_modifier += gain
				out_card.runtime_data["demon_growth"] = growth + gain
	return result

static func _resolve_damage_status(
	state: BattleState,
	rng: Variant,
	actor_id: int,
	card: BattleCardState, definition: CardDef,
	target: Variant,
	amount: float,
	status_id: StringName
) -> Dictionary:
	return _apply(
		state, rng, actor_id, card.battle_uid, target,
		[
			{"type_key": &"damage", "params": {"amount": _damage_amount(card, state.round_index, amount)}},
			{"type_key": &"apply_status", "params": {"status_id": status_id, "stacks": int(definition.get_rule_value("status_stacks", card.upgrade_level, 1)), "duration": 1}},
		]
	)

static func _resolve_technique_synergy(
	state: BattleState,
	rng: Variant,
	actor_id: int,
	card: BattleCardState, definition: CardDef,
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
	return _damage(state, rng, actor_id, card, target, technique_value * definition.get_rule_value("multiplier", card.upgrade_level, 1.0))

static func _resolve_overflow(
	state: BattleState, rng: Variant, actor_id: int, card: BattleCardState, definition: CardDef, target: Variant
) -> Dictionary:
	var target_id := _target_unit_id(target)
	var target_unit := state.get_unit(target_id)
	if target_unit == null:
		return _failure(state, rng)
	var hp_before := target_unit.hp
	var target_cell := state.board.get_unit_cell(target_id)
	var result := _damage(state, rng, actor_id, card, target, definition.get_rule_value("damage", card.upgrade_level, 7))
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
			effects.append({"type_key": &"damage", "target": enemy_id, "params": {"amount": overflow, "ignore_status_modifiers": true}})
	return _apply(out, result["rng_out"], actor_id, card.battle_uid, null, effects, batch)

static func _resolve_rooted_attack(
	state: BattleState, rng: Variant, actor_id: int, card: BattleCardState, definition: CardDef, target: Variant
) -> Dictionary:
	var actor := state.get_unit(actor_id)
	if actor == null:
		return _failure(state, rng)
	var move := maxi(0, actor.get_resource(TurnSystem.MOVE_RESOURCE))
	actor.set_resource(TurnSystem.MOVE_RESOURCE, 0)
	return _damage(state, rng, actor_id, card, target, float(move) * definition.get_rule_value("per_move", card.upgrade_level, 4))
