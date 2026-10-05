extends "res://tests/test_case.gd"

const CONTENT_DB_SCRIPT := preload("res://autoload/content_db.gd")


func run() -> Array[String]:
	reset()
	# 单测试通过 -s 启动时不注入 autoload 全局名，所以直接实例化同一实现脚本。
	var db := CONTENT_DB_SCRIPT.new()
	assert_true(db.load_catalog("res://content/catalog.tres"), "formal content catalog should load")
	assert_true(db.card_ids().size() >= 12, "catalog should expose at least 12 cards")
	assert_equal(db.status_ids().size(), 3, "catalog should expose 3 seed statuses")
	assert_equal(db.relic_ids().size(), 3, "catalog should expose 3 seed relics")
	assert_equal(db.enemy_ids().size(), 4, "catalog should expose 3 normal enemies + 1 boss")

	var strike := db.get_card(&"card.warrior.strike")
	assert_true(strike != null and strike.is_valid(), "strike CardDef should exist")
	if strike != null:
		assert_equal(strike.get_cost(0), 1, "strike base cost")
		assert_true(strike.get_effects(1).size() > 0, "strike should define an upgraded effect set")
		var target := strike.get_target_rule(0)
		assert_true(target is TargetSpec.UnitTarget, "strike should synthesize UnitTarget from content fields")
		if target is TargetSpec.UnitTarget:
			assert_equal((target as TargetSpec.UnitTarget).team, TargetSpec.UnitTarget.Team.ENEMY, "strike target team")

	var enemy := db.get_enemy(&"enemy.ring_stalker")
	assert_true(enemy != null and enemy.behavior != null, "normal enemy should have behavior")
	if enemy != null:
		assert_true(db.get_unit(enemy.unit_def_id) != null, "enemy UnitDef should resolve by stable ID")
	return failures()
