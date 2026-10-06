extends "res://tests/test_case.gd"

const CONTENT_DB_SCRIPT := preload("res://autoload/content_db.gd")


func run() -> Array[String]:
	reset()
	# 单测试通过 -s 启动时不注入 autoload 全局名，所以直接实例化同一实现脚本。
	var db := CONTENT_DB_SCRIPT.new()
	assert_true(db.load_catalog("res://content/catalog.tres"), "formal content catalog should load")
	assert_equal(db.card_ids().size(), 67, "catalog should expose 12 legacy + 5 starter + 49 formal + 1 fist token")
	assert_equal(db.reward_card_ids().size(), 49, "formal reward pool should contain only the 49 reward cards")
	for number in range(1, 50):
		var implemented := db.get_card(StringName("card.reward.%02d" % number))
		assert_true(implemented != null and implemented.reward_pool_enabled, "implemented formal card %02d should enter reward pool" % number)
	var reward_49 := db.get_card(&"card.reward.49")
	assert_true(reward_49 != null, "formal card #49 should be registered")
	if reward_49 != null:
		assert_equal(reward_49.card_number, 49, "formal card number should be stable")
		assert_equal(reward_49.get_visual_key(), &"card_49", "formal card visual key should be stable")
		assert_true(reward_49.reward_pool_enabled, "formal card #49 should be enabled in rewards")
	assert_equal(db.status_ids().size(), 7, "catalog should expose 3 seed + poison + 3 formal-card statuses")

	assert_equal(db.relic_ids().size(), 3, "catalog should expose 3 seed relics")
	assert_equal(db.enemy_ids().size(), 12, "catalog should expose 4 tomb mobs + 3 elites + 1 boss + 4 mobius enemies")
	assert_equal(db.monster_pool_ids().size(), 2, "catalog should expose act-1 mob + elite pools")
	assert_true(db.get_monster_pool(&"monster_pool.act1") != null, "act-1 pool should resolve")
	assert_true(db.get_monster_pool(&"monster_pool.act1_elite") != null, "act-1 elite pool should resolve")
	assert_true(db.get_encounter(&"encounter.boss.act1") != null, "tomb boss encounter should resolve")
	var tomb_enemy := db.get_enemy(&"enemy.tomb.bat")
	assert_true(tomb_enemy != null and tomb_enemy.behavior != null, "tomb enemy should have behavior")
	assert_equal(tomb_enemy.display_name, "蝙蝠", "tomb enemy display_name")

	var strike := db.get_card(&"card.warrior.strike")
	assert_true(strike != null and strike.is_valid(), "strike CardDef should exist")
	if strike != null:
		assert_true(not strike.reward_pool_enabled, "legacy warrior cards should no longer enter formal rewards")
		assert_equal(strike.get_cost(0), 1, "strike base cost")
		assert_true(strike.get_effects(1).size() > 0, "strike should define an upgraded effect set")
		var target := strike.get_target_rule(0)
		assert_true(target is TargetSpec.UnitTarget, "strike should synthesize UnitTarget from content fields")
		if target is TargetSpec.UnitTarget:
			assert_equal((target as TargetSpec.UnitTarget).team, TargetSpec.UnitTarget.Team.ENEMY, "strike target team")

	for starter_id: StringName in [
		&"card.starter.punch",
		&"card.starter.attack",
		&"card.starter.charge",
		&"card.starter.relentless",
		&"card.starter.defend",
	]:
		var starter := db.get_card(starter_id)
		assert_true(starter != null and starter.is_valid(), "starter card should be registered: %s" % starter_id)
		if starter != null:
			assert_true(not starter.reward_pool_enabled, "starter cards should not enter reward pool")

	var enemy := db.get_enemy(&"enemy.ring_stalker")
	assert_true(enemy != null and enemy.behavior != null, "normal enemy should have behavior")
	if enemy != null:
		assert_true(db.get_unit(enemy.unit_def_id) != null, "enemy UnitDef should resolve by stable ID")
	return failures()
