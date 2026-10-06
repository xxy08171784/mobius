extends "res://tests/test_case.gd"
## RunSession：create_run / enter_node / on_battle_finished 的规则与零副作用测试。

const CONTENT_DB_SCRIPT := preload("res://autoload/content_db.gd")


func run() -> Array[String]:
	reset()
	var content := _content()
	if content == null:
		_failures.append("catalog 加载失败")
		return failures()
	_test_create_run(content)
	_test_enter_battle_node(content)
	_test_enter_locked_zero_side_effects(content)
	_test_reenter_visited_fails(content)
	_test_same_row_sibling_locked(content)
	_test_enter_determinism(content)
	_test_battle_result_writes_hp(content)
	_test_first_battle_uses_monster_pool(content)
	_test_preview_matches_actual_enemies(content)
	_test_boss_advances_act(content)
	_test_treasure_node(content)
	return failures()


func _content() -> Object:
	var db: Object = CONTENT_DB_SCRIPT.new()
	if not bool(db.call("load_catalog", "res://content/catalog.tres")):
		return null
	return db


func _session(content: Object, seed_text: String = "run-seed") -> RunSession:
	var run: RunState = RunSession.create_run(&"character.hero", seed_text, content)
	var session := RunSession.new()
	session.setup(run, content)
	return session


func _test_create_run(content: Object) -> void:
	var run: RunState = RunSession.create_run(&"character.hero", "seed-a", content)
	assert_true(run != null, "create_run 成功")
	if run == null:
		return
	assert_equal(run.hp, run.max_hp, "初始满血")
	assert_equal(run.max_hp, 80, "hero max_hp 来自 UnitDef")
	assert_equal(run.deck.size(), 10, "初始卡组 10 张")
	assert_equal(run.relics.size(), 0, "初始不再携带回环罗盘")
	assert_true(run.map != null and run.map.boss_id != -1, "生成了含 boss 的地图")
	assert_true(not run.rng_snapshot.is_empty(), "RNG 快照已写入")
	# 未知角色返回 null。
	assert_true(RunSession.create_run(&"character.nobody", "s", content) == null, "未知角色返回 null")


func _test_enter_battle_node(content: Object) -> void:
	var session := _session(content)
	var before_battle_id := session.state.next_battle_id
	var entries := session.available_node_ids()
	assert_true(not entries.is_empty(), "初始有可进入口")
	var target := int(entries[0])
	var transition := session.enter_node(target)

	assert_true(bool(transition.get("ok", false)), "进入入口成功")
	assert_equal(String(transition.get("kind", "")), "battle", "入口是战斗节点")
	assert_true(not (transition.get("battle", {}) as Dictionary).is_empty(), "携带战斗装配数据")
	# enter_node 以工作快照提交，session.state 被替换为新实例，必须重新读取。
	var run := session.state
	assert_equal(run.current_node_id, target, "current_node_id 已更新")
	assert_true(run.map.get_node(target).visited, "节点标记 visited")
	assert_equal(run.next_battle_id, before_battle_id + 1, "battle 计数器推进")
	assert_true(not run.map.get_node(target).content_id.is_empty(), "content_id 已解析")


## 第 1 个战斗节点走"怪物池"：固定 2 只，且都来自墓外池（enemy.tomb.*）。
func _test_first_battle_uses_monster_pool(content: Object) -> void:
	var session := _session(content, "pool-seed")
	var entries := session.available_node_ids()
	var transition := session.enter_node(int(entries[0]))
	assert_true(bool(transition.get("ok", false)), "进入第一场战斗成功")
	var state: BattleState = (transition.get("battle", {}) as Dictionary).get("state", null)
	assert_true(state != null, "携带 BattleState")
	if state == null:
		return
	assert_equal(state.enemy_ids().size(), 2, "第 1 个战斗节点固定 2 只（怪物池）")
	for enemy_id: int in state.enemy_ids():
		var unit := state.get_unit(enemy_id)
		assert_true(
			unit.def_id.begins_with("unit.enemy.tomb."),
			"敌人来自墓外怪物池（%s）" % String(unit.def_id)
		)


## 部署预览的敌人落点 = 玩家选外圈格进场后的实际落点（同 seed 一致）。
func _test_preview_matches_actual_enemies(content: Object) -> void:
	var session := _session(content, "preview-seed")
	var node_id := int(session.available_node_ids()[0])
	var preview := session.preview_battle(node_id)
	assert_true(preview.has("enemy_cells"), "预览返回敌人落点")
	var preview_cells := preview["enemy_cells"] as Array
	assert_equal(preview_cells.size(), 2, "第 1 战预览 2 只怪")

	var transition := session.enter_node(node_id, Vector2i(0, 0))
	var state: BattleState = (transition.get("battle", {}) as Dictionary).get("state", null)
	assert_true(state != null, "开战携带状态")
	if state == null:
		return
	var actual: Array[Vector2i] = []
	for enemy_id: int in state.enemy_ids():
		actual.append(state.board.get_unit_cell(enemy_id))
	assert_equal(actual, preview_cells, "开战敌人落点 = 部署预览")


func _test_enter_locked_zero_side_effects(content: Object) -> void:
	var session := _session(content)
	var run := session.state
	# 找一个初始不可进的节点（非入口）。
	var locked := -1
	for id: int in run.map.nodes:
		if not run.map.get_node(id).is_entry:
			locked = id
			break
	assert_true(locked >= 0, "存在非入口节点")
	var snapshot_before := run.duplicate_state()
	var result := session.enter_node(locked)
	assert_true(not bool(result.get("ok", false)), "进入锁定节点失败")
	assert_equal(String(result.get("error_code", "")), "node_locked", "错误码 node_locked")
	# 零副作用：状态等价。
	assert_equal(_sig(run), _sig(snapshot_before), "失败 enter 不改变 RunState")
	assert_equal(run.current_node_id, -1, "current 未变")
	# 不存在的节点。
	assert_true(not bool(session.enter_node(999999).get("ok", false)), "未知节点失败")


func _test_reenter_visited_fails(content: Object) -> void:
	var session := _session(content)
	var target := int(session.available_node_ids()[0])
	assert_true(bool(session.enter_node(target).get("ok", false)), "首次进入成功")
	assert_true(not bool(session.enter_node(target).get("ok", false)), "重复进入被拒")


## 回归：进入一个节点后，同层兄弟节点不可再进（StS 式单路径推进）。
func _test_same_row_sibling_locked(content: Object) -> void:
	var session := _session(content)
	var entries := session.state.map.get_entry_nodes()
	assert_true(entries.size() >= 2, "默认地图应有 >=2 个入口以测试兄弟锁定")
	if entries.size() < 2:
		return
	var a := entries[0].id
	var b := entries[1].id
	assert_true(bool(session.enter_node(a).get("ok", false)), "进入入口 a 成功")
	var result := session.enter_node(b)
	assert_true(not bool(result.get("ok", false)), "同层兄弟 b 不可进入")
	assert_equal(String(result.get("error_code", "")), "node_locked", "错误码 node_locked")
	assert_equal(session.state.current_node_id, a, "current 仍停在第 a 个入口")
	# 只应剩下 a 的直接后继可选，b 不在其中。
	assert_true(not session.available_node_ids().has(b), "b 不在可选集合")


func _test_enter_determinism(content: Object) -> void:
	var a := _session(content, "same-seed")
	var b := _session(content, "same-seed")
	var ta := a.enter_node(int(a.available_node_ids()[0]))
	var tb := b.enter_node(int(b.available_node_ids()[0]))
	assert_equal(String(ta.get("encounter_id", "")), String(tb.get("encounter_id", "")), "同 seed 同入口遭遇一致")
	assert_equal(_sig(a.state), _sig(b.state), "同 seed 同操作 RunState 一致")
	var player_a := (ta["battle"]["state"] as BattleState).board.get_unit_cell(2)
	var player_b := (tb["battle"]["state"] as BattleState).board.get_unit_cell(2)
	assert_equal(player_a, player_b, "战斗初始落点确定")


func _test_battle_result_writes_hp(content: Object) -> void:
	var session := _session(content)
	var target := int(session.available_node_ids()[0])
	session.enter_node(target)
	assert_equal(session.state.hp, 80, "战前满血")
	var result := BattleResult.new()
	result.battle_id = session.state.next_battle_id - 1
	result.victory = true
	result.persistent_changes = {"player_hp": {EncounterBuilder.PLAYER_UNIT_ID: 21}}
	var out := session.on_battle_finished(result)
	assert_equal(String(out.get("kind", "")), "victory", "非 boss 胜利返回 victory")
	assert_equal(session.state.hp, 21, "持久 HP 写回")


func _test_boss_advances_act(content: Object) -> void:
	var session := _session(content)
	# 手搭：入口 monster -> boss，把 current 指到 boss。
	var g := RouteGraph.new()
	g.rows = 1
	g.cols = 1
	var entry := g.add_node(0, 0, true)
	entry.type_key = RouteMapDef.TYPE_MONSTER
	var boss := g.add_boss(1)
	g.add_edge(entry.id, boss.id)
	session.state.map = g
	session.state.current_node_id = entry.id
	g.mark_visited(entry.id)
	session.enter_node(boss.id)

	var result := BattleResult.new()
	result.battle_id = session.state.pending_battle_id
	result.victory = true
	result.persistent_changes = {"player_hp": {EncounterBuilder.PLAYER_UNIT_ID: 25}}
	var out := session.on_battle_finished(result)
	assert_equal(String(out.get("kind", "")), "act_complete", "boss 胜利推进章节")
	assert_equal(session.state.act_index, 1, "act_index 前进")
	assert_equal(session.state.current_node_id, -1, "新章重置当前位置")
	assert_true(session.state.map.boss_id != -1, "新章地图已生成")


func _test_treasure_node(content: Object) -> void:
	var session := _session(content)
	# 手搭：入口 monster(已访问) -> treasure。
	var g := RouteGraph.new()
	g.rows = 1
	g.cols = 1
	var entry := g.add_node(0, 0, true)
	entry.type_key = RouteMapDef.TYPE_MONSTER
	var treasure := g.add_node(1, 0, false)
	treasure.type_key = RouteMapDef.TYPE_TREASURE
	g.add_edge(entry.id, treasure.id)
	session.state.map = g
	session.state.current_node_id = entry.id
	g.mark_visited(entry.id)

	var gold_before := session.state.gold
	var relics_before := session.state.relics.size()
	var transition := session.enter_node(treasure.id)
	assert_true(bool(transition.get("ok", false)), "进入宝箱成功")
	if not bool(transition.get("ok", false)):
		return
	assert_equal(String(transition.get("kind", "")), "treasure", "宝箱转移")
	var run := session.state
	assert_equal(run.relics.size(), relics_before + 1, "获得遗物")
	assert_equal(run.gold, gold_before + TreasureSystem.GOLD_REWARD, "获得金币")
	assert_true(not StringName(String(transition.get("relic_id", ""))).is_empty(), "遗物 ID 非空")


## 与遍历顺序无关的状态签名。
func _sig(run: RunState) -> String:
	var parts: Array[String] = [
		"hp=%d" % run.hp,
		"battle=%d" % run.next_battle_id,
		"current=%d" % run.current_node_id,
		"act=%d" % run.act_index,
		"deck=%d" % run.deck.size(),
	]
	var ids: Array = run.map.nodes.keys()
	ids.sort()
	for id: int in ids:
		var n: MapNodeState = run.map.nodes[id]
		parts.append("%d:%s:v%d" % [id, n.type_key, 1 if n.visited else 0])
	return "|".join(parts)
