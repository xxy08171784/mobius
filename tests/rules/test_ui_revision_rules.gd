extends "res://tests/test_case.gd"
## 本轮涉及规则的回归：每幕 Boss 回血、防重复结算、退役遗物的旧存档兼容。

func run() -> Array[String]:
	reset()
	var db := load("res://autoload/content_db.gd").new() as Node
	db.load_catalog()
	for act in 3:
		for hp in [25, 79, 80]:
			var run := RunSession.create_run(&"character.hero", "boss-heal-%d" % act, db)
			run.act_index = act
			run.instance_id = "boss-heal-test"
			var graph := RouteGraph.new()
			graph.rows = 1
			graph.cols = 1
			var entry := graph.add_node(0, 0, true)
			entry.type_key = RouteMapDef.TYPE_MONSTER
			var boss := graph.add_boss(1)
			graph.add_edge(entry.id, boss.id)
			graph.mark_visited(entry.id)
			run.map = graph
			run.current_node_id = entry.id
			var session := RunSession.new()
			session.setup(run, db)
			assert_true(session.enter_node(boss.id).get("ok", false), "boss entry")
			var result := BattleResult.new()
			result.run_instance_id = session.state.instance_id
			result.battle_id = session.state.pending_battle_id
			result.victory = true
			result.persistent_changes = {"player_hp": {1: hp}}
			assert_true(session.on_battle_finished(result).get("ok", false), "boss settled")
			var expected := 69 if hp == 25 else 80
			assert_equal(session.state.hp, expected, "80%% missing HP after act %d" % (act + 1))
			var before := SaveCodec.new().encode_state(session.state)
			assert_true(not session.on_battle_finished(result).get("ok", false), "duplicate result rejected")
			assert_equal(SaveCodec.new().encode_state(session.state), before, "duplicate does not heal or reward again")
			if act == 2:
				assert_equal(session.state.flow_phase, &"run_over", "final boss still completes run")
	var run := RunSession.create_run(&"character.hero", "old-compass", db)
	run.add_relic(&"relic.loop_compass")
	run.add_relic(&"relic.echo_shell")
	var session := RunSession.new()
	session.setup(run, db)
	var data: Dictionary = session.enter_node(session.available_node_ids()[0]).battle
	# 模拟更新前战斗检查点中仍有罗盘钩子。
	data.state.relic_hooks.append({"id": &"relic.loop_compass", "hook": &"battle_start", "params": {"move_points": 1}, "count": 0})
	var restored := BattleCheckpoint.restore(BattleCheckpoint.capture(data), db)
	assert_true(not restored.is_empty(), "legacy checkpoint loads")
	assert_equal(restored.state.relic_hooks.size(), 1, "only enabled echo shell hook remains")
	assert_equal(restored.state.relic_hooks[0].id, &"relic.echo_shell", "active relic preserved")
	_test_opening_shuffle(db)
	db.free()
	return failures()


func _test_opening_shuffle(db: Object) -> void:
	var orders: Dictionary = {}
	for seed_text: String in ["101", "202", "303"]:
		var run := RunSession.create_run(&"character.hero", seed_text, db)
		var encounter: EncounterDef = db.get_encounter(&"encounter.boss.act1")
		var a := RngStreams.new()
		var b := RngStreams.new()
		a.derive_streams(seed_text)
		b.derive_streams(seed_text)
		var first := EncounterBuilder.build(encounter, run, a, db)
		var second := EncounterBuilder.build(encounter, run, b, db)
		assert_equal(first.state.deck.draw, second.state.deck.draw, "same seed gives same opening order")
		assert_equal(first.state.rng_snapshot, a.snapshot(), "checkpoint includes RNG after shuffle")
		var expected: Array = range(1000, 1010)
		var sorted: Array = first.state.deck.draw.duplicate()
		sorted.sort()
		assert_equal(sorted, expected, "shuffle preserves all ten cards once")
		orders[str(first.state.deck.draw)] = true
		var battle := BattleSession.new()
		battle.setup(first.rng, first.state, first.card_defs, first.enemy_behaviors, first.enemy_actions)
		first.state = battle.state
		var resumed := BattleCheckpoint.restore(BattleCheckpoint.capture(first), db)
		assert_equal(resumed.state.deck.hand, battle.state.deck.hand, "restore preserves opening hand")
		assert_equal(resumed.state.deck.draw, battle.state.deck.draw, "restore preserves remaining draw order")
		assert_equal(resumed.rng.snapshot(), battle.state.rng_snapshot, "restore does not consume shuffle RNG")
	assert_true(orders.size() > 1, "different seeds can produce different initial orders")
