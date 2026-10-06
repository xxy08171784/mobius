extends "res://tests/test_case.gd"
## 正式 49 卡的系统级闭环：ComboPlanner / BattleSession / TurnSystem / SaveCodec / RunSession。

const CONTENT_DB_SCRIPT := preload("res://autoload/content_db.gd")


func run() -> Array[String]:
	reset()
	_test_atomic_draw_card_in_real_battle_state()
	_test_choice_card_through_combo_planner()
	_test_direction_card_through_combo_planner()
	_test_scheduled_effects_fire_next_round()
	_test_stun_skips_enemy_action()
	_test_slow_reduces_approach()
	_test_save_codec_preserves_formal_runtime_state()
	_test_battle_result_writes_max_hp_to_run()
	return failures()


func _test_atomic_draw_card_in_real_battle_state() -> void:
	var state := FormalCardFixture.state()
	FormalCardFixture.add_card(state, 7, 7001)
	FormalCardFixture.add_card(state, 28, 7002, DeckState.ZONE_DRAW)
	FormalCardFixture.add_card(state, 29, 7003, DeckState.ZONE_DRAW)
	var defs := FormalCardFixture.defs([7, 28, 29])
	var command := FormalCardFixture.command(1, [7001], [null])
	var result := ComboPlanner.new().build_plan_for_actor(
		state, state.deck, command, defs, FormalCardFixture.rng("atomic-draw")
	)
	assert_true(bool(result.get("ok", false)), "躁动应能在真实 BattleState 中通过 ComboPlanner 结算")
	if bool(result.get("ok", false)):
		var out := result["state_out"] as BattleState
		assert_equal(out.get_unit(1).block, 4, "躁动真实战斗获得4护甲")
		assert_equal(out.deck.zone_of(7001), DeckState.ZONE_DISCARD, "躁动打出后进入弃牌堆")
		assert_equal(out.deck.hand.size(), 2, "躁动真实战斗抽2张牌")


func _test_choice_card_through_combo_planner() -> void:
	var state := FormalCardFixture.state()
	FormalCardFixture.add_card(state, 6, 6001)
	FormalCardFixture.add_card(state, 28, 6002)
	FormalCardFixture.add_card(state, 40, 6003)
	FormalCardFixture.add_card(state, 44, 6004)
	var defs := FormalCardFixture.defs([6, 28, 40, 44])
	var invalid := FormalCardFixture.command(1, [6004], [null])
	var rejected := ComboPlanner.new().build_plan_for_actor(
		state, state.deck, invalid, defs, FormalCardFixture.rng("choice-invalid")
	)
	assert_true(not bool(rejected.get("ok", false)), "应激格挡缺少必选手牌时必须拒绝")
	assert_equal(rejected.get("error_code"), ComboPlanner.ERROR_COMBO, "缺少选牌按 combo 输入错误处理")

	var command := FormalCardFixture.command(1, [6001], [null], {6001: [6002, 6003]})
	var result := ComboPlanner.new().build_plan_for_actor(
		state, state.deck, command, defs, FormalCardFixture.rng("choice-valid")
	)
	assert_true(bool(result.get("ok", false)), "遣散应通过正式 ComboPlanner 结算")
	if bool(result.get("ok", false)):
		var out := result["state_out"] as BattleState
		assert_equal(out.get_unit(1).block, 16, "遣散2张获得16护甲")
		assert_equal(out.deck.zone_of(6001), DeckState.ZONE_EXHAUST, "遣散自身为消耗牌")
		assert_equal(out.deck.zone_of(6002), DeckState.ZONE_EXHAUST, "所选牌1进入消耗区")
		assert_equal(out.deck.zone_of(6003), DeckState.ZONE_EXHAUST, "所选牌2进入消耗区")
	assert_equal(state.deck.zone_of(6001), DeckState.ZONE_HAND, "规划不得污染权威输入牌区")


func _test_direction_card_through_combo_planner() -> void:
	var state := FormalCardFixture.state(30, 30, 40, Vector2i(2, 2), Vector2i(5, 2))
	FormalCardFixture.add_card(state, 13, 13001)
	var defs := FormalCardFixture.defs([13])
	var command := FormalCardFixture.command(
		1, [13001], [FormalCardFixture.direction_target(Vector2i.RIGHT)]
	)
	var result := ComboPlanner.new().build_plan_for_actor(
		state, state.deck, command, defs, FormalCardFixture.rng("dash-combo")
	)
	assert_true(bool(result.get("ok", false)), "冲刺斩应通过正式 ComboPlanner 方向目标结算")
	if bool(result.get("ok", false)):
		var out := result["state_out"] as BattleState
		assert_equal(out.board.get_unit_cell(1), Vector2i(4, 2), "冲刺斩正式路径移动到敌人前")
		assert_equal(out.get_unit(2).hp, 20, "冲刺2格造成20伤害")
		assert_equal(out.deck.zone_of(13001), DeckState.ZONE_DISCARD, "冲刺斩结算后进入弃牌堆")


func _test_scheduled_effects_fire_next_round() -> void:
	var state := FormalCardFixture.state()
	state.phase = BattleState.Phase.ROUND_END
	state.round_index = 1
	state.hand_size = 0
	FormalCardFixture.add_card(state, 28, 23002, DeckState.ZONE_DRAW)
	state.scheduled_effects = [
		{"round": 2, "kind": &"draw", "count": 1, "source_unit_id": 1},
		{"round": 2, "kind": &"block", "amount": 9, "source_unit_id": 1},
	]
	var result := TurnSystem.new().begin_round(state, FormalCardFixture.rng("scheduled"), {})
	assert_true(bool(result.get("ok", false)), "下一回合延迟效果应成功兑现")
	assert_equal(state.round_index, 2, "进入第2回合")
	assert_equal(state.deck.zone_of(23002), DeckState.ZONE_HAND, "#23 延迟额外抽1张")
	assert_equal(state.get_unit(1).block, 9, "#43 延迟获得9护甲")
	assert_equal(state.scheduled_effects.size(), 0, "已兑现延迟效果从队列移除")


func _test_stun_skips_enemy_action() -> void:
	var streams := Phase3Fixture.rng("stun-runtime")
	var state := Phase3Fixture.base_state(
		streams, 20, 20, Vector2i(0, 0), Vector2i(1, 0), DeckState.new(), 0, 3, 0
	)
	var stun := StatusState.new()
	stun.instance_id = 5001
	stun.status_id = StatusRules.STUN
	stun.stacks = 1
	stun.duration = 1
	state.get_unit(2).set_status(stun.instance_id, stun)
	var session := Phase3Fixture.session(
		state, streams, {}, Phase3Fixture.behavior([Phase3Fixture.attack_action(&"enemy.stunned_attack", 7)])
	)
	var command := EndTurnCommand.new()
	command.command_id = 5002
	command.actor_id = 1
	var result := session.submit(command)
	assert_true(result.accepted, "眩晕敌人的回合推进应正常完成")
	assert_equal(session.state.get_unit(1).hp, 20, "眩晕敌人跳过本次7伤攻击")
	assert_equal(StatusRules.stacks(session.state.get_unit(2), StatusRules.STUN), 0, "跳过行动后眩晕到期")


func _test_slow_reduces_approach() -> void:
	var streams := Phase3Fixture.rng("slow-runtime")
	var state := Phase3Fixture.base_state(
		streams, 20, 20, Vector2i(0, 0), Vector2i(0, 4), DeckState.new(), 0, 3, 0
	)
	var slow := StatusState.new()
	slow.instance_id = 5101
	slow.status_id = StatusRules.SLOW
	slow.stacks = 1
	slow.duration = 1
	state.get_unit(2).set_status(slow.instance_id, slow)
	var action := EnemyActionDef.new()
	action.id = &"enemy.slow_approach"
	action.kind = EnemyActionDef.Kind.APPROACH
	action.target_policy = EnemyActionDef.TargetPolicy.PLAYER
	action.move_steps = 2
	var session := Phase3Fixture.session(state, streams, {}, Phase3Fixture.behavior([action]))
	var command := EndTurnCommand.new()
	command.command_id = 5102
	command.actor_id = 1
	var result := session.submit(command)
	assert_true(result.accepted, "钝足敌人的回合推进应正常完成")
	assert_equal(session.state.board.get_unit_cell(2), Vector2i(0, 3), "钝足使原本2格接近只移动1格")
	assert_equal(StatusRules.stacks(session.state.get_unit(2), StatusRules.SLOW), 0, "行动结束后钝足到期")


func _test_save_codec_preserves_formal_runtime_state() -> void:
	var state := FormalCardFixture.state()
	var card := FormalCardFixture.add_card(state, 37, 5201)
	card.damage_modifier = 4
	card.block_modifier = 3
	card.runtime_data = {"stacked_block": 8, "turn_damage_bonus": 6}
	state.scheduled_effects = [{"round": 2, "kind": &"draw", "count": 1, "source_unit_id": 1}]
	state.ground_items[Vector2i(4, 4)] = [&"item.test"]
	state.collected_items = [&"item.old"]
	state.run_changes = {"max_hp_delta": 3}
	var codec := SaveCodec.new()
	var decoded := codec.decode_state(codec.encode_state(state))
	assert_true(decoded != null, "正式卡扩展状态应可 SaveCodec 往返")
	if decoded == null:
		return
	var out := decoded as BattleState
	var out_card := out.deck.get_card(5201)
	assert_equal(out_card.damage_modifier, 4, "保存战斗内伤害修正")
	assert_equal(out_card.block_modifier, 3, "保存战斗内护甲修正")
	assert_equal(int(out_card.runtime_data.get("stacked_block", 0)), 8, "保存单卡战斗态")
	assert_equal(out.scheduled_effects.size(), 1, "保存延迟效果队列")
	assert_true(out.ground_items.has(Vector2i(4, 4)), "保存地面物件")
	assert_true(out.collected_items.has(&"item.old"), "保存已收集物件")
	assert_equal(int(out.run_changes.get("max_hp_delta", 0)), 3, "保存待写回Run变化")


func _test_battle_result_writes_max_hp_to_run() -> void:
	var content: Object = CONTENT_DB_SCRIPT.new()
	assert_true(bool(content.call("load_catalog", "res://content/catalog.tres")), "正式 catalog 应加载")
	var run := RunSession.create_run(&"character.hero", "formal-max-hp", content)
	var session := RunSession.new()
	session.setup(run, content)
	session.enter_node(session.available_node_ids()[0])
	var max_before := run.max_hp
	var result := BattleResult.new()
	result.victory = true
	result.battle_id = session.state.pending_battle_id
	result.persistent_changes = {
		"max_hp_delta": 3,
		"player_hp": {EncounterBuilder.PLAYER_UNIT_ID: run.hp},
	}
	var outcome := session.on_battle_finished(result)
	assert_equal(String(outcome.get("kind", "")), "victory", "饮血剑永久变化通过正常胜利路径写回")
	assert_equal(session.state.max_hp, max_before + 3, "RunState 最大生命永久+3")
