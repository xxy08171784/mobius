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
	_test_player_start_override(content)
	_test_enemies_spawn_interior(content)
	_test_obstacles(content)
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


func _test_player_start_override(content: Object) -> void:
	var run := _run(content)
	var encounter: EncounterDef = content.call("get_encounter", &"encounter.monster.ring_stalker")
	var cell := Vector2i(7, 0)
	var data := EncounterBuilder.build(encounter, run, _rng(), content, cell)
	if data.is_empty():
		assert_true(false, "override 下 build 应成功")
		return
	var state: BattleState = data["state"]
	assert_equal(state.board.get_unit_cell(1), cell, "玩家落在传入进场格")
	assert_true(state.board.is_occupied(cell), "进场格被玩家占用")
	# 非法格回退 encounter.player_start。
	var bad := EncounterBuilder.build(encounter, run, _rng(), content, Vector2i(-5, -5))
	var bad_state: BattleState = bad["state"]
	assert_equal(bad_state.board.get_unit_cell(1), encounter.player_start, "非法进场格回退默认起点")


func _test_enemies_spawn_interior(content: Object) -> void:
	var encounter: EncounterDef = content.call("get_encounter", &"encounter.elite.twin_guard")
	var data := EncounterBuilder.build(encounter, _run(content), _rng("spawn"), content)
	if data.is_empty():
		assert_true(false, "精英 build 应成功")
		return
	var state: BattleState = data["state"]
	var enemy_ids: Array = state.alive_enemy_ids()
	assert_equal(enemy_ids.size(), 2, "精英 2 敌人")
	assert_not_equal(
		state.board.get_unit_cell(2),
		state.board.get_unit_cell(3),
		"敌人互不重叠"
	)
	for enemy_id: int in enemy_ids:
		var cell := state.board.get_unit_cell(enemy_id)
		assert_true(
			cell.x > 0 and cell.y > 0 and cell.x < encounter.board_cols - 1 and cell.y < encounter.board_rows - 1,
			"敌人在内部格（非边缘）"
		)


func _test_obstacles(content: Object) -> void:
	var pool: MonsterPoolDef = content.call("get_monster_pool", &"monster_pool.act1")
	assert_true(pool != null, "act1 怪物池存在")
	if pool == null:
		return
	assert_true(pool.obstacle_count > 0 and not pool.obstacle_pool_id.is_empty(), "act1 池配置了障碍池与数量")
	var encounter := MonsterPool.build_encounter(pool, 3, _rng("obs-draw").get_stream(&"encounter"))
	assert_true(encounter != null and encounter.obstacle_count > 0, "抽出的遭遇携带障碍配置")
	if encounter == null:
		return
	var data := EncounterBuilder.build(encounter, _run(content), _rng("obs-build"), content)
	if data.is_empty():
		assert_true(false, "带障碍的 build 应成功")
		return
	var state: BattleState = data["state"]
	var obstacles := _obstacle_map(state.board)
	assert_equal(obstacles.size(), encounter.obstacle_count, "障碍数量符合配置")
	for cell: Vector2i in obstacles:
		assert_true(_is_interior(cell, state.board), "障碍在内部格")
		assert_true(not state.board.is_occupied(cell), "障碍不在单位格")
		assert_true(not state.board.is_traversable(cell), "障碍格不可走")
	assert_true(_open_connected(state.board), "摆障碍后开放格仍连通")
	# 同 seed 确定性。
	var b := EncounterBuilder.build(encounter, _run(content), _rng("obs-build"), content)
	assert_equal(_obstacle_map((b["state"] as BattleState).board), obstacles, "同 seed 障碍布局确定")


func _obstacle_map(board: BoardState) -> Dictionary:
	var out: Dictionary = {}
	for y in range(board.rows):
		for x in range(board.cols):
			var cell := Vector2i(x, y)
			var cs := board.get_cell(cell)
			if cs != null and not cs.terrain_key.is_empty():
				out[cell] = cs.terrain_key
	return out


func _is_interior(cell: Vector2i, board: BoardState) -> bool:
	return cell.x > 0 and cell.y > 0 and cell.x < board.cols - 1 and cell.y < board.rows - 1


func _open_connected(board: BoardState) -> bool:
	var start := Vector2i(-1, -1)
	for y in range(board.rows):
		for x in range(board.cols):
			var c := Vector2i(x, y)
			if board.is_traversable(c) and not board.is_occupied(c):
				start = c
				break
		if start != Vector2i(-1, -1):
			break
	if start == Vector2i(-1, -1):
		return true
	var visited: Dictionary = {start: true}
	var stack: Array[Vector2i] = [start]
	while not stack.is_empty():
		var cur: Vector2i = stack.pop_back()
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nxt := cur + d
			if not board.is_inside(nxt) or visited.has(nxt):
				continue
			if not board.is_traversable(nxt) or board.is_occupied(nxt):
				continue
			visited[nxt] = true
			stack.append(nxt)
	for y in range(board.rows):
		for x in range(board.cols):
			var c := Vector2i(x, y)
			if board.is_traversable(c) and not board.is_occupied(c) and not visited.has(c):
				return false
	return true


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
