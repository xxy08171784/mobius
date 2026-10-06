extends "res://tests/test_case.gd"
## RewardSystem / RunSession 奖励路径测试：生成确定性、领卡、放弃、胜利金币。

const CONTENT_DB_SCRIPT := preload("res://autoload/content_db.gd")


func run() -> Array[String]:
	reset()
	var content := _content()
	if content == null:
		_failures.append("catalog 加载失败")
		return failures()
	_test_generate_determinism(content)
	_test_claim_and_skip(content)
	_test_victory_gold_and_reward_via_session(content)
	return failures()


func _content() -> Object:
	var db: Object = CONTENT_DB_SCRIPT.new()
	if not bool(db.call("load_catalog", "res://content/catalog.tres")):
		return null
	return db


func _test_generate_determinism(content: Object) -> void:
	var pool: Array = content.call("reward_card_ids")
	assert_true(pool.size() >= 12, "卡池至少 12 张")
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 9
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 9
	var a := RewardSystem.generate(pool, rng_a)
	var b := RewardSystem.generate(pool, rng_b)
	assert_equal(a.offers.size(), RewardSystem.OFFER_COUNT, "三选一")
	assert_equal(a.offers, b.offers, "同 seed 商品确定")
	# 无重复。
	var seen := {}
	for card_id: StringName in a.offers:
		seen[card_id] = true
	assert_equal(seen.size(), a.offers.size(), "奖励不重复")


func _test_claim_and_skip(content: Object) -> void:
	var run: RunState = RunSession.create_run(&"character.hero", "reward-claim", content)
	var reward := RewardSystem.generate(content.call("reward_card_ids"), RandomNumberGenerator.new())
	var deck_before := run.deck.size()
	var first: StringName = reward.offers[0]

	var claimed := RewardSystem.claim(run, reward, 0)
	assert_true(bool(claimed.get("ok", false)), "领卡成功")
	assert_equal(run.deck.size(), deck_before + 1, "卡组 +1")
	assert_equal(run.deck[run.deck.size() - 1].card_id, first, "领的是选项卡")
	assert_true(
		not bool(RewardSystem.claim(run, reward, 1).get("ok", false)),
		"已结算后不可再领"
	)

	# 放弃也结算。
	var reward2 := RewardSystem.generate(content.call("reward_card_ids"), RandomNumberGenerator.new())
	var skipped := RewardSystem.claim(run, reward2, -1)
	assert_true(bool(skipped.get("ok", false)), "放弃成功")
	assert_true(not bool(RewardSystem.claim(run, reward2, 0).get("ok", false)), "放弃后不可领")


func _test_victory_gold_and_reward_via_session(content: Object) -> void:
	var run: RunState = RunSession.create_run(&"character.hero", "reward-session", content)
	var session := RunSession.new()
	session.setup(run, content)
	session.enter_node(session.available_node_ids()[0])
	var gold_before := run.gold

	var result := BattleResult.new()
	result.victory = true
	result.battle_id = session.state.pending_battle_id
	result.persistent_changes = {"player_hp": {EncounterBuilder.PLAYER_UNIT_ID: 28}}
	var outcome := session.on_battle_finished(result)
	assert_equal(String(outcome.get("kind", "")), "victory", "胜利转移")
	assert_equal(session.state.gold, gold_before + RewardSystem.GOLD_REWARD, "胜利发金币")

	# 同 seed 的 RunSession 生成相同三选一。
	var run_a: RunState = RunSession.create_run(&"character.hero", "reward-det", content)
	var session_a := RunSession.new()
	session_a.setup(run_a, content)
	var run_b: RunState = RunSession.create_run(&"character.hero", "reward-det", content)
	var session_b := RunSession.new()
	session_b.setup(run_b, content)
	for pending: RunSession in [session_a, session_b]:
		pending.enter_node(pending.available_node_ids()[0])
		var victory := BattleResult.new()
		victory.battle_id = pending.state.pending_battle_id
		victory.victory = true
		pending.on_battle_finished(victory)
	assert_equal(
		session_a.generate_reward().offers,
		session_b.generate_reward().offers,
		"同 seed 同奖励流生成相同三选一"
	)
