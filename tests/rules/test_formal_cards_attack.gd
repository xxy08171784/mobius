extends "res://tests/test_case.gd"
## 攻击牌 18~36：补测除第一批 24/28/29/32/34/36 外的正式行为。


func run() -> Array[String]:
	reset()
	_test_18_blood_sword()
	_test_19_demon_blade()
	_test_20_stun()
	_test_21_attack_secret()
	_test_22_execution_blade()
	_test_23_heavy_strike()
	_test_25_brawl()
	_test_26_training()
	_test_27_technique_synergy()
	_test_30_cornered_power()
	_test_31_knee_arrow()
	_test_33_overflow()
	_test_35_rooted_attack()
	return failures()


func _test_18_blood_sword() -> void:
	var state := FormalCardFixture.state(20, 30, 9)
	FormalCardFixture.add_card(state, 18, 1801)
	var result := FormalCardFixture.resolve(state, 18, 1801, FormalCardFixture.unit_target(2))
	assert_true(bool(result.get("ok", false)), "饮血剑击杀应成功")
	if bool(result.get("ok", false)):
		var out := result["state_out"] as BattleState
		assert_equal(out.get_unit(2).hp, 0, "9伤害击杀9血敌人")
		assert_equal(out.get_unit(1).max_hp, 33, "击杀永久增加3最大生命")
		assert_equal(out.get_unit(1).hp, 23, "击杀恢复3生命")
		assert_equal(int(out.run_changes.get("max_hp_delta", 0)), 3, "战斗结果记录Run层最大生命增量")


func _test_19_demon_blade() -> void:
	var state := FormalCardFixture.state()
	FormalCardFixture.add_card(state, 19, 1901)
	var target := FormalCardFixture.unit_target(2)
	var result := FormalCardFixture.resolve(state, 19, 1901, target)
	assert_true(bool(result.get("ok", false)), "妖刀第一次攻击应成功")
	if not bool(result.get("ok", false)):
		return
	var out := result["state_out"] as BattleState
	assert_equal(out.get_unit(2).hp, 24, "第一次造成6伤害")
	assert_equal(out.deck.get_card(1901).damage_modifier, 2, "真正掉血后本场伤害+2")
	result = FormalCardFixture.resolve(out, 19, 1901, target)
	if bool(result.get("ok", false)):
		var out2 := result["state_out"] as BattleState
		assert_equal(out2.get_unit(2).hp, 16, "第二次应造成8伤害")
		assert_equal(out2.deck.get_card(1901).damage_modifier, 4, "再次掉血后继续累计+2")


func _test_20_stun() -> void:
	var state := FormalCardFixture.state()
	FormalCardFixture.add_card(state, 20, 2001)
	var result := FormalCardFixture.resolve(state, 20, 2001, FormalCardFixture.unit_target(2))
	assert_true(bool(result.get("ok", false)), "击晕应成功")
	if bool(result.get("ok", false)):
		var out := result["state_out"] as BattleState
		assert_equal(out.get_unit(2).hp, 18, "击晕造成12伤害")
		assert_true(StatusRules.is_stunned(out.get_unit(2)), "目标获得眩晕")


func _test_21_attack_secret() -> void:
	var state := FormalCardFixture.state()
	FormalCardFixture.add_card(state, 21, 2101)
	FormalCardFixture.add_card(state, 28, 2102)
	FormalCardFixture.add_card(state, 29, 2103)
	var target := FormalCardFixture.unit_target(2)
	var command := FormalCardFixture.command(1, [2101, 2102, 2103], [target, target, target])
	var result := FormalCardFixture.resolve(state, 21, 2101, target, command)
	assert_true(bool(result.get("ok", false)), "进攻秘术应成功")
	if bool(result.get("ok", false)):
		assert_equal((result["state_out"] as BattleState).get_unit(2).hp, 15, "重影刀计2、英勇打击计1：6+3*3=15伤害")


func _test_22_execution_blade() -> void:
	var state := FormalCardFixture.state()
	var bleed := StatusState.new()
	bleed.instance_id = 220
	bleed.status_id = StatusRules.BLEED
	bleed.stacks = 1
	bleed.duration = 2
	state.get_unit(2).set_status(220, bleed)
	FormalCardFixture.add_card(state, 22, 2201)
	var result := FormalCardFixture.resolve(state, 22, 2201, FormalCardFixture.unit_target(2))
	assert_true(bool(result.get("ok", false)), "索命刀应成功")
	if bool(result.get("ok", false)):
		assert_equal((result["state_out"] as BattleState).get_unit(2).hp, 18, "负面状态目标承受2倍即12伤害")


func _test_23_heavy_strike() -> void:
	var state := FormalCardFixture.state()
	FormalCardFixture.add_card(state, 23, 2301)
	var result := FormalCardFixture.resolve(state, 23, 2301, FormalCardFixture.unit_target(2))
	assert_true(bool(result.get("ok", false)), "重击应成功")
	if bool(result.get("ok", false)):
		var out := result["state_out"] as BattleState
		assert_equal(out.get_unit(2).hp, 20, "重击造成10伤害")
		assert_equal(out.scheduled_effects.size(), 1, "登记一个下回合延迟效果")
		assert_equal(StringName(String(out.scheduled_effects[0].get("kind", ""))), &"draw", "延迟效果为额外抽牌")
		assert_equal(int(out.scheduled_effects[0].get("round", 0)), 2, "在下一回合触发")


func _test_25_brawl() -> void:
	var far := FormalCardFixture.state(30, 30, 30, Vector2i(2, 2), Vector2i(4, 2))
	var target := FormalCardFixture.unit_target(2)
	assert_true(
		not bool(FormalCardRules.validate_target(far, 1, FormalCardFixture.definition(25), target).get("ok", false)),
		"肉搏不能攻击不紧邻敌人"
	)
	var state := FormalCardFixture.state()
	FormalCardFixture.add_card(state, 25, 2501)
	var result := FormalCardFixture.resolve(state, 25, 2501, FormalCardFixture.unit_target(2))
	assert_true(bool(result.get("ok", false)), "紧邻时肉搏应成功")
	if bool(result.get("ok", false)):
		assert_equal((result["state_out"] as BattleState).get_unit(2).hp, 18, "肉搏造成12伤害")


func _test_26_training() -> void:
	var state := FormalCardFixture.state()
	FormalCardFixture.add_card(state, 26, 2601)
	FormalCardFixture.add_card(state, 14, 2602)
	var command := FormalCardFixture.command(
		1, [2601, 2602], [FormalCardFixture.unit_target(2), FormalCardFixture.unit_target(2)]
	)
	FormalCardRules.apply_combo_pre_modifiers(state, command, FormalCardFixture.defs([26, 14]))
	assert_equal(state.deck.get_card(2602).damage_modifier, 0, "苦练不能在本组结算前增伤")


func _test_27_technique_synergy() -> void:
	var state := FormalCardFixture.state()
	FormalCardFixture.add_card(state, 27, 2701)
	FormalCardFixture.add_card(state, 14, 2702)
	var target := FormalCardFixture.unit_target(2)
	var command := FormalCardFixture.command(1, [2701, 2702], [target, target])
	var defs := FormalCardFixture.defs([27, 14])
	var result := FormalCardFixture.resolve(state, 27, 2701, target, command, defs)
	assert_true(bool(result.get("ok", false)), "妙用招式应成功")
	if bool(result.get("ok", false)):
		assert_equal((result["state_out"] as BattleState).get_unit(2).hp, 21, "基础版取蹬踢后翻基础伤害100%")


func _test_30_cornered_power() -> void:
	var state := FormalCardFixture.state(30, 30, 40, Vector2i(2, 2), Vector2i(3, 2))
	FormalCardFixture.add_enemy(state, 3, 30, Vector2i(2, 4))
	FormalCardFixture.add_enemy(state, 4, 30, Vector2i(7, 7))
	FormalCardFixture.add_card(state, 30, 3001)
	var result := FormalCardFixture.resolve(state, 30, 3001, FormalCardFixture.unit_target(2))
	assert_true(bool(result.get("ok", false)), "困兽之力应成功")
	if bool(result.get("ok", false)):
		assert_equal((result["state_out"] as BattleState).get_unit(2).hp, 30, "2格内2敌人 => 10伤害")


func _test_31_knee_arrow() -> void:
	var state := FormalCardFixture.state()
	FormalCardFixture.add_card(state, 31, 3101)
	var result := FormalCardFixture.resolve(state, 31, 3101, FormalCardFixture.unit_target(2))
	assert_true(bool(result.get("ok", false)), "膝盖一箭应成功")
	if bool(result.get("ok", false)):
		var out := result["state_out"] as BattleState
		assert_equal(out.get_unit(2).hp, 21, "造成9伤害")
		assert_equal(StatusRules.stacks(out.get_unit(2), StatusRules.SLOW), 1, "施加1层钝足")


func _test_33_overflow() -> void:
	var state := FormalCardFixture.state(30, 30, 5, Vector2i(2, 2), Vector2i(3, 2))
	FormalCardFixture.add_enemy(state, 3, 20, Vector2i(4, 2))
	FormalCardFixture.add_enemy(state, 4, 20, Vector2i(7, 7))
	FormalCardFixture.add_card(state, 33, 3301)
	var result := FormalCardFixture.resolve(state, 33, 3301, FormalCardFixture.unit_target(2))
	assert_true(bool(result.get("ok", false)), "砍爆应成功")
	if bool(result.get("ok", false)):
		var out := result["state_out"] as BattleState
		assert_equal(out.get_unit(2).hp, 0, "主目标死亡")
		assert_equal(out.get_unit(3).hp, 16, "9伤打5血产生4溢出，对周围敌人造成4")
		assert_equal(out.get_unit(4).hp, 20, "远处敌人不受溢出影响")


func _test_35_rooted_attack() -> void:
	var state := FormalCardFixture.state(30, 30, 30, Vector2i(2, 2), Vector2i(3, 2), 3)
	FormalCardFixture.add_card(state, 35, 3501)
	var result := FormalCardFixture.resolve(state, 35, 3501, FormalCardFixture.unit_target(2))
	assert_true(bool(result.get("ok", false)), "扎根打击应成功")
	if bool(result.get("ok", false)):
		var out := result["state_out"] as BattleState
		assert_equal(out.get_unit(1).get_resource(TurnSystem.MOVE_RESOURCE), 0, "消耗全部3移动点")
		assert_equal(out.get_unit(2).hp, 18, "3*4=12伤害")
