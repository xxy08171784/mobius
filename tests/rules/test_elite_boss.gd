extends "res://tests/test_case.gd"
## 精英/Boss 组装测试：精英战 = 1 精英 + 2 小怪；Boss 节点 = 墓外石像（带召唤池）。

const CONTENT_DB_SCRIPT := preload("res://autoload/content_db.gd")

const ELITE_DEFS: Array[StringName] = [
	&"unit.enemy.tomb.viper",
	&"unit.enemy.tomb.skeleton",
	&"unit.enemy.tomb.crossbow",
]


func run() -> Array[String]:
	reset()
	_test_elite_composition()
	var content := _content()
	if content == null:
		_failures.append("catalog 加载失败")
		return failures()
	_test_elite_node(content)
	_test_boss_node(content)
	return failures()


func _content() -> Object:
	var db: Object = CONTENT_DB_SCRIPT.new()
	if not bool(db.call("load_catalog", "res://content/catalog.tres")):
		return null
	return db


func _session(content: Object, seed_text: String) -> RunSession:
	var run: RunState = RunSession.create_run(&"character.hero", seed_text, content)
	var session := RunSession.new()
	session.setup(run, content)
	return session


func _pool(id: StringName, tier: StringName, ids: Array[StringName]) -> MonsterPoolDef:
	var p := MonsterPoolDef.new()
	p.id = id
	p.tier = tier
	p.enemy_ids = ids
	return p


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _test_elite_composition() -> void:
	var elite := _pool(&"monster_pool.test_elite", &"elite", [&"enemy.e1", &"enemy.e2", &"enemy.e3"])
	var mobs := _pool(&"monster_pool.test_mob", &"monster", [&"enemy.m1", &"enemy.m2", &"enemy.m3", &"enemy.m4"])
	var comp := MonsterPool.draw_elite_composition(elite, mobs, _rng(7))
	assert_equal(comp.size(), 3, "精英战 = 1 精英 + 2 小怪")
	assert_true(elite.enemy_ids.has(comp[0]), "首个是精英")
	assert_true(mobs.enemy_ids.has(comp[1]) and mobs.enemy_ids.has(comp[2]), "后两个来自小怪池")
	assert_equal(comp, MonsterPool.draw_elite_composition(elite, mobs, _rng(7)), "同种子同组成")

	var encounter := MonsterPool.build_elite_encounter(elite, mobs, 3, _rng(7))
	assert_true(encounter != null and encounter.is_valid(), "合成精英遭遇合法")
	assert_equal(encounter.enemy_ids.size(), 3, "精英遭遇 3 个敌人")
	assert_equal(encounter.tier, &"elite", "层级 elite")


## 手搭：入口(已访问, current) -> 目标节点（仿 test_run_session 的宝箱/boss 手搭模式）。
func _map_to(target_type: StringName) -> Array:
	var g := RouteGraph.new()
	g.rows = 1
	g.cols = 2
	var entry := g.add_node(0, 0, true)
	entry.type_key = RouteMapDef.TYPE_MONSTER
	var target := g.add_node(1, 0, false)
	target.type_key = target_type
	g.add_edge(entry.id, target.id)
	g.mark_visited(entry.id)
	return [g, entry.id, target.id]


func _enter(session: RunSession, target_type: StringName) -> Dictionary:
	var built := _map_to(target_type)
	session.state.map = built[0]
	session.state.current_node_id = int(built[1])
	return session.enter_node(int(built[2]))


func _test_elite_node(content: Object) -> void:
	var session := _session(content, "elite-node")
	var transition := _enter(session, RouteMapDef.TYPE_ELITE)
	assert_true(bool(transition.get("ok", false)), "进入精英节点成功")
	var state: BattleState = (transition.get("battle", {}) as Dictionary).get("state", null)
	assert_true(state != null, "携带 BattleState")
	if state == null:
		return
	assert_equal(state.enemy_ids().size(), 3, "精英战 = 1 精英 + 2 小怪")
	var elite_count := 0
	var mob_count := 0
	for enemy_id: int in state.enemy_ids():
		var def_id: StringName = state.get_unit(enemy_id).def_id
		if ELITE_DEFS.has(def_id):
			elite_count += 1
		elif String(def_id).begins_with("unit.enemy.tomb."):
			mob_count += 1
	assert_equal(elite_count, 1, "恰一只墓外精英")
	assert_equal(mob_count, 2, "恰两只墓外小怪")


func _test_boss_node(content: Object) -> void:
	var session := _session(content, "boss-node")
	var transition := _enter(session, RouteMapDef.TYPE_BOSS)
	assert_true(bool(transition.get("ok", false)), "进入 Boss 节点成功")
	var battle: Dictionary = transition.get("battle", {})
	var state: BattleState = battle.get("state", null)
	assert_true(state != null, "携带 BattleState")
	if state == null:
		return
	assert_equal(state.enemy_ids().size(), 1, "Boss 单独上场（小怪靠召唤刷新）")
	assert_equal(state.get_unit(int(state.enemy_ids()[0])).def_id, &"unit.enemy.tomb.tomb_statue", "Boss = 陵墓石像")
	assert_equal((battle.get("summon_pool", []) as Array).size(), 4, "召唤池含 4 只墓外小怪")
