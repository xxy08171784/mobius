extends "res://tests/test_case.gd"
## 第一批正式奖励卡（07/08/24/28/29/32/34/36/40/42）的数据与原子效果回归。

const IMPLEMENTED := [7, 8, 24, 28, 29, 32, 34, 36, 40, 42]


func run() -> Array[String]:
	reset()
	_test_definitions()
	_test_self_cards()
	_test_enemy_and_mixed_cards()
	_test_push_away_from_source()
	return failures()


func _definition(number: int) -> CardDef:
	return load("res://content/cards/reward/card_%02d.tres" % number) as CardDef


func _rng() -> RngStreams:
	var rng := RngStreams.new()
	rng.derive_streams("first-batch")
	return rng


func _resolve(number: int, state: EffectTestState, target: Variant = null) -> Dictionary:
	var definition := _definition(number)
	return EffectResolver.new().resolve(
		state,
		{
			"context": {"source_unit_id": 1, "target": target},
			"effects": definition.get_effects(),
		},
		_rng()
	)


func _test_definitions() -> void:
	for number: int in IMPLEMENTED:
		var definition := _definition(number)
		assert_true(definition != null, "card %02d resource should load" % number)
		if definition == null:
			continue
		assert_true(definition.reward_pool_enabled, "card %02d should be reward-enabled" % number)
		assert_true(not definition.get_effects().is_empty(), "card %02d should have runtime effects" % number)
	var card_28 := _definition(28)
	var card_40 := _definition(40)
	var card_42 := _definition(42)
	assert_equal(card_28.get_play_count_weight(), 2, "重影刀算作 2 张")
	assert_equal(card_40.get_play_count_weight(), 0, "符甲不计入出牌数")
	assert_equal(card_42.get_play_count_weight(), 2, "重影盾算作 2 张")


func _test_self_cards() -> void:
	var state := EffectTestState.new()
	var result := _resolve(7, state)
	assert_true(bool(result.get("ok", false)), "躁动 should resolve")
	if bool(result.get("ok", false)):
		var out: EffectTestState = result["state_out"]
		assert_equal(int(out.units[1]["block"]), 4, "躁动 +4 护甲")
		assert_equal(out.draw_pile, [103, 104], "躁动抽 2")

	state = EffectTestState.new()
	result = _resolve(8, state)
	assert_true(bool(result.get("ok", false)), "信心 should resolve")
	if bool(result.get("ok", false)):
		var out8: EffectTestState = result["state_out"]
		assert_equal(int(out8.units[1]["resources"]["move_points"]), 3, "信心 +1 移动点")
		assert_equal(int(out8.units[1]["resources"]["courage"]), 5, "信心 +2 勇气")
		assert_equal(out8.draw_pile, [102, 103, 104], "信心抽 1")

	state = EffectTestState.new()
	result = _resolve(40, state)
	assert_true(bool(result.get("ok", false)), "符甲 should resolve")
	if bool(result.get("ok", false)):
		assert_equal(int((result["state_out"] as EffectTestState).units[1]["block"]), 8, "符甲 +8 护盾")

	state = EffectTestState.new()
	result = _resolve(42, state)
	assert_true(bool(result.get("ok", false)), "重影盾 should resolve")
	if bool(result.get("ok", false)):
		assert_equal(int((result["state_out"] as EffectTestState).units[1]["block"]), 6, "重影盾 +6 护盾")


func _test_enemy_and_mixed_cards() -> void:
	var state := EffectTestState.new()
	var result := _resolve(28, state, 2)
	assert_true(bool(result.get("ok", false)), "重影刀 should resolve")
	if bool(result.get("ok", false)):
		assert_equal(int((result["state_out"] as EffectTestState).units[2]["hp"]), 6, "重影刀造成 7 伤害（先扣 3 护盾）")

	state = EffectTestState.new()
	result = _resolve(29, state, 2)
	assert_true(bool(result.get("ok", false)), "英勇打击 should resolve")
	if bool(result.get("ok", false)):
		var out29: EffectTestState = result["state_out"]
		assert_equal(int(out29.units[2]["hp"]), 7, "英勇打击造成 6 伤害")
		assert_equal(int(out29.units[1]["resources"]["courage"]), 5, "英勇打击给自己 +2 勇气")

	state = EffectTestState.new()
	result = _resolve(32, state, 2)
	assert_true(bool(result.get("ok", false)), "打了就跑 should resolve")
	if bool(result.get("ok", false)):
		var out32: EffectTestState = result["state_out"]
		assert_equal(int(out32.units[2]["hp"]), 4, "打了就跑造成 9 伤害")
		assert_equal(int(out32.units[1]["resources"]["move_points"]), 3, "打了就跑给自己 +1 移动点")

	state = EffectTestState.new()
	result = _resolve(34, state, 2)
	assert_true(bool(result.get("ok", false)), "刺透 should resolve")
	if bool(result.get("ok", false)):
		var out34: EffectTestState = result["state_out"]
		assert_equal(int(out34.units[2]["hp"]), 0, "刺透 17 伤害无视护甲")
		assert_equal(int(out34.units[2]["block"]), 3, "刺透不消耗目标护甲")

	state = EffectTestState.new()
	result = _resolve(36, state, 2)
	assert_true(bool(result.get("ok", false)), "攻防一体 should resolve")
	if bool(result.get("ok", false)):
		var out36: EffectTestState = result["state_out"]
		assert_equal(int(out36.units[2]["hp"]), 8, "攻防一体造成 5 伤害")
		assert_equal(int(out36.units[1]["block"]), 4, "攻防一体给自己 +4 护甲")


func _test_push_away_from_source() -> void:
	var board := BoardState.new(6, 6)
	board.place_unit(1, Vector2i(1, 2))
	board.place_unit(2, Vector2i(2, 2))
	var state := {"board": board, "next_event_seq": 1}
	var context := EffectContext.new()
	context.source_unit_id = 1
	context.target = 2
	var result := PushEffectHandler.new().apply(
		state,
		{"params": {"steps": 1, "direction_mode": &"away_from_source"}},
		context,
		RandomNumberGenerator.new()
	)
	assert_true(bool(result.get("ok", false)), "击退的自动远离施法者方向 should resolve")
	assert_equal(board.get_unit_cell(2), Vector2i(3, 2), "目标应沿施法者->目标方向被推 1 格")
