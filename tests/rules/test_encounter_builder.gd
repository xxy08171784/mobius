extends "res://tests/test_case.gd"
## EncounterBuilder：RunState + EncounterDef -> 战斗装配 dict 的纯函数测试。

const CONTENT_DB_SCRIPT := preload("res://autoload/content_db.gd")


func run() -> Array[String]:
	reset()
	var content := _content()
	if content == null:
		_failures.append("catalog 加载失败")
		return failures()
	_test_build_basic(content)
	_test_player_hp_carried(content)
	_test_build_does_not_mutate_run(content)
	_test_determinism(content)
	_test_invalid_defs(content)
	return failures()


func _content() -> Object:
	var db: Object = CONTENT_DB_SCRIPT.new()
	if not bool(db.call("load_catalog", "res://content/catalog.tres")):
		return null
	return db


func _rng(seed_value: String = "encounter-test") -> RngStreams:
	var streams := RngStreams.new()
	streams.derive_streams(seed_value)
	return streams


func _run(content: Object, hp: int = 22) -> RunState:
	var run := RunState.new()
	run.run_id = 1
	run.seed = "test-run"
	run.character_id = &"character.hero"
	run.max_hp = 30
	run.hp = hp
	var character: CharacterDef = content.call("get_character", &"character.hero")
	for card_id: StringName in character.starter_deck:
		run.add_card(card_id)
	return run


func _test_build_basic(content: Object) -> void:
	var run := _run(content)
	var encounter: EncounterDef = content.call("get_encounter", &"encounter.monster.ring_stalker")
	var data := EncounterBuilder.build(encounter, run, _rng(), content)
	assert_true(not data.is_empty(), "build 应成功")
	if data.is_empty():
		return
	var state: BattleState = data["state"]
	assert_true(state.phase == BattleState.Phase.SETUP, "初始 phase 为 SETUP")
	assert_equal(state.units.size(), 2, "1 玩家 + 1 敌人")
	assert_equal(run.deck.size(), 10, "初始卡组 10 张")
	assert_equal(state.deck.cards.size(), 10, "战斗牌堆 10 张")
	assert_true(not Dictionary(data["enemy_behaviors"]).is_empty(), "敌人行为已装配")
	assert_true(not Dictionary(data["enemy_actions"]).is_empty(), "敌人行动表已装配")
	assert_true(not Dictionary(data["card_labels"]).is_empty(), "卡牌展示文本非空")
	# 玩家在 player_start，敌人在盘内。
	assert_true(state.board.get_unit_cell(1) != BoardState.INVALID_CELL, "玩家已落子")
	assert_true(state.board.get_unit_cell(2) != BoardState.INVALID_CELL, "敌人已落子")
	# source_run_uid 回指永久卡。
	var first_battle_card: BattleCardState = state.deck.get_card(EncounterBuilder.BATTLE_CARD_UID_BASE)
	assert_true(first_battle_card != null, "首张战斗卡存在")
	if first_battle_card != null:
		assert_equal(first_battle_card.source_run_uid, run.deck[0].run_uid, "战斗卡回指永久卡")


func _test_player_hp_carried(content: Object) -> void:
	var run := _run(content, 17)
	var encounter: EncounterDef = content.call("get_encounter", &"encounter.monster.echo_guard")
	var data := EncounterBuilder.build(encounter, run, _rng(), content)
	var state: BattleState = data["state"]
	assert_equal(state.get_unit(1).hp, 17, "持久 HP 带入战斗")
	assert_equal(state.get_unit(1).max_hp, 30, "max_hp 来自 RunState")


func _test_build_does_not_mutate_run(content: Object) -> void:
	var run := _run(content)
	var before_deck := run.deck.size()
	var before_battle := run.next_battle_id
	var encounter: EncounterDef = content.call("get_encounter", &"encounter.monster.loop_hound")
	var data := EncounterBuilder.build(encounter, run, _rng(), content)
	assert_equal(run.deck.size(), before_deck, "build 不改 RunState 卡组")
	assert_equal(run.next_battle_id, before_battle, "build 不推进 battle 计数器")
	assert_equal((data["state"] as BattleState).battle_id, before_battle, "battle_id 读自 next_battle_id")


func _test_determinism(content: Object) -> void:
	var encounter: EncounterDef = content.call("get_encounter", &"encounter.elite.twin_guard")
	var a := EncounterBuilder.build(encounter, _run(content), _rng("same"), content)
	var b := EncounterBuilder.build(encounter, _run(content), _rng("same"), content)
	var sa: BattleState = a["state"]
	var sb: BattleState = b["state"]
	assert_equal(sa.units.size(), 3, "精英遭遇 1 玩家 + 2 敌人")
	assert_equal(
		sa.board.get_unit_cell(2),
		sb.board.get_unit_cell(2),
		"同输入敌人 2 落点确定"
	)
	assert_equal(
		sa.board.get_unit_cell(3),
		sb.board.get_unit_cell(3),
		"同输入敌人 3 落点确定"
	)


func _test_invalid_defs(content: Object) -> void:
	var run := _run(content)
	# 无敌人列表的非法遭遇。
	var bad := EncounterDef.new()
	bad.id = &"encounter.bad"
	assert_true(EncounterBuilder.build(bad, run, _rng(), content).is_empty(), "非法遭遇返回空")
	# 敌人 ID 不存在。
	var missing := EncounterDef.new()
	missing.id = &"encounter.missing"
	missing.enemy_ids = [&"enemy.does_not_exist"]
	assert_true(EncounterBuilder.build(missing, run, _rng(), content).is_empty(), "缺内容返回空")
