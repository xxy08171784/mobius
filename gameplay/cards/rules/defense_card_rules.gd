class_name DefenseCardRules
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
	match definition.card_number:
		37:
			var amount := int(card.runtime_data.get("stacked_block", 0))
			card.runtime_data["stacked_block"] = 0
			return _block(state, rng, actor_id, card, float(amount))
		38:
			return _resolve_hold_back(state, rng, actor_id, card, definition)
		39:
			var amount := definition.get_rule_value("block", card.upgrade_level, 5) + definition.get_rule_value("per_card", card.upgrade_level, 3) * float(combo_metadata.get("other_play_count", 0))
			return _block(state, rng, actor_id, card, amount)
		41:
			var has_technique := _hand_has_category(state.deck, card_defs, CardDef.CardCategory.TECHNIQUE)
			return _block(state, rng, actor_id, card, definition.get_rule_value("conditional_block", card.upgrade_level, 12) if has_technique else definition.get_rule_value("block", card.upgrade_level, 5))
		43:
			var result := _block(state, rng, actor_id, card, definition.get_rule_value("block", card.upgrade_level, 9))
			if bool(result.get("ok", false)):
				var out := result["state_out"] as BattleState
				out.scheduled_effects.append({
					"round": out.round_index + 1,
					"kind": &"block",
					"amount": int(definition.get_rule_value("block", card.upgrade_level, 9)),
					"source_unit_id": actor_id,
				})
			return result
		44:
			return _resolve_stress_block(state, rng, actor_id, card, definition, choices)
		45:
			var amount := float(_enemies_within(state, actor_id, 2).size()) * definition.get_rule_value("per_enemy", card.upgrade_level, 8)
			return _block(state, rng, actor_id, card, amount)
		46:
			var amount := int(card.runtime_data.get("heal_charge", 0))
			return _apply(
				state, rng, actor_id, card.battle_uid, null,
				[{"type_key": &"heal", "params": {"amount": amount, "target_mode": &"source"}}]
			)
		47:
			var result := _block(state, rng, actor_id, card, definition.get_rule_value("block", card.upgrade_level, 8))
			if not bool(result.get("ok", false)):
				return result
			var out := result["state_out"] as BattleState
			if not _enemies_adjacent(out, actor_id).is_empty():
				return _apply(
					out, result["rng_out"], actor_id, card.battle_uid, null,
					[{"type_key": &"resource", "params": {
						"key": &"courage", "operation": &"add", "amount": int(definition.get_rule_value("courage", card.upgrade_level, 2)), "target_mode": &"source"
					}}],
					result["events"]
				)
			return result
		48:
			return _resolve_rooted_defense(state, rng, actor_id, card, definition)
		49:
			return _success(state, rng)
		_:
			return {"handled": false}


static func _resolve_hold_back(
	state: BattleState, rng: Variant, actor_id: int, card: BattleCardState, definition: CardDef
) -> Dictionary:
	var result := _block(state, rng, actor_id, card, definition.get_rule_value("block", card.upgrade_level, 5))
	if not bool(result.get("ok", false)):
		return result
	var out := result["state_out"] as BattleState
	var card_system := CardSystem.new()
	var draw_result := card_system.draw_cards(out.deck, 1, _battle_rng(result["rng_out"]))
	var drawn: Array = draw_result.get("cards", [])
	if not drawn.is_empty():
		var drawn_card := out.deck.get_card(int(drawn[0]))
		if drawn_card != null:
			drawn_card.upgrade_level = 1
	return result

static func _resolve_stress_block(
	state: BattleState, rng: Variant, actor_id: int, card: BattleCardState, definition: CardDef, choices: Array[int]
) -> Dictionary:
	if choices.size() != 1 or not state.deck.move_card(choices[0], DeckState.ZONE_HAND, DeckState.ZONE_DISCARD):
		return _failure(state, rng)
	return _block(state, rng, actor_id, card, definition.get_rule_value("block", card.upgrade_level, 10))

static func _resolve_rooted_defense(
	state: BattleState, rng: Variant, actor_id: int, card: BattleCardState, definition: CardDef
) -> Dictionary:
	var actor := state.get_unit(actor_id)
	if actor == null:
		return _failure(state, rng)
	var move := maxi(0, actor.get_resource(TurnSystem.MOVE_RESOURCE))
	actor.set_resource(TurnSystem.MOVE_RESOURCE, 0)
	return _block(state, rng, actor_id, card, float(move) * definition.get_rule_value("per_move", card.upgrade_level, 3))
