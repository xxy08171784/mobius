extends "res://tests/test_case.gd"


func run() -> Array[String]:
	reset()
	_test_damage_modifiers()
	_test_bleed_ticks_at_owner_turn_end()
	return failures()


func _status(id: int, status_id: StringName, stacks: int, duration: int) -> StatusState:
	var status := StatusState.new()
	status.instance_id = id
	status.status_id = status_id
	status.stacks = stacks
	status.duration = duration
	return status


func _test_damage_modifiers() -> void:
	var streams := Phase3Fixture.rng("status-damage")
	var state := Phase3Fixture.base_state(streams, 20, 30)
	state.get_unit(1).set_status(10, _status(10, StatusRules.FOCUS, 2, 2))
	state.get_unit(2).set_status(11, _status(11, StatusRules.VULNERABLE, 1, 2))
	var result := EffectResolver.new().resolve(
		state,
		{
			"context": {"source_unit_id": 1},
			"effects": [{"type_key": &"damage", "target": 2, "params": {"amount": 4}}],
		},
		streams
	)
	assert_true(bool(result.get("ok", false)), "focus + vulnerable damage should resolve")
	if bool(result.get("ok", false)):
		var out := result["state_out"] as BattleState
		# (4 + 2 层专注) * 1.5 易伤 = 9。
		assert_equal(out.get_unit(2).hp, 21, "status damage modifiers should follow flat then percent order")
	assert_equal(state.get_unit(2).hp, 30, "status damage preview must keep input state pure")


func _test_bleed_ticks_at_owner_turn_end() -> void:
	var streams := Phase3Fixture.rng("status-bleed")
	var state := Phase3Fixture.base_state(streams, 20, 20)
	state.phase = BattleState.Phase.PLAYER_INPUT
	state.get_unit(1).set_status(12, _status(12, StatusRules.BLEED, 3, 2))
	var defend := Phase3Fixture.defend_action(&"enemy.defend.status", 0)
	var behavior := Phase3Fixture.behavior([defend])
	state.enemy_intents[2] = EnemyPlanner.plan(
		state.board,
		state.get_unit(2),
		behavior,
		0,
		[state.get_unit(1)]
	)
	var result := TurnSystem.new().run_end_turn(
		state,
		streams,
		{2: behavior},
		{defend.id: defend}
	)
	assert_true(bool(result.get("ok", false)), "end turn with bleed should resolve")
	assert_equal(state.get_unit(1).hp, 17, "3 bleed stacks should deal 3 damage")
	assert_equal(state.get_unit(1).get_status(12).duration, 1, "bleed duration should decrease after ticking")
	var events := result.get("events") as EventBatch
	assert_true(events != null and events.size() >= 1, "bleed should emit presentation damage event")
