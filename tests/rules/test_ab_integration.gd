extends "res://tests/test_case.gd"


func run() -> Array[String]:
	reset()
	_test_target_spec_is_consumed_by_effects()
	_test_real_board_displacement_and_unit_state()
	_test_move_budget_rejection_is_pure()
	_test_combo_uses_target_rule_and_unit_resource()
	return failures()


func _rng() -> RngStreams:
	var rng := RngStreams.new()
	rng.derive_streams("20261005")
	return rng


func _state() -> IntegratedBattleState:
	var state := IntegratedBattleState.new()
	var player := UnitState.create(1, &"unit.player", UnitState.Team.PLAYER, 20)
	player.set_resource(&"energy", 3)
	var enemy := UnitState.create(2, &"unit.enemy", UnitState.Team.ENEMY, 10)
	enemy.block = 3
	state.units[1] = player
	state.units[2] = enemy
	state.board.place_unit(1, Vector2i(0, 0))
	state.board.place_unit(2, Vector2i(3, 0))
	return state


func _unit_target(unit_id: int) -> TargetSpec.UnitTarget:
	var target := TargetSpec.UnitTarget.new()
	target.unit_id = unit_id
	return target


func _cell_target(cell: Vector2i) -> TargetSpec.CellTarget:
	var target := TargetSpec.CellTarget.new()
	target.cell = cell
	return target


func _test_target_spec_is_consumed_by_effects() -> void:
	var unit_context := EffectContext.new()
	unit_context.target = _unit_target(7)
	assert_equal(EffectStateAccess.target_unit_id(unit_context), 7, "A1 should read B1 UnitTarget")

	var cell_context := EffectContext.new()
	cell_context.target = _cell_target(Vector2i(2, 1))
	assert_equal(EffectStateAccess.target_cell(cell_context), Vector2i(2, 1), "A1 should read B1 CellTarget")

	var direction := TargetSpec.DirectionTarget.new()
	direction.direction = Vector2i.RIGHT
	var direction_context := EffectContext.new()
	direction_context.target = direction
	assert_equal(EffectStateAccess.target_direction(direction_context), Vector2i.RIGHT, "A1 should read B1 DirectionTarget")


func _test_real_board_displacement_and_unit_state() -> void:
	var state := _state()
	var result := EffectResolver.new().resolve(
		state,
		{
			"context": {"source_unit_id": 1},
			"effects": [
				{
					"type_key": &"move",
					"target": _cell_target(Vector2i(1, 0)),
					"params": {"move_points": 1},
				},
				{
					"type_key": &"damage",
					"target": _unit_target(2),
					"params": {"amount": 5},
				},
				{
					"type_key": &"apply_status",
					"target": _unit_target(2),
					"params": {"status_id": &"poison", "stacks": 2, "duration": 3},
				},
				{
					"type_key": &"push",
					"target": _unit_target(2),
					"params": {"direction": Vector2i.LEFT, "steps": 1},
				},
			],
		},
		_rng()
	)
	assert_true(bool(result["ok"]), "A1 should resolve against real B1/B2 state")
	var out: IntegratedBattleState = result["state_out"]
	assert_equal(out.board.get_unit_cell(1), Vector2i(1, 0), "move must go through B1 Displacement")
	assert_equal(out.board.get_unit_cell(2), Vector2i(2, 0), "push must go through B1 Displacement")
	assert_equal(out.units[2].block, 0, "damage should consume UnitState block")
	assert_equal(out.units[2].hp, 8, "remaining damage should reduce UnitState HP")
	assert_equal(out.units[2].statuses.size(), 1, "A1 StatusState should live in B2 UnitState")
	assert_true(out.units[2].statuses.values()[0] is StatusState, "UnitState status value is StatusState")
	assert_equal(state.board.get_unit_cell(1), Vector2i(0, 0), "preview must not mutate authoritative BoardState")
	assert_equal(state.board.get_unit_cell(2), Vector2i(3, 0), "preview push must not mutate authoritative BoardState")
	assert_equal(state.units[2].hp, 10, "preview damage must not mutate authoritative UnitState")


func _test_move_budget_rejection_is_pure() -> void:
	var state := _state()
	var result := EffectResolver.new().resolve(
		state,
		{
			"context": {"source_unit_id": 1},
			"effects": [{
				"type_key": &"move",
				"target": _cell_target(Vector2i(2, 0)),
				"params": {"move_points": 1},
			}],
		},
		_rng()
	)
	assert_true(not bool(result["ok"]), "B1 path budget should reject over-budget Move")
	assert_equal(result["error_code"], DisplacementResult.REASON_OUT_OF_BUDGET, "A1 should forward B1 failure reason")
	assert_equal(state.board.get_unit_cell(1), Vector2i(0, 0), "rejected move has zero board side effects")


func _test_combo_uses_target_rule_and_unit_resource() -> void:
	var state := _state()
	var deck := DeckState.new()
	var battle_card := BattleCardState.new()
	battle_card.battle_uid = 50
	battle_card.card_id = &"card.hit"
	deck.add_card(battle_card, DeckState.ZONE_HAND)

	var definition := CardDef.new()
	definition.card_id = &"card.hit"
	definition.base_cost = 2
	var rule := TargetSpec.UnitTarget.new()
	rule.team = TargetSpec.UnitTarget.Team.ENEMY
	definition.target_rule = rule
	var defs := {&"card.hit": definition}

	var bad_command := PlayCardsCommand.new()
	bad_command.actor_id = 1
	bad_command.card_uids = [50]
	bad_command.targets = [_cell_target(Vector2i(2, 0))]
	var bad := ComboPlanner.new().build_plan_for_actor(state, deck, bad_command, defs, _rng())
	assert_true(not bool(bad["ok"]), "CardDef UnitTarget rule should reject CellTarget")
	assert_equal(bad["error_code"], ComboPlanner.ERROR_TARGET, "wrong TargetSpec kind is target error")

	var ally_command := PlayCardsCommand.new()
	ally_command.actor_id = 1
	ally_command.card_uids = [50]
	ally_command.targets = [_unit_target(1)]
	var ally := ComboPlanner.new().build_plan_for_actor(state, deck, ally_command, defs, _rng())
	assert_true(not bool(ally["ok"]), "ENEMY UnitTarget rule should reject self/ally")
	assert_equal(ally["error_code"], ComboPlanner.ERROR_TARGET, "wrong UnitTarget team is target error")

	var good_command := PlayCardsCommand.new()
	good_command.actor_id = 1
	good_command.card_uids = [50]
	good_command.targets = [_unit_target(2)]
	var good := ComboPlanner.new().build_plan_for_actor(state, deck, good_command, defs, _rng())
	assert_true(bool(good["ok"]), "ComboPlanner should read actor energy from UnitState")
	assert_equal(int(good["cost_spent"]), 2, "card cost should be planned")
	assert_equal(int(good["resource_after"]), 1, "resource_after should use UnitState energy")
	assert_equal(state.units[1].get_resource(&"energy"), 3, "planner must not mutate authoritative resource")
