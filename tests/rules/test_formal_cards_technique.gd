extends "res://tests/test_case.gd"
## 招式牌 13~17 专项行为。


func run() -> Array[String]:
	reset()
	_test_13_dash_slash()
	_test_14_kick_backflip()
	_test_15_hook()
	_test_16_whirlwind()
	_test_17_throwing_knife()
	return failures()


func _test_13_dash_slash() -> void:
	var state := FormalCardFixture.state(30, 30, 40, Vector2i(2, 2), Vector2i(5, 2))
	FormalCardFixture.add_card(state, 13, 1301)
	var result := FormalCardFixture.resolve(
		state, 13, 1301, FormalCardFixture.direction_target(Vector2i.RIGHT)
	)
	assert_true(bool(result.get("ok", false)), "冲刺斩应成功")
	if bool(result.get("ok", false)):
		var out := result["state_out"] as BattleState
		assert_equal(out.board.get_unit_cell(1), Vector2i(4, 2), "遇敌前停下，实际冲刺2格")
		assert_equal(out.get_unit(2).hp, 20, "10基础+每格5，冲刺2格造成20伤害")


func _test_14_kick_backflip() -> void:
	var state := FormalCardFixture.state(30, 30, 30, Vector2i(3, 3), Vector2i(4, 3))
	FormalCardFixture.add_card(state, 14, 1401)
	var result := FormalCardFixture.resolve(state, 14, 1401, FormalCardFixture.unit_target(2))
	assert_true(bool(result.get("ok", false)), "蹬踢后翻应成功")
	if bool(result.get("ok", false)):
		var out := result["state_out"] as BattleState
		assert_equal(out.get_unit(2).hp, 21, "造成9伤害")
		assert_equal(out.board.get_unit_cell(2), Vector2i(5, 3), "敌人后退1格")
		assert_equal(out.board.get_unit_cell(1), Vector2i(2, 3), "自己后退1格")


func _test_15_hook() -> void:
	var state := FormalCardFixture.state(30, 30, 30, Vector2i(2, 2), Vector2i(5, 2))
	FormalCardFixture.add_card(state, 15, 1501)
	var target := FormalCardFixture.unit_target(2)
	assert_true(
		bool(FormalCardRules.validate_target(state, 1, FormalCardFixture.definition(15), target).get("ok", false)),
		"抓钩直线3格目标应合法"
	)
	var result := FormalCardFixture.resolve(state, 15, 1501, target)
	assert_true(bool(result.get("ok", false)), "抓钩应成功")
	if bool(result.get("ok", false)):
		var out := result["state_out"] as BattleState
		assert_equal(out.board.get_unit_cell(2), Vector2i(3, 2), "目标实际拖回2格")
		assert_equal(out.get_unit(2).hp, 24, "5伤害按拖2格+24%后取整为6")


func _test_16_whirlwind() -> void:
	var state := FormalCardFixture.state(30, 30, 30, Vector2i(3, 3), Vector2i(4, 3))
	FormalCardFixture.add_enemy(state, 3, 30, Vector2i(3, 4))
	FormalCardFixture.add_enemy(state, 4, 30, Vector2i(6, 6))
	FormalCardFixture.add_card(state, 16, 1601)
	var result := FormalCardFixture.resolve(state, 16, 1601)
	assert_true(bool(result.get("ok", false)), "旋风斩应成功")
	if bool(result.get("ok", false)):
		var out := result["state_out"] as BattleState
		assert_equal(out.get_unit(2).hp, 25, "邻接敌人1受到5伤害")
		assert_equal(out.get_unit(3).hp, 25, "邻接敌人2受到5伤害")
		assert_equal(out.get_unit(4).hp, 30, "非周身8格敌人不受伤")
		assert_equal(out.get_unit(1).block, 4, "命中2人获得4护甲")


func _test_17_throwing_knife() -> void:
	var state := FormalCardFixture.state(30, 30, 30, Vector2i(2, 2), Vector2i(5, 2))
	FormalCardFixture.add_card(state, 17, 1701)
	var target := FormalCardFixture.unit_target(2)
	var result := FormalCardFixture.resolve(state, 17, 1701, target)
	assert_true(bool(result.get("ok", false)), "飞刀应成功")
	if bool(result.get("ok", false)):
		var out := result["state_out"] as BattleState
		assert_equal(out.get_unit(2).hp, 22, "飞刀造成8伤害")
		assert_equal(StatusRules.stacks(out.get_unit(2), StatusRules.KNIFE_MARK), 1, "附加1层飞刀标记")
		var status: StatusState = out.get_unit(2).statuses.values()[0] as StatusState
		assert_equal(status.duration, -1, "飞刀标记应持续到显式取回")
