extends "res://tests/test_case.gd"
## 精英/Boss 新机制测试：多段伤害、无视护甲 DoT（中毒减层）、流血保持吃盾+减持续、
## DASH（随位移加成伤害）、SUMMON（召唤生成 + 首回合可行动 + 确定性）。


func run() -> Array[String]:
	reset()
	_test_multi_hit()
	_test_poison_ignores_block_and_decays_stacks()
	_test_bleed_still_armored_and_duration_decays()
	_test_dash_damage_scales_with_steps()
	_test_advance_then_attack_same_turn()
	_test_death_removes_from_board()
	_test_summon_spawns_and_acts_next_round()
	return failures()


func _status(instance_id: int, status_id: StringName, stacks: int, duration: int) -> StatusState:
	var s := StatusState.new()
	s.instance_id = instance_id
	s.status_id = status_id
	s.stacks = stacks
	s.duration = duration
	return s


func _action(id: StringName, kind: EnemyActionDef.Kind, damage: int = 0) -> EnemyActionDef:
	var a := EnemyActionDef.new()
	a.id = id
	a.kind = kind
	a.target_policy = EnemyActionDef.TargetPolicy.PLAYER
	a.damage = damage
	a.range = 1
	a.range_shape = BoardQuery.RangeShape.BOX
	return a


func _behavior(actions: Array[EnemyActionDef]) -> SequenceBehaviorDef:
	var b := SequenceBehaviorDef.new()
	b.id = &"behavior.mech"
	b.sequence = actions
	return b


func _defend(id: StringName = &"d.defend") -> EnemyActionDef:
	var a := EnemyActionDef.new()
	a.id = id
	a.kind = EnemyActionDef.Kind.DEFEND
	a.target_policy = EnemyActionDef.TargetPolicy.SELF
	a.block = 3
	return a


func _lock(state: BattleState, behavior: BehaviorDef) -> void:
	state.enemy_intents[2] = EnemyPlanner.plan(
		state.board, state.get_unit(2), behavior, 0, [state.get_unit(1)]
	)


func _count_damage_events(result: Dictionary) -> int:
	var events := result.get("events") as EventBatch
	if events == null:
		return 0
	var n := 0
	for event: GameEvent in events.events:
		if event.type_key == &"damage":
			n += 1
	return n


func _test_multi_hit() -> void:
	var streams := Phase3Fixture.rng("multihit")
	var state := Phase3Fixture.base_state(streams, 30, 20, Vector2i(0, 0), Vector2i(1, 0))
	state.phase = BattleState.Phase.PLAYER_INPUT
	var volley := _action(&"volley", EnemyActionDef.Kind.ATTACK, 4)
	volley.hit_count = 2
	var behavior := _behavior([volley])
	_lock(state, behavior)
	var result := TurnSystem.new().run_end_turn(state, streams, {2: behavior}, {volley.id: volley})
	assert_true(bool(result.get("ok", false)), "多段攻击应结算成功")
	assert_equal(state.get_unit(1).hp, 22, "4×2 两段共 8 点")
	assert_equal(_count_damage_events(result), 2, "应产生两个伤害事件")


func _test_poison_ignores_block_and_decays_stacks() -> void:
	var streams := Phase3Fixture.rng("poison-armor")
	var state := Phase3Fixture.base_state(streams, 20, 20, Vector2i(0, 0), Vector2i(1, 0))
	state.phase = BattleState.Phase.PLAYER_INPUT
	state.get_unit(1).block = 5
	state.get_unit(1).set_status(20, _status(20, StatusRules.POISON, 4, 99))
	var defend := _defend()
	var behavior := _behavior([defend])
	_lock(state, behavior)
	var result := TurnSystem.new().run_end_turn(state, streams, {2: behavior}, {defend.id: defend})
	assert_true(bool(result.get("ok", false)), "中毒结算应成功")
	assert_equal(state.get_unit(1).hp, 16, "中毒无视护盾：4 层直接扣 4（护盾不吸收）")
	assert_equal(StatusRules.stacks(state.get_unit(1), StatusRules.POISON), 3, "中毒层数 -1（减层而非减持续）")


func _test_bleed_still_armored_and_duration_decays() -> void:
	var streams := Phase3Fixture.rng("bleed-armor")
	var state := Phase3Fixture.base_state(streams, 20, 20, Vector2i(0, 0), Vector2i(1, 0))
	state.phase = BattleState.Phase.PLAYER_INPUT
	state.get_unit(1).block = 5
	state.get_unit(1).set_status(21, _status(21, StatusRules.BLEED, 3, 5))
	var defend := _defend()
	var behavior := _behavior([defend])
	_lock(state, behavior)
	TurnSystem.new().run_end_turn(state, streams, {2: behavior}, {defend.id: defend})
	assert_equal(state.get_unit(1).hp, 20, "流血吃护盾：3 层被 5 护盾吸收，不掉血")
	assert_equal(state.get_unit(1).get_status(21).duration, 4, "流血按持续递减")


func _test_dash_damage_scales_with_steps() -> void:
	var streams := Phase3Fixture.rng("dash")
	var state := Phase3Fixture.base_state(streams, 40, 30, Vector2i(0, 0), Vector2i(0, 4))
	state.phase = BattleState.Phase.PLAYER_INPUT
	var dash := _action(&"dash", EnemyActionDef.Kind.DASH, 6)
	dash.move_steps = 3
	dash.dash_damage_per_step = 3
	var behavior := _behavior([dash])
	_lock(state, behavior)
	var result := TurnSystem.new().run_end_turn(state, streams, {2: behavior}, {dash.id: dash})
	assert_true(bool(result.get("ok", false)), "横冲直撞应结算成功")
	assert_equal(state.board.get_unit_cell(2), Vector2i(0, 1), "冲撞移动 3 步到玩家旁")
	assert_equal(state.get_unit(1).hp, 25, "伤害 = 6 + 3 步 × 3 = 15")


func _test_advance_then_attack_same_turn() -> void:
	# 距 3、advance_steps=2：同一回合先移动 2 步进射程，再命中（不再隔回合）。
	var streams := Phase3Fixture.rng("advance")
	var state := Phase3Fixture.base_state(streams, 30, 20, Vector2i(0, 0), Vector2i(0, 3))
	state.phase = BattleState.Phase.PLAYER_INPUT
	var attack := _action(&"a.bite", EnemyActionDef.Kind.ATTACK, 5)
	attack.advance_steps = 2
	var behavior := _behavior([attack])
	_lock(state, behavior)
	var result := TurnSystem.new().run_end_turn(state, streams, {2: behavior}, {attack.id: attack})
	assert_true(bool(result.get("ok", false)), "先移动再攻击应结算成功")
	assert_equal(state.board.get_unit_cell(2), Vector2i(0, 1), "同一回合先移动到射程内")
	assert_equal(state.get_unit(1).hp, 25, "移动进射程后命中（5 伤害）")


func _test_death_removes_from_board() -> void:
	# 致命伤害后单位离场（不占格），但 units 仍记录、存活过滤负责胜负。
	var streams := Phase3Fixture.rng("death")
	var state := Phase3Fixture.base_state(streams, 30, 3, Vector2i(0, 0), Vector2i(1, 0))
	var resolved := EffectResolver.new().resolve(
		state,
		{
			"context": {"source_unit_id": 1},
			"effects": [{"type_key": &"damage", "target": 2, "params": {"amount": 10}}],
		},
		streams
	)
	assert_true(bool(resolved.get("ok", false)), "致命伤害应解析成功")
	var out := resolved["state_out"] as BattleState
	assert_equal(out.board.get_unit_cell(2), BoardState.INVALID_CELL, "死亡单位已从棋盘移除")
	assert_equal(out.board.is_occupied(Vector2i(1, 0)), false, "尸格不再占用")
	assert_equal(out.get_unit(2).hp, 0, "units 仍记录死亡单位（可查）")
	assert_true(not out.alive_enemy_ids().has(2), "存活过滤排除死亡敌人")


func _test_summon_spawns_and_acts_next_round() -> void:
	var spec := _summon_spec()
	var first := _run_summon("summon-seed", spec)
	var second := _run_summon("summon-seed", spec)

	var state: BattleState = first["state"]
	var summoned := _summoned_id(state)
	assert_true(summoned >= 0, "应生成一只小怪")
	if summoned >= 0:
		assert_equal(state.get_unit(summoned).max_hp, 12, "召唤单位来自召唤池 spec")
		var player_cell := state.board.get_unit_cell(1)
		var cell := state.board.get_unit_cell(summoned)
		assert_true(
			maxi(absi(cell.x - player_cell.x), absi(cell.y - player_cell.y)) <= TurnSystem.SUMMON_RADIUS,
			"召唤落点在玩家附近"
		)
		var intent: IntentState = state.enemy_intents.get(summoned)
		assert_true(intent != null and not intent.is_empty(), "召唤单位下一回合已有锁定意图（可行动）")

	var summoned2 := _summoned_id(second["state"] as BattleState)
	assert_equal(
		(second["state"] as BattleState).board.get_unit_cell(summoned2),
		state.board.get_unit_cell(summoned),
		"同 seed 同召唤结果（确定性）"
	)


func _summon_spec() -> Dictionary:
	var mob_attack := _action(&"mob.atk", EnemyActionDef.Kind.ATTACK, 3)
	var mob_behavior := _behavior([mob_attack])
	return {
		"enemy_id": &"enemy.test.mob",
		"unit_def_id": &"unit.enemy.test.mob",
		"max_hp": 12,
		"appearance_key": &"",
		"behavior": mob_behavior,
		"actions": [mob_attack],
	}


func _run_summon(seed_text: String, spec: Dictionary) -> Dictionary:
	var streams := Phase3Fixture.rng(seed_text)
	var state := Phase3Fixture.base_state(streams, 40, 30, Vector2i(4, 4), Vector2i(0, 0))
	state.phase = BattleState.Phase.PLAYER_INPUT
	var summon := _action(&"statue.summon", EnemyActionDef.Kind.SUMMON)
	summon.target_policy = EnemyActionDef.TargetPolicy.NONE
	var behavior := _behavior([summon])
	_lock(state, behavior)
	var result := TurnSystem.new().run_end_turn(state, streams, {2: behavior}, {summon.id: summon}, [spec])
	return {"ok": bool(result.get("ok", false)), "state": state}


func _summoned_id(state: BattleState) -> int:
	for enemy_id: int in state.enemy_ids():
		if enemy_id != 2:
			return enemy_id
	return -1
