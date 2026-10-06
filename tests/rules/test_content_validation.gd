extends "res://tests/test_case.gd"


func run() -> Array[String]:
	reset()
	var db := load("res://autoload/content_db.gd").new() as Node
	db.load_catalog()
	assert_equal(ContentValidator.validate(db, load(RunSession.CAMPAIGN_PATH)).size(), 0, "all content cross references valid")
	var shop: ShopDef = db.get_shop(&"shop.route")
	assert_equal(shop.pool.resolve(db), db.reward_card_ids(), "shop and rewards share formal pool")
	var enemy: EnemyDef = db.get_enemy(db.enemy_ids()[0])
	var saved := enemy.unit_def_id
	enemy.unit_def_id = &"unit.missing.test"
	assert_true(not ContentValidator.validate(db).is_empty(), "broken unit reference detected")
	enemy.unit_def_id = saved
	var state := RunSession.create_run(&"character.hero", "relic-test", db)
	state.add_relic(&"relic.loop_compass") # 模拟旧存档持有已停用遗物。
	state.add_relic(&"relic.echo_shell")
	state.add_relic(&"relic.mobius_coin")
	var session := RunSession.new()
	session.setup(state, db)
	var data: Dictionary = session.enter_node(session.available_node_ids()[0]).battle
	var battle := BattleSession.new()
	battle.setup(data.rng, data.state, data.card_defs, data.enemy_behaviors, data.enemy_actions)
	assert_equal(battle.state.get_unit(1).block, 4, "echo shell grants opening block")
	assert_equal(battle.state.get_unit(1).get_resource(&"move_points"), battle.state.move_points_per_round, "retired compass does not grant movement")
	var snapshot := SaveCodec.new().clone_state(battle.state) as BattleState
	var resumed := BattleSession.new()
	resumed.setup(data.rng, snapshot, data.card_defs, data.enemy_behaviors, data.enemy_actions)
	assert_equal(resumed.state.get_unit(1).block, 4, "resume does not duplicate opening relic")
	assert_equal(resumed.state.relic_hooks, battle.state.relic_hooks, "relic counters persisted")
	var gold := session.state.gold
	var victory := BattleResult.new()
	victory.battle_id = session.state.pending_battle_id
	victory.victory = true
	session.on_battle_finished(victory)
	assert_equal(session.state.gold, gold + RewardSystem.GOLD_REWARD + 1, "coin grants victory gold")
	db.free()
	return failures()
