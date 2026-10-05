extends "res://tests/test_case.gd"
## RunState 数据/计数器/深拷贝独立性测试。


func run() -> Array[String]:
	reset()
	_test_counters_and_cards()
	_test_relics()
	_test_clone_independence()
	_test_clone_map_independence()
	return failures()


func _state() -> RunState:
	var state := RunState.new()
	state.run_id = 7
	state.seed = "12345"
	state.character_id = &"character.hero"
	state.hp = 24
	state.max_hp = 30
	state.gold = 50
	return state


func _test_counters_and_cards() -> void:
	var state := _state()
	var a := state.add_card(&"card.warrior.strike")
	var b := state.add_card(&"card.warrior.strike")
	var c := state.make_card(&"card.warrior.guard")
	assert_not_equal(a.run_uid, b.run_uid, "同名卡 UID 必须不同")
	assert_equal(a.run_uid, 1, "首张卡 run_uid 从 1 起")
	assert_equal(state.next_card_uid, 4, "三次建卡后计数器为 4")
	assert_true(state.get_card(b.run_uid) == b, "get_card 按 run_uid 取")
	assert_true(state.get_card(c.run_uid) == null, "未加入卡组的卡取不到")
	assert_equal(state.deck.size(), 2, "make_card 不自动入组")
	assert_true(state.remove_card(a.run_uid), "remove_card 成功")
	assert_true(state.get_card(a.run_uid) == null, "移除后取不到")
	assert_true(not state.remove_card(999), "移除不存在卡返回 false")


func _test_relics() -> void:
	var state := _state()
	var r1 := state.add_relic(&"relic.loop_compass")
	var r2 := state.add_relic(&"relic.loop_compass")
	assert_not_equal(r1.instance_id, r2.instance_id, "同名遗物实例 ID 必须不同")
	assert_true(state.get_relic(r2.instance_id) == r2, "get_relic 按 instance_id 取")
	assert_true(state.has_relic(&"relic.loop_compass"), "has_relic 命中")
	assert_true(not state.has_relic(&"relic.mobius_coin"), "has_relic 未命中")
	assert_equal(state.allocate_battle_id(), 1, "首个 battle_id")
	assert_equal(state.allocate_battle_id(), 2, "battle_id 单调递增")


func _test_clone_independence() -> void:
	var state := _state()
	var card := state.add_card(&"card.warrior.strike")
	var relic := state.add_relic(&"relic.loop_compass")
	relic.set_counter(&"used", 3)
	state.rng_snapshot = {"seed": "12345", "states": {"battle": "999"}}

	var copy := state.duplicate_state()
	assert_equal(copy.deck.size(), 1, "副本卡组数量一致")
	assert_equal(copy.relics.size(), 1, "副本遗物数量一致")
	assert_equal(copy.hp, state.hp, "副本 HP 一致")

	# 改副本不应影响原状态。
	copy.hp = 1
	copy.gold = 0
	copy.deck[0].upgrade_level = 5
	copy.relics[0].set_counter(&"used", 99)
	copy.next_battle_id = 777
	copy.rng_snapshot["states"]["battle"] = "0"

	assert_equal(state.hp, 24, "副本改 HP 不影响原")
	assert_equal(state.gold, 50, "副本改金币不影响原")
	assert_equal(card.upgrade_level, 0, "副本改卡升级不影响原卡")
	assert_equal(state.relics[0].get_counter(&"used"), 3, "副本改遗物计数不影响原")
	assert_equal(state.next_battle_id, 1, "副本改计数器不影响原")
	assert_equal(state.rng_snapshot["states"]["battle"], "999", "副本改 RNG 快照不影响原")


func _test_clone_map_independence() -> void:
	var state := _state()
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	state.map = MapGenerator.generate(RouteMapDef.new(), rng)

	var copy := state.duplicate_state()
	assert_equal(copy.map.nodes.size(), state.map.nodes.size(), "副本地图节点数一致")
	assert_true(copy.map.boss_id == state.map.boss_id, "副本 boss_id 一致")

	# 改副本地图（访问态 / 类型 / 边）不应影响原图。
	var an_entry: int = copy.map.entry_ids[0]
	copy.map.mark_visited(an_entry)
	assert_true(not state.map.get_node(an_entry).visited, "副本标记 visited 不影响原图")

	var some_id: int = copy.map.nodes.keys()[0]
	copy.map.get_node(some_id).type_key = &"__mutated__"
	assert_not_equal(state.map.get_node(some_id).type_key, &"__mutated__", "副本改类型不影响原图")

	copy.map.get_node(some_id).next_ids.append(999999)
	assert_true(not state.map.get_node(some_id).next_ids.has(999999), "副本改边不影响原图")
