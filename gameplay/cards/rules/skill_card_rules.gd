class_name SkillCardRules
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
		1:
			return _resolve_lasso(state, rng, actor_id, target)
		2:
			return _resolve_requisition(state, rng, card, choices)
		3:
			return _resolve_cautious(state, rng, actor_id, card)
		4:
			return _resolve_generate_fists(state, rng)
		5:
			return _resolve_technique_insight(state, rng, choices)
		6:
			return _resolve_dismiss(state, rng, actor_id, card, choices)
		9:
			return _resolve_inspire(state, rng, actor_id)
		10:
			return _apply(
				state, rng, actor_id, card.battle_uid, target,
				[{"type_key": &"push", "params": {"steps": 2, "direction_mode": &"away_from_source"}}]
			)
		11:
			return _resolve_area_damage(state, rng, actor_id, card, 2, 12.0, false)
		12:
			return _resolve_copy(state, rng, choices)
		_:
			return {"handled": false}


static func _resolve_lasso(state: BattleState, rng: Variant, actor_id: int, target: Variant) -> Dictionary:
	var cell: Variant = EffectStateAccess.target_cell(_context(actor_id, target))
	if not cell is Vector2i:
		return _failure(state, rng)
	var target_cell := cell as Vector2i
	var unit_id := state.board.get_unit_at(target_cell)
	if unit_id >= 0:
		var target_unit := state.get_unit(unit_id)
		var knives := _remove_knives(target_unit)
		if knives <= 0:
			return _failure(state, rng)
		return _apply(
			state, rng, actor_id, -1, unit_id,
			[{"type_key": &"damage", "params": {"amount": knives * 6}}]
		)
	var raw_items: Variant = state.ground_items.get(target_cell, [])
	if not raw_items is Array or (raw_items as Array).is_empty():
		return _failure(state, rng)
	for value: Variant in raw_items:
		state.collected_items.append(StringName(String(value)))
	state.ground_items.erase(target_cell)
	return _success(state, rng)

static func _resolve_requisition(
	state: BattleState, rng: Variant, _source: BattleCardState, choices: Array[int]
) -> Dictionary:
	if choices.size() != 1:
		return _failure(state, rng)
	var picked := state.deck.get_card(choices[0])
	if picked == null or not state.deck.move_card(picked.battle_uid, DeckState.ZONE_DRAW, DeckState.ZONE_HAND):
		return _failure(state, rng)
	picked.runtime_data["turn_damage_bonus"] = 6
	picked.runtime_data["turn_damage_bonus_round"] = state.round_index
	return _success(state, rng)

static func _resolve_cautious(
	state: BattleState, rng: Variant, actor_id: int, card: BattleCardState
) -> Dictionary:
	var actor := state.get_unit(actor_id)
	if actor == null:
		return _failure(state, rng)
	var courage := maxi(0, actor.get_resource(&"courage"))
	actor.set_resource(&"courage", 0)
	return _block(state, rng, actor_id, card, float(courage * 2))

static func _resolve_generate_fists(state: BattleState, rng: Variant) -> Dictionary:
	var card_system := CardSystem.new()
	for _i in range(3):
		var uid := _allocate_card_uid(state.deck)
		var generated := card_system.create_generated_card(TOKEN_FIST, uid)
		state.deck.add_card(generated, DeckState.ZONE_HAND)
	return _success(state, rng)

static func _resolve_technique_insight(
	state: BattleState, rng: Variant, choices: Array[int]
) -> Dictionary:
	if choices.size() != 1:
		return _failure(state, rng)
	var picked := state.deck.get_card(choices[0])
	if picked == null:
		return _failure(state, rng)
	picked.cost_modifier -= 1
	return _success(state, rng)

static func _resolve_dismiss(
	state: BattleState, rng: Variant, actor_id: int, card: BattleCardState, choices: Array[int]
) -> Dictionary:
	if choices.size() > 2:
		return _failure(state, rng)
	for uid: int in choices:
		if not state.deck.move_card(uid, DeckState.ZONE_HAND, DeckState.ZONE_EXHAUST):
			return _failure(state, rng)
	return _block(state, rng, actor_id, card, float(choices.size() * 8))

static func _resolve_inspire(state: BattleState, rng: Variant, actor_id: int) -> Dictionary:
	var actor := state.get_unit(actor_id)
	if actor == null:
		return _failure(state, rng)
	var amount := 7 if actor.get_resource(&"courage") <= 0 else 3
	return _apply(
		state, rng, actor_id, -1, null,
		[{"type_key": &"resource", "params": {
			"key": &"courage", "operation": &"add", "amount": amount, "target_mode": &"source"
		}}]
	)

static func _resolve_copy(state: BattleState, rng: Variant, choices: Array[int]) -> Dictionary:
	if choices.size() != 1:
		return _failure(state, rng)
	var source := state.deck.get_card(choices[0])
	if source == null:
		return _failure(state, rng)
	var copy := source.duplicate_state()
	copy.battle_uid = _allocate_card_uid(state.deck)
	copy.source_run_uid = -1
	copy.generated = true
	if not state.deck.add_card(copy, DeckState.ZONE_HAND):
		return _failure(state, rng)
	return _success(state, rng)
