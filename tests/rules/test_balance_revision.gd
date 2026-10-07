extends "res://tests/test_case.gd"

func run() -> Array[String]:
	reset()
	_test_charge_and_single_upgrade()
	_test_training_after_combo()
	_test_courage_and_poison()
	_test_movement_and_immunity()
	_test_enemy_movement()
	_test_overflow_and_growth_limits()
	_test_every_upgrade_has_gameplay_effect()
	_test_summon_preview_and_cap()
	_test_spawn_collision()
	return failures()

func _status(unit: UnitState, id: StringName, stacks: int, duration: int = 2) -> void:
	var instance := StatusState.new()
	instance.instance_id = 100 + unit.status_ids().size()
	instance.status_id = id
	instance.stacks = stacks
	instance.duration = duration
	unit.set_status(instance.instance_id, instance)

func _test_charge_and_single_upgrade() -> void:
	var state := FormalCardFixture.state(10, 30)
	var heal := FormalCardFixture.add_card(state, 46, 1)
	var guard := FormalCardFixture.add_card(state, 37, 2)
	FormalCardRules.on_card_drawn(heal)
	FormalCardRules.on_card_drawn(guard)
	assert_equal(state.get_unit(1).hp, 10, "drawing heal only stores charge")
	assert_equal(state.get_unit(1).block, 0, "drawing stacked guard grants no immediate block")
	assert_equal(heal.runtime_data.heal_charge, 3, "base heal stores 3")
	heal.upgrade_level = 1
	FormalCardRules.on_card_drawn(heal)
	assert_equal(heal.runtime_data.heal_charge, 7, "upgrading does not retroactively change prior charge")
	var cloned := SaveCodec.new().clone_state(state)
	assert_equal(cloned.deck.get_card(1).runtime_data.heal_charge, 7, "save clone retains charge")
	var resolved := FormalCardFixture.resolve(cloned, 46, 1)
	assert_equal((resolved.state_out as BattleState).get_unit(1).hp, 17, "playing accumulated heal restores 7")
	resolved = FormalCardFixture.resolve(state, 37, 2)
	assert_equal((resolved.state_out as BattleState).get_unit(1).block, 4, "playing guard grants stored block")
	assert_equal((resolved.state_out as BattleState).deck.get_card(2).runtime_data.stacked_block, 0, "guard resets only on play")
	var permanent := RunCardState.new()
	permanent.run_uid = 55
	permanent.card_id = &"card.starter.attack"
	var temporary := CardSystem.new().create_battle_card(permanent, 55)
	state.deck.add_card(temporary, DeckState.ZONE_DRAW)
	FormalCardFixture.add_card(state, 38, 38)
	resolved = FormalCardFixture.resolve(state, 38, 38)
	var out := resolved.state_out as BattleState
	assert_equal(out.deck.get_card(55).upgrade_level, 1, "hold back upgrades the drawn instance")
	assert_equal(permanent.upgrade_level, 0, "hold back does not write permanent deck")
	out.deck.move_card(55, DeckState.ZONE_HAND, DeckState.ZONE_DRAW)
	resolved = FormalCardFixture.resolve(out, 38, 38)
	assert_equal((resolved.state_out as BattleState).deck.get_card(55).upgrade_level, 1, "repeated hold back cannot upgrade twice")
	permanent.upgrade_level = 9
	temporary.upgrade_level = 9
	assert_equal(permanent.upgrade_level, 1, "legacy permanent levels clamp")
	assert_equal(temporary.upgrade_level, 1, "legacy battle levels clamp")

func _test_training_after_combo() -> void:
	for order: Array in [[26, 17], [17, 26]]:
		var state := FormalCardFixture.state(30, 30, 100)
		FormalCardFixture.add_card(state, 26, 26)
		FormalCardFixture.add_card(state, 17, 17)
		var ids: Array[int] = []
		var targets: Array = []
		for n: int in order:
			ids.append(n)
			targets.append(null if n == 26 else FormalCardFixture.unit_target(2))
		var command := FormalCardFixture.command(1, ids, targets)
		var defs := FormalCardFixture.defs([26, 17])
		var result := ComboPlanner.new().build_plan_for_actor(state, state.deck, command, defs, FormalCardFixture.rng())
		assert_true(bool(result.get("ok", false)), "training combo accepted in either order")
		if not bool(result.get("ok", false)):
			continue
		var out := result.state_out as BattleState
		assert_equal(out.get_unit(2).hp, 93, "current knife damage excludes training")
		assert_equal(out.deck.get_card(17).damage_modifier, 3, "training applies after the entire group")
		assert_equal(state.deck.get_card(17).damage_modifier, 0, "planning is side-effect free")
		out.deck.move_card(17, DeckState.ZONE_EXHAUST, DeckState.ZONE_HAND)
		result = FormalCardFixture.resolve(out, 17, 17, FormalCardFixture.unit_target(2))
		assert_equal((result.state_out as BattleState).get_unit(2).hp, 83, "next play gains training damage")

func _test_courage_and_poison() -> void:
	var state := FormalCardFixture.state(30, 30, 100, Vector2i(2, 2), Vector2i(3, 2), 3, 5)
	FormalCardFixture.add_card(state, 19, 19)
	var result := FormalCardFixture.resolve(state, 19, 19, FormalCardFixture.unit_target(2))
	assert_equal((result.state_out as BattleState).get_unit(2).hp, 89, "5 courage adds 5 to a 6-damage attack")
	_status(state.get_unit(1), StatusRules.POISON, 2, -1)
	_status(state.get_unit(1), StatusRules.POISON, 3, -1)
	state.get_unit(1).block = 50
	StatusTickSystem.new()._finish_single_owner_turn(state, FormalCardFixture.rng(), 1)
	assert_equal(state.get_unit(1).hp, 25, "poison ignores block and courage")
	assert_equal(state.get_unit(1).block, 50, "poison does not consume block")
	assert_equal(StatusRules.stacks(state.get_unit(1), StatusRules.POISON), 4, "all poison sources together lose only one stack")
	assert_equal(state.get_unit(1).get_resource(&"courage"), 2, "odd courage halves down at owner turn end")
	StatusTickSystem.new()._finish_single_owner_turn(state, FormalCardFixture.rng(), 1)
	assert_equal(state.get_unit(1).get_resource(&"courage"), 1, "courage continues decaying")

func _test_movement_and_immunity() -> void:
	var state := FormalCardFixture.state()
	_status(state.get_unit(1), StatusRules.ENTANGLE, 1)
	for number: int in [13, 14]:
		var target: Variant = FormalCardFixture.direction_target(Vector2i.RIGHT) if number == 13 else FormalCardFixture.unit_target(2)
		var result := FormalCardRules.validate_target(state, 1, FormalCardFixture.definition(number), target)
		assert_true(not bool(result.ok), "entangle rejects active movement card %d" % number)
	var charge := load("res://content/cards/starter/charge.tres") as CardDef
	assert_true(not bool(FormalCardRules.validate_target(state, 1, charge, FormalCardFixture.unit_target(2)).ok), "entangle also locks charge")
	var resolver := EffectResolver.new()
	var result := resolver.resolve(state, {"context": {"source_unit_id": 1, "target": {"cell": Vector2i(2, 3)}}, "effects": [{"type_key": &"move", "params": {"move_points": 2}}]}, FormalCardFixture.rng())
	assert_true(not bool(result.ok), "generic move effects cannot bypass entangle")
	result = resolver.resolve(state, {"context": {"source_unit_id": 2, "target": 1}, "effects": [{"type_key": &"push", "params": {"steps": 1, "direction_mode": &"away_from_source"}}]}, FormalCardFixture.rng())
	assert_true(bool(result.ok), "forced knockback ignores entangle")
	assert_equal((result.state_out as BattleState).board.get_unit_cell(1), Vector2i(1, 2), "forced movement actually happens")
	result = resolver.resolve(state, {"context": {"source_unit_id": 2, "target": 1}, "effects": [{"type_key": &"apply_status", "params": {"status_id": StatusRules.STUN, "stacks": 1}}]}, FormalCardFixture.rng())
	assert_equal(StatusRules.stacks((result.state_out as BattleState).get_unit(1), StatusRules.STUN), 0, "no player stun is introduced")

func _test_enemy_movement() -> void:
	var executor := EnemyTurnExecutor.new()
	for kind: int in [EnemyActionDef.Kind.APPROACH, EnemyActionDef.Kind.ATTACK, EnemyActionDef.Kind.DASH]:
		var state := FormalCardFixture.state(30, 30, 30, Vector2i(0, 2), Vector2i(6, 2))
		_status(state.get_unit(2), StatusRules.SLOW, 2)
		var action := EnemyActionDef.new()
		action.kind = kind
		action.move_steps = 3
		action.advance_steps = 3
		action.damage = 10
		var intent := IntentState.new()
		intent.locked_unit_id = 1
		intent.locked_cell = Vector2i(0, 2)
		var plan := executor._intent_to_effect_plan(state, 2, intent, action, FormalCardFixture.rng())
		var result := EffectResolver.new().resolve(state, plan, FormalCardFixture.rng())
		assert_true(bool(result.ok), "slowed enemy movement resolves")
		if bool(result.ok):
			var out := result.state_out as BattleState
			assert_equal(out.board.get_unit_cell(2), Vector2i(5, 2), "two slow stacks remove two steps for movement kind %d" % kind)
			assert_equal(out.get_unit(1).hp, 30, "out-of-range attack or dash cannot hit")
		_status(state.get_unit(2), StatusRules.ENTANGLE, 1)
		plan = executor._intent_to_effect_plan(state, 2, intent, action, FormalCardFixture.rng())
		assert_true(plan.is_empty(), "entangled distant enemy cannot move or hit")

func _test_overflow_and_growth_limits() -> void:
	var state := FormalCardFixture.state(20, 30, 5, Vector2i(2, 2), Vector2i(3, 2), 3, 5)
	FormalCardFixture.add_enemy(state, 3, 40, Vector2i(3, 3))
	FormalCardFixture.add_card(state, 33, 33)
	var result := FormalCardFixture.resolve(state, 33, 33, FormalCardFixture.unit_target(2))
	assert_equal((result.state_out as BattleState).get_unit(3).hp, 31, "overflow 9+5-5=9 does not get courage twice")
	state = FormalCardFixture.state(20, 30, 5)
	FormalCardFixture.add_enemy(state, 3, 5, Vector2i(3, 3))
	FormalCardFixture.add_card(state, 18, 18)
	result = FormalCardFixture.resolve(state, 18, 18, FormalCardFixture.unit_target(2))
	result = FormalCardFixture.resolve(result.state_out, 18, 18, FormalCardFixture.unit_target(3))
	assert_equal((result.state_out as BattleState).get_unit(1).max_hp, 33, "copied blood swords cannot farm unbounded maximum HP")
	state = FormalCardFixture.state(30, 30, 300)
	FormalCardFixture.add_card(state, 19, 19)
	for i in range(8):
		result = FormalCardFixture.resolve(state, 19, 19, FormalCardFixture.unit_target(2))
		state = result.state_out
	assert_equal(state.deck.get_card(19).damage_modifier, 6, "demon blade caps its own battle growth")

func _test_every_upgrade_has_gameplay_effect() -> void:
	var catalog := load("res://content/catalog.tres") as ContentCatalog
	for definition: CardDef in catalog.cards:
		assert_true(not definition._upgrade_data(1).is_empty(), "%s has an upgrade" % definition.card_id)
		assert_equal(definition.get_display_name(1), definition.get_display_name(0) + "+", "single plus naming")
		assert_equal(definition.get_cost(99), definition.get_cost(1), "levels above one use upgraded definition")
		if definition.card_number <= 0 or definition.get_cost(0) != definition.get_cost(1):
			continue
		var base := _upgrade_outcome(definition, 0)
		var upgraded := _upgrade_outcome(definition, 1)
		assert_true(base != upgraded, "%s upgrade changes actual outcome" % definition.card_id)

func _upgrade_outcome(definition: CardDef, level: int) -> String:
	var state := FormalCardFixture.state(20, 100, 200, Vector2i(2, 2), Vector2i(3, 2), 3, 4)
	var number := definition.card_number
	var source := FormalCardFixture.add_card(state, number, 500)
	source.upgrade_level = level
	FormalCardRules.on_card_drawn(source)
	FormalCardFixture.add_card(state, 17, 501)
	FormalCardFixture.add_card(state, 28, 502, DeckState.ZONE_DRAW)
	var defs := FormalCardFixture.defs([number, 17, 28])
	var command := FormalCardFixture.command(1, [500], [null])
	var rule := definition.get_target_rule(level)
	if rule is TargetSpec.UnitTarget:
		command.targets[0] = FormalCardFixture.unit_target(2)
	elif rule is TargetSpec.CellTarget:
		command.targets[0] = FormalCardFixture.cell_target(Vector2i(3, 2))
	elif rule is TargetSpec.DirectionTarget:
		command.targets[0] = FormalCardFixture.direction_target(Vector2i.RIGHT)
	var request := FormalCardRules.choice_request(state, 500, [500], defs)
	if not request.is_empty():
		command.choices[500] = [Array(request.candidates)[0]]
	if number in [26, 27]:
		command.card_uids.append(501)
		command.targets.append(FormalCardFixture.unit_target(2))
	if number == 49:
		state.deck.get_card(501).card_id = &"card.reward.39"
		defs[&"card.reward.39"] = FormalCardFixture.definition(39)
		command.card_uids.append(501)
		command.targets.append(null)
	var result := ComboPlanner.new().build_plan_for_actor(state, state.deck, command, defs, FormalCardFixture.rng())
	assert_true(bool(result.get("ok", false)), "upgrade execution succeeds: %s level %d" % [definition.card_id, level])
	if not bool(result.get("ok", false)):
		return "failed"
	var out := result.state_out as BattleState
	# Exclude the upgraded source's metadata: require a real effect on units or other cards.
	out.deck.cards.erase(500)
	return JSON.stringify(SaveCodec.new().encode_state(out))

func _test_summon_preview_and_cap() -> void:
	var state := FormalCardFixture.state(100, 100)
	state.hand_size = 0
	var summon := EnemyActionDef.new()
	summon.id = &"test.summon"
	summon.kind = EnemyActionDef.Kind.SUMMON
	summon.target_policy = EnemyActionDef.TargetPolicy.NONE
	var behavior := SequenceBehaviorDef.new()
	behavior.sequence = [summon]
	var attack := EnemyActionDef.new()
	attack.id = &"test.minion.attack"
	attack.damage = 1
	var minion := SequenceBehaviorDef.new()
	minion.sequence = [attack]
	var pool := [{"enemy_id": &"test.minion", "unit_def_id": &"unit.test.minion", "max_hp": 10, "behavior": minion, "actions": [attack]}]
	var session := BattleSession.new()
	state.phase = BattleState.Phase.SETUP
	session.setup(FormalCardFixture.rng("7001"), state, {}, {2: behavior}, {}, Callable(), pool)
	var command := EndTurnCommand.new()
	command.actor_id = 1
	command.command_id = 7001
	var before := SaveCodec.new().encode_state(session.state)
	assert_true(session.preview(command).accepted, "summon round preview succeeds")
	assert_equal(SaveCodec.new().encode_state(session.state), before, "summon preview cannot alter state or RNG")
	assert_equal(session._enemy_behaviors.size(), 1, "summon preview cannot register phantom enemy behavior")
	for i in range(5):
		command = EndTurnCommand.new()
		command.actor_id = 1
		command.command_id = 7002 + i
		assert_true(session.submit(command).accepted, "summon round commits")
		session.finish_presentation()
	assert_equal(session.state.alive_enemy_ids().size(), 4, "summons stop at four living enemies including boss")
	assert_equal(session._enemy_behaviors.size(), 4, "committed summons register their behaviors")

func _test_spawn_collision() -> void:
	var content: Node = load("res://autoload/content_db.gd").new()
	content.load_catalog()
	var run := RunSession.create_run(&"character.hero", "1279", content)
	var encounter := EncounterDef.new()
	encounter.id = &"test.spawn.collision"
	encounter.enemy_ids = [&"enemy.tomb.scorpion"]
	encounter.player_start = Vector2i(2, 5)
	encounter.enemy_spawns = [Vector2i(2, 5)]
	var data := EncounterBuilder.build(encounter, run, FormalCardFixture.rng("1279"), content)
	assert_true(not data.is_empty(), "colliding spawn uses a free fallback")
	if not data.is_empty():
		var state := data.state as BattleState
		assert_equal(state.board.get_unit_cell(1), Vector2i(2, 5), "internal default player start remains valid")
		assert_true(state.board.get_unit_cell(2) != BoardState.INVALID_CELL, "enemy cannot be alive outside the board")
		assert_true(state.board.get_unit_cell(2) != Vector2i(2, 5), "enemy never overlaps player spawn")
	content.free()
