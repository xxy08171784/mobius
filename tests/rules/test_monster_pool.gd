extends "res://tests/test_case.gd"
## 怪物池抽取测试：前 2 战固定 2 只、其后 2~4、确定性、有放回、合成 EncounterDef 合法。


func run() -> Array[String]:
	reset()
	_test_early_battles_fixed_two()
	_test_later_battles_range()
	_test_deterministic()
	_test_ids_from_pool()
	_test_build_encounter()
	return failures()


func _pool() -> MonsterPoolDef:
	var p := MonsterPoolDef.new()
	p.id = &"monster_pool.test"
	p.tier = &"monster"
	p.enemy_ids = [&"enemy.a", &"enemy.b", &"enemy.c", &"enemy.d"]
	return p


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _test_early_battles_fixed_two() -> void:
	var p := _pool()
	assert_equal(MonsterPool.draw_count(1, _rng(1)), 2, "第 1 战固定 2 只")
	assert_equal(MonsterPool.draw_count(2, _rng(2)), 2, "第 2 战固定 2 只")
	assert_equal(MonsterPool.draw_ids(p, 1, _rng(3)).size(), 2, "第 1 战抽到 2 只")
	assert_equal(MonsterPool.draw_ids(p, 2, _rng(4)).size(), 2, "第 2 战抽到 2 只")


func _test_later_battles_range() -> void:
	var p := _pool()
	for battle in range(3, 60):
		var count := MonsterPool.draw_count(battle, _rng(battle))
		assert_true(count >= 2 and count <= 4, "第 %d 战数量应在 2~4（实际 %d）" % [battle, count])


func _test_deterministic() -> void:
	var p := _pool()
	var a := MonsterPool.draw_ids(p, 5, _rng(777))
	var b := MonsterPool.draw_ids(p, 5, _rng(777))
	assert_equal(a, b, "同种子同战斗序号 -> 相同结果")


func _test_ids_from_pool() -> void:
	var p := _pool()
	var ids := MonsterPool.draw_ids(p, 9, _rng(42))
	assert_true(ids.size() >= 2 and ids.size() <= 4, "抽取数量 2~4")
	for id: StringName in ids:
		assert_true(p.enemy_ids.has(id), "抽到的 ID 必须来自池")


func _test_build_encounter() -> void:
	var p := _pool()
	var encounter := MonsterPool.build_encounter(p, 5, _rng(11))
	assert_true(encounter != null and encounter.is_valid(), "合成 EncounterDef 应合法")
	assert_true(encounter.enemy_ids.size() >= 2 and encounter.enemy_ids.size() <= 4, "组成数量 2~4")
	assert_equal(encounter.tier, &"monster", "层级沿用池")
	assert_equal(encounter.board_cols, 8, "棋盘参数沿用池")

	var empty := MonsterPoolDef.new()
	empty.id = &"monster_pool.empty"
	assert_equal(MonsterPool.build_encounter(empty, 5, _rng(1)), null, "空池 -> null")
