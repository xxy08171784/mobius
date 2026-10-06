extends "res://tests/test_case.gd"
## 技能牌 01~12：补测除第一批 07/08 之外的正式行为。


func run() -> Array[String]:
	reset()
	_test_01_lasso()
	_test_02_requisition()
	_test_03_cautious()
	_test_04_generate_fists()
	_test_05_technique_insight()
	_test_06_dismiss()
	_test_09_inspire()
	_test_10_fear()
	_test_11_courage_burst()
	_test_12_copy()
	return failures()


func _test_01_lasso() -> void:
	var state := FormalCardFixture.state(30, 30, 30, Vector2i(2, 2), Vector2i(4, 2))
	var knife := StatusState.new()
	knife.instance_id = 100
	knife.status_id = StatusRules.KNIFE_MARK
	knife.stacks = 2
	knife.duration = -1
	state.get_unit(2).set_status(100, knife)
	FormalCardFixture.add_card(state, 1, 101)
	var target := FormalCardFixture.cell_target(Vector2i(4, 2))
	assert_true(
		bool(FormalCardRules.validate_target(state, 1, FormalCardFixture.definition(1), target).get("ok", false)),
		"套索应允许直线2格内带飞刀敌人"
	)
	var result := FormalCardFixture.resolve(state, 1, 101, target)
	assert_true(bool(result.get("ok", false)), "套索取回飞刀应成功")
	if bool(result.get("ok", false)):
		var out := result["state_out"] as BattleState
		assert_equal(out.get_unit(2).hp, 18, "2把飞刀各造成6伤害")
		assert_equal(StatusRules.stacks(out.get_unit(2), StatusRules.KNIFE_MARK), 0, "取回后清除飞刀标记")

	state = FormalCardFixture.state(30, 30, 30, Vector2i(2, 2), Vector2i(6, 6))
	FormalCardFixture.add_card(state, 1, 102)
	state.ground_items[Vector2i(3, 2)] = [&"item.test"]
	result = FormalCardFixture.resolve(state, 1, 102, FormalCardFixture.cell_target(Vector2i(3, 2)))
	assert_true(bool(result.get("ok", false)), "套索拾取地面物品应成功")
	if bool(result.get("ok", false)):
		var out_item := result["state_out"] as BattleState
		assert_true(out_item.collected_items.has(&"item.test"), "拾取物进入战斗收集列表")
		assert_true(not out_item.ground_items.has(Vector2i(3, 2)), "地面物品被移除")


func _test_02_requisition() -> void:
	var state := FormalCardFixture.state()
	FormalCardFixture.add_card(state, 2, 201)
	var picked := FormalCardFixture.add_card(state, 28, 202, DeckState.ZONE_DRAW)
	var defs := FormalCardFixture.defs([2, 28])
	var request := FormalCardRules.choice_request(state, 201, [201], defs)
	assert_true(Array(request.get("candidates", [])).has(202), "立刻征用应列出抽牌堆攻击牌")
	var command := FormalCardFixture.command(1, [201], [null], {201: [202]})
	assert_true(FormalCardRules.validate_command_choices(state, command, defs), "立刻征用合法选择应通过")
	var result := FormalCardFixture.resolve(state, 2, 201, null, command, defs)
	assert_true(bool(result.get("ok", false)), "立刻征用应成功")
	if bool(result.get("ok", false)):
		var out := result["state_out"] as BattleState
		assert_equal(out.deck.zone_of(202), DeckState.ZONE_HAND, "所选攻击牌进入手牌")
		var out_card := out.deck.get_card(202)
		assert_equal(int(out_card.runtime_data.get("turn_damage_bonus", 0)), 6, "本回合攻击力+6")
		assert_equal(int(out_card.runtime_data.get("turn_damage_bonus_round", 0)), 1, "临时加成绑定当前回合")
	assert_equal(picked.damage_modifier, 0, "征用的+6不是永久伤害修正")


func _test_03_cautious() -> void:
	var state := FormalCardFixture.state(30, 30, 30, Vector2i(2, 2), Vector2i(3, 2), 3, 4)
	FormalCardFixture.add_card(state, 3, 301)
	var result := FormalCardFixture.resolve(state, 3, 301)
	assert_true(bool(result.get("ok", false)), "谨慎应成功")
	if bool(result.get("ok", false)):
		var out := result["state_out"] as BattleState
		assert_equal(out.get_unit(1).get_resource(&"courage"), 0, "谨慎消耗全部勇气")
		assert_equal(out.get_unit(1).block, 8, "4勇气按每层2护甲转为8护甲")


func _test_04_generate_fists() -> void:
	var state := FormalCardFixture.state()
	FormalCardFixture.add_card(state, 4, 401)
	var result := FormalCardFixture.resolve(state, 4, 401)
	assert_true(bool(result.get("ok", false)), "欧拉欧拉欧拉应成功")
	if bool(result.get("ok", false)):
		var out := result["state_out"] as BattleState
		var fists := 0
		for uid: int in out.deck.hand:
			var card := out.deck.get_card(uid)
			if card != null and card.card_id == FormalCardRules.TOKEN_FIST:
				fists += 1
				assert_true(card.generated, "拳牌应是战斗生成牌")
		assert_equal(fists, 3, "应生成3张拳牌")


func _test_05_technique_insight() -> void:
	var state := FormalCardFixture.state()
	FormalCardFixture.add_card(state, 5, 501)
	FormalCardFixture.add_card(state, 14, 502)
	var defs := FormalCardFixture.defs([5, 14])
	var command := FormalCardFixture.command(1, [501], [null], {501: [502]})
	var result := FormalCardFixture.resolve(state, 5, 501, null, command, defs)
	assert_true(bool(result.get("ok", false)), "招式领悟应成功")
	if bool(result.get("ok", false)):
		var out := result["state_out"] as BattleState
		assert_equal(out.deck.get_card(502).cost_modifier, -1, "所选招式本场费用-1")


func _test_06_dismiss() -> void:
	var state := FormalCardFixture.state()
	FormalCardFixture.add_card(state, 6, 601)
	FormalCardFixture.add_card(state, 28, 602)
	FormalCardFixture.add_card(state, 40, 603)
	var defs := FormalCardFixture.defs([6, 28, 40])
	var command := FormalCardFixture.command(1, [601], [null], {601: [602, 603]})
	var result := FormalCardFixture.resolve(state, 6, 601, null, command, defs)
	assert_true(bool(result.get("ok", false)), "遣散应成功")
	if bool(result.get("ok", false)):
		var out := result["state_out"] as BattleState
		assert_equal(out.deck.zone_of(602), DeckState.ZONE_EXHAUST, "第一张所选牌进入消耗区")
		assert_equal(out.deck.zone_of(603), DeckState.ZONE_EXHAUST, "第二张所选牌进入消耗区")
		assert_equal(out.get_unit(1).block, 16, "消耗2张获得16护甲")


func _test_09_inspire() -> void:
	var state := FormalCardFixture.state()
	FormalCardFixture.add_card(state, 9, 901)
	var result := FormalCardFixture.resolve(state, 9, 901)
	assert_true(bool(result.get("ok", false)), "振奋零勇气应成功")
	if bool(result.get("ok", false)):
		assert_equal((result["state_out"] as BattleState).get_unit(1).get_resource(&"courage"), 7, "零勇气时+7")
	state = FormalCardFixture.state(30, 30, 30, Vector2i(2, 2), Vector2i(3, 2), 3, 2)
	FormalCardFixture.add_card(state, 9, 902)
	result = FormalCardFixture.resolve(state, 9, 902)
	if bool(result.get("ok", false)):
		assert_equal((result["state_out"] as BattleState).get_unit(1).get_resource(&"courage"), 5, "已有勇气时+3")


func _test_10_fear() -> void:
	var state := FormalCardFixture.state(30, 30, 30, Vector2i(2, 2), Vector2i(4, 2))
	FormalCardFixture.add_card(state, 10, 1001)
	var result := FormalCardFixture.resolve(state, 10, 1001, FormalCardFixture.unit_target(2))
	assert_true(bool(result.get("ok", false)), "恐吓应成功")
	if bool(result.get("ok", false)):
		assert_equal((result["state_out"] as BattleState).board.get_unit_cell(2), Vector2i(6, 2), "敌人被吓退2格")


func _test_11_courage_burst() -> void:
	var state := FormalCardFixture.state(30, 30, 30, Vector2i(2, 2), Vector2i(3, 2))
	FormalCardFixture.add_enemy(state, 3, 30, Vector2i(2, 4))
	FormalCardFixture.add_enemy(state, 4, 30, Vector2i(7, 7))
	FormalCardFixture.add_card(state, 11, 1101)
	var result := FormalCardFixture.resolve(state, 11, 1101)
	assert_true(bool(result.get("ok", false)), "勇气迸发应成功")
	if bool(result.get("ok", false)):
		var out := result["state_out"] as BattleState
		assert_equal(out.get_unit(2).hp, 18, "范围内敌人1受到12伤害")
		assert_equal(out.get_unit(3).hp, 18, "范围内敌人2受到12伤害")
		assert_equal(out.get_unit(4).hp, 30, "范围外敌人不受伤")


func _test_12_copy() -> void:
	var state := FormalCardFixture.state()
	FormalCardFixture.add_card(state, 12, 1201)
	FormalCardFixture.add_card(state, 28, 1202)
	var defs := FormalCardFixture.defs([12, 28])
	var command := FormalCardFixture.command(1, [1201], [null], {1201: [1202]})
	var result := FormalCardFixture.resolve(state, 12, 1201, null, command, defs)
	assert_true(bool(result.get("ok", false)), "复制应成功")
	if bool(result.get("ok", false)):
		var out := result["state_out"] as BattleState
		var copies := 0
		for uid: int in out.deck.hand:
			var value := out.deck.get_card(uid)
			if value != null and value.card_id == &"card.reward.28":
				copies += 1
		assert_equal(copies, 2, "手牌中应有原牌+复制牌")
