extends "res://tests/test_case.gd"

var _range_checks: Array[Vector2i] = []


func run() -> Array[String]:
	reset()
	_test_cost_is_computed_once_and_original_deck_is_untouched()
	_test_insufficient_cost_has_zero_side_effects()
	_test_resolving_cleanup_uses_discard_or_exhaust()
	_test_range_is_recomputed_after_previous_movement()
	_test_later_invalidated_target_can_fizzle_without_retarget()
	return failures()


func _rng() -> RngStreams:
	var rng := RngStreams.new()
	rng.derive_streams("20261005")
	return rng


func _card(uid: int, card_id: StringName, modifier: int = 0) -> BattleCardState:
	var card := BattleCardState.new()
	card.battle_uid = uid
	card.card_id = card_id
	card.cost_modifier = modifier
	return card


func _definition(
	card_id: StringName,
	cost: int,
	effects: Array[EffectDef] = [],
	exhausts: bool = false,
	tags: Array[StringName] = []
) -> CardDef:
	var definition := CardDef.new()
	definition.card_id = card_id
	definition.base_cost = cost
	definition.effects = effects
	definition.exhaust_on_play = exhausts
	definition.tags = tags
	return definition


func _base_command(uids: Array[int], targets: Array, actor_id: int = 1) -> PlayCardsCommand:
	var command := PlayCardsCommand.new()
	command.actor_id = actor_id
	command.card_uids = uids
	command.targets = targets
	return command


func _test_cost_is_computed_once_and_original_deck_is_untouched() -> void:
	var deck := DeckState.new()
	deck.add_card(_card(10, &"card.a"), DeckState.ZONE_HAND)
	deck.add_card(_card(11, &"card.b", -1), DeckState.ZONE_HAND)
	var defs := {
		&"card.a": _definition(&"card.a", 2),
		&"card.b": _definition(&"card.b", 2),
	}
	var result := ComboPlanner.new().build_plan(
		EffectTestState.new(),
		deck,
		_base_command([10, 11], [null, null]),
		defs,
		5,
		_rng()
	)
	assert_true(bool(result["ok"]), "valid combo should plan")
	assert_equal(int(result["cost_spent"]), 3, "effective costs should be summed exactly once")
	assert_equal(int(result["resource_after"]), 2, "planner should expose one final resource deduction")
	assert_equal(deck.hand, [10, 11], "planner must not mutate authoritative deck")
	assert_equal(deck.resolving, [], "authoritative resolving zone must stay untouched")


func _test_insufficient_cost_has_zero_side_effects() -> void:
	var deck := DeckState.new()
	deck.add_card(_card(20, &"card.expensive"), DeckState.ZONE_HAND)
	var state := EffectTestState.new()
	var rng := _rng()
	var rng_before := rng.snapshot()
	var result := ComboPlanner.new().build_plan(
		state,
		deck,
		_base_command([20], [2]),
		{&"card.expensive": _definition(&"card.expensive", 4, [TestEffectDef.make(&"damage", {"amount": 9})])},
		3,
		rng
	)
	assert_true(not bool(result["ok"]), "insufficient resource should reject combo")
	assert_equal(result["error_code"], ComboPlanner.ERROR_COST, "cost rejection code")
	assert_equal(int(result["cost_spent"]), 0, "rejected combo must spend zero resource")
	assert_equal(int(state.units[2]["hp"]), 10, "rejected combo must not resolve effects")
	assert_equal(deck.hand, [20], "rejected combo must not move cards")
	assert_equal(rng.snapshot(), rng_before, "rejected combo must not advance authoritative RNG")


func _test_resolving_cleanup_uses_discard_or_exhaust() -> void:
	var deck := DeckState.new()
	deck.add_card(_card(30, &"card.normal"), DeckState.ZONE_HAND)
	deck.add_card(_card(31, &"card.exhaust"), DeckState.ZONE_HAND)
	var defs := {
		&"card.normal": _definition(&"card.normal", 0),
		&"card.exhaust": _definition(&"card.exhaust", 0, [], true),
	}
	var result := ComboPlanner.new().build_plan(
		EffectTestState.new(),
		deck,
		_base_command([30, 31], [null, null]),
		defs,
		0,
		_rng()
	)
	assert_true(bool(result["ok"]), "zero-cost combo should plan")
	var out: DeckState = result["deck_out"]
	assert_equal(out.resolving, [], "all committed cards must leave resolving after preview")
	assert_equal(out.discard, [30], "normal card should finish in discard")
	assert_equal(out.exhaust, [31], "exhaust card should finish in exhaust")
	assert_true(bool(out.validate_invariants()["ok"]), "combo cleanup must preserve zone invariant")


func _test_range_is_recomputed_after_previous_movement() -> void:
	_range_checks.clear()
	var deck := DeckState.new()
	deck.add_card(_card(40, &"card.dash"), DeckState.ZONE_HAND)
	deck.add_card(_card(41, &"card.strike"), DeckState.ZONE_HAND)
	var defs := {
		&"card.dash": _definition(&"card.dash", 1, [TestEffectDef.make(&"move")]),
		&"card.strike": _definition(&"card.strike", 1, [TestEffectDef.make(&"damage", {"amount": 4})], false, [&"attack"]),
	}
	var state := EffectTestState.new()
	var result := ComboPlanner.new().build_plan(
		state,
		deck,
		_base_command([40, 41], [{"cell": Vector2i(1, 0)}, 2]),
		defs,
		2,
		_rng(),
		Callable(self, "_validate_dynamic_range")
	)
	assert_true(bool(result["ok"]), "dash then strike should become valid after movement")
	assert_equal(_range_checks.size(), 2, "target validator should run separately for each card")
	assert_equal(_range_checks[0], Vector2i(0, 0), "first card validates from original position")
	assert_equal(_range_checks[1], Vector2i(1, 0), "second card must validate from moved position")
	var out: EffectTestState = result["state_out"]
	assert_equal(out.positions[1], Vector2i(1, 0), "dash should update work-state position")
	assert_equal(int(out.units[2]["hp"]), 9, "strike should recalculate range then resolve through Block")


func _validate_dynamic_range(
	state: Variant,
	_card: BattleCardState,
	definition: CardDef,
	target: Variant
) -> Dictionary:
	var typed := state as EffectTestState
	_range_checks.append(typed.positions[1])
	if definition.card_id == &"card.dash":
		return {"ok": target is Dictionary and target.has("cell")}
	var target_id := int(target)
	var from_cell: Vector2i = typed.positions[1]
	var target_cell: Vector2i = typed.positions[target_id]
	return {"ok": from_cell.distance_to(target_cell) <= 1.0}


func _test_later_invalidated_target_can_fizzle_without_retarget() -> void:
	var deck := DeckState.new()
	deck.add_card(_card(50, &"card.kill"), DeckState.ZONE_HAND)
	deck.add_card(_card(51, &"card.follow"), DeckState.ZONE_HAND)
	var defs := {
		&"card.kill": _definition(&"card.kill", 0, [TestEffectDef.make(&"damage", {"amount": 99})], false, [&"attack"]),
		&"card.follow": _definition(&"card.follow", 0, [TestEffectDef.make(&"damage", {"amount": 3})], false, [&"attack"]),
	}
	var result := ComboPlanner.new().build_plan(
		EffectTestState.new(),
		deck,
		_base_command([50, 51], [2, 2]),
		defs,
		0,
		_rng(),
		Callable(self, "_validate_or_fizzle_dead_target")
	)
	assert_true(bool(result["ok"]), "later target invalidation should fizzle, not retarget or refund")
	var steps: Array = result["steps"]
	assert_true(bool(steps[1]["fizzled"]), "second card should be marked fizzled")
	assert_equal(steps[1]["target"], 2, "fizzled card must keep original target and never retarget")
	var out: DeckState = result["deck_out"]
	assert_equal(out.discard, [50, 51], "fizzled committed card still leaves resolving")


func _validate_or_fizzle_dead_target(
	state: Variant,
	_card: BattleCardState,
	_definition: CardDef,
	target: Variant
) -> Dictionary:
	var typed := state as EffectTestState
	var unit: Dictionary = typed.units[int(target)]
	if not bool(unit.get("alive", true)) or int(unit.get("hp", 0)) <= 0:
		return {"ok": false, "fizzle": true}
	return {"ok": true}
