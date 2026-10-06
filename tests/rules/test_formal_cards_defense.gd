extends "res://tests/test_case.gd"
## 防御牌 37~49：补测除第一批 40/42 外的正式行为。


func run() -> Array[String]:
	reset()
	_test_37_stacking_defense()
	_test_38_hold_back()
	_test_39_defense_secret()
	_test_41_proper_defense()
	_test_43_regenerating_shell()
	_test_44_stress_block()
	_test_45_cornered_armor()
	_test_46_heal()
	_test_47_control()
	_test_48_rooted_defense()
	_test_49_guarding_hand()
	return failures()


func _test_37_stacking_defense() -> void:
	var state := FormalCardFixture.state()
	var card := FormalCardFixture.add_card(state, 37, 3701)
	FormalCardRules.on_card_drawn(card)
	FormalCardRules.on_card_drawn(card)
	assert_equal(int(card.runtime_data.get("stacked_block", 0)), 8, "堆叠防守抽到2次累计8护甲")
	var result := FormalCardFixture.resolve(state, 37, 3701)
	assert_true(bool(result.get("ok", false)), "堆叠防守应成功")
	if bool(result.get("ok", false)):
		var out := result["state_out"] as BattleState
		assert_equal(out.get_unit(1).block, 8, "打出获得当前累计8护甲")
		assert_equal(int(out.deck.get_card(3701).runtime_data.get("stacked_block", -1)), 0, "打出后累计归零")


func _test_38_hold_back() -> void:
	var state := FormalCardFixture.state()
	FormalCardFixture.add_card(state, 38, 3801)
	FormalCardFixture.add_card(state, 28, 3802, DeckState.ZONE_DRAW)
	var result := FormalCardFixture.resolve(state, 38, 3801)
	assert_true(bool(result.get("ok", false)), "留一手应成功")
	if bool(result.get("ok", false)):
		var out := result["state_out"] as BattleState
		assert_equal(out.get_unit(1).block, 5, "获得5护甲")
		assert_equal(out.deck.zone_of(3802), DeckState.ZONE_HAND, "抽1张牌")
		assert_equal(out.deck.get_card(3802).upgrade_level, 1, "抽到的牌立即升级")


func _test_39_defense_secret() -> void:
	var state := FormalCardFixture.state()
	FormalCardFixture.add_card(state, 39, 3901)
	FormalCardFixture.add_card(state, 28, 3902)
	FormalCardFixture.add_card(state, 29, 3903)
	var command := FormalCardFixture.command(1, [3901, 3902, 3903], [null, null, null])
	var result := FormalCardFixture.resolve(state, 39, 3901, null, command)
	assert_true(bool(result.get("ok", false)), "防守秘术应成功")
	if bool(result.get("ok", false)):
		assert_equal((result["state_out"] as BattleState).get_unit(1).block, 11, "5基础+2张其他牌*3=11护甲")


func _test_41_proper_defense() -> void:
	var state := FormalCardFixture.state()
	FormalCardFixture.add_card(state, 41, 4101)
	FormalCardFixture.add_card(state, 14, 4102)
	var defs := FormalCardFixture.defs([41, 14])
	var result := FormalCardFixture.resolve(state, 41, 4101, null, null, defs)
	assert_true(bool(result.get("ok", false)), "恰当防守应成功")
	if bool(result.get("ok", false)):
		assert_equal((result["state_out"] as BattleState).get_unit(1).block, 16, "手牌有招式：5+11=16护甲")


func _test_43_regenerating_shell() -> void:
	var state := FormalCardFixture.state()
	FormalCardFixture.add_card(state, 43, 4301)
	var result := FormalCardFixture.resolve(state, 43, 4301)
	assert_true(bool(result.get("ok", false)), "再生硬壳应成功")
	if bool(result.get("ok", false)):
		var out := result["state_out"] as BattleState
		assert_equal(out.get_unit(1).block, 9, "本回合获得9护甲")
		assert_equal(out.scheduled_effects.size(), 1, "登记下回合护甲效果")
		assert_equal(StringName(String(out.scheduled_effects[0].get("kind", ""))), &"block", "延迟效果类型为block")
		assert_equal(int(out.scheduled_effects[0].get("amount", 0)), 9, "下回合再获得9护甲")


func _test_44_stress_block() -> void:
	var state := FormalCardFixture.state()
	FormalCardFixture.add_card(state, 44, 4401)
	FormalCardFixture.add_card(state, 28, 4402)
	var defs := FormalCardFixture.defs([44, 28])
	var command := FormalCardFixture.command(1, [4401], [null], {4401: [4402]})
	var result := FormalCardFixture.resolve(state, 44, 4401, null, command, defs)
	assert_true(bool(result.get("ok", false)), "应激格挡应成功")
	if bool(result.get("ok", false)):
		var out := result["state_out"] as BattleState
		assert_equal(out.get_unit(1).block, 10, "获得10护甲")
		assert_equal(out.deck.zone_of(4402), DeckState.ZONE_DISCARD, "所选手牌进入弃牌堆")


func _test_45_cornered_armor() -> void:
	var state := FormalCardFixture.state(30, 30, 30, Vector2i(2, 2), Vector2i(3, 2))
	FormalCardFixture.add_enemy(state, 3, 30, Vector2i(2, 4))
	FormalCardFixture.add_enemy(state, 4, 30, Vector2i(7, 7))
	FormalCardFixture.add_card(state, 45, 4501)
	var result := FormalCardFixture.resolve(state, 45, 4501)
	assert_true(bool(result.get("ok", false)), "困兽之甲应成功")
	if bool(result.get("ok", false)):
		assert_equal((result["state_out"] as BattleState).get_unit(1).block, 16, "2格内2敌人 => 16护甲")


func _test_46_heal() -> void:
	var state := FormalCardFixture.state(20, 30)
	var card := FormalCardFixture.add_card(state, 46, 4601)
	for _i in range(4):
		FormalCardRules.on_card_drawn(card)
	assert_equal(int(card.runtime_data.get("heal_charge", 0)), 9, "疗伤累计恢复量上限9")
	var result := FormalCardFixture.resolve(state, 46, 4601)
	assert_true(bool(result.get("ok", false)), "疗伤应成功")
	if bool(result.get("ok", false)):
		assert_equal((result["state_out"] as BattleState).get_unit(1).hp, 29, "当前9点恢复量实际回血9")


func _test_47_control() -> void:
	var state := FormalCardFixture.state()
	FormalCardFixture.add_card(state, 47, 4701)
	var result := FormalCardFixture.resolve(state, 47, 4701)
	assert_true(bool(result.get("ok", false)), "掌控应成功")
	if bool(result.get("ok", false)):
		var out := result["state_out"] as BattleState
		assert_equal(out.get_unit(1).block, 13, "获得13护甲")
		assert_equal(out.get_unit(1).get_resource(&"courage"), 5, "紧邻敌人时+5勇气")


func _test_48_rooted_defense() -> void:
	var state := FormalCardFixture.state(30, 30, 30, Vector2i(2, 2), Vector2i(3, 2), 3)
	FormalCardFixture.add_card(state, 48, 4801)
	var result := FormalCardFixture.resolve(state, 48, 4801)
	assert_true(bool(result.get("ok", false)), "扎根防守应成功")
	if bool(result.get("ok", false)):
		var out := result["state_out"] as BattleState
		assert_equal(out.get_unit(1).get_resource(TurnSystem.MOVE_RESOURCE), 0, "消耗全部移动点")
		assert_equal(out.get_unit(1).block, 9, "3移动点*3=9护甲")


func _test_49_guarding_hand() -> void:
	var state := FormalCardFixture.state()
	FormalCardFixture.add_card(state, 49, 4901)
	FormalCardFixture.add_card(state, 28, 4902)
	var command := FormalCardFixture.command(
		1, [4901, 4902], [null, FormalCardFixture.unit_target(2)]
	)
	var defs := FormalCardFixture.defs([49, 28])
	FormalCardRules.apply_combo_pre_modifiers(state, command, defs)
	var other := state.deck.get_card(4902)
	assert_equal(other.block_modifier, 3, "守护之手使其他同出牌本场获得+3护甲")
	var prepared := FormalCardRules.prepare_effects(other, FormalCardFixture.definition(28), 1)
	var found_block := false
	for value: Variant in prepared:
		if value is Dictionary and StringName(String((value as Dictionary).get("type_key", ""))) == &"block":
			found_block = int((value as Dictionary).get("params", {}).get("amount", 0)) == 3
	assert_true(found_block, "即使其他牌原本不产护甲，也应额外获得3护甲效果")
