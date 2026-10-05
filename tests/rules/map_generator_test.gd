class_name MapGeneratorTest
extends RefCounted
## 选关地图生成的无头测试。run_all() 返回失败信息列表（空 = 全过）。
## 待 Phase 0 的 tests/run_all.gd 落地后由其发现并调用本类。

const SEEDS := [1, 42, 12345, 67890, 987654321]
const DIST_SEEDS := 200


func run_all() -> Array[String]:
	var fails: Array[String] = []
	_test_determinism(fails)
	_test_fixed_floors(fails)
	_test_boss(fails)
	_test_no_crossing(fails)
	_test_dag_and_connectivity(fails)
	_test_special_adjacency(fails)
	_test_min_floors(fails)
	_test_distribution(fails)
	_test_unlock(fails)
	return fails


static func _default_def() -> RouteMapDef:
	return RouteMapDef.new()


static func _gen(def: RouteMapDef, seed_value: int) -> RouteGraph:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return MapGenerator.generate(def, rng)


## 与遍历顺序无关的图签名（节点+类型+出边），用于确定性比对。
static func _signature(g: RouteGraph) -> String:
	var parts: Array[String] = []
	for id in g.nodes:
		var n: MapNodeState = g.nodes[id]
		var nxt: Array[int] = n.next_ids.duplicate()
		nxt.sort()
		parts.append("%d@%d,%d:%s->%s" % [n.id, n.row, n.col, n.type_key, str(nxt)])
	parts.sort()
	return "\n".join(parts)


func _test_determinism(fails: Array[String]) -> void:
	var def := _default_def()
	for s in SEEDS:
		var a := _signature(_gen(def, s))
		var b := _signature(_gen(def, s))
		if a != b:
			fails.append("确定性失败 seed=%d" % s)
	# 不同种子应产生不同图（防实现退化为常量图）。
	var g1 := _signature(_gen(def, SEEDS[0]))
	var g2 := _signature(_gen(def, SEEDS[1]))
	if g1 == g2:
		fails.append("不同 seed 生成相同图（随机未生效）")


func _test_fixed_floors(fails: Array[String]) -> void:
	var def := _default_def()
	for s in SEEDS:
		var g := _gen(def, s)
		_expect_row_type(g, 0, RouteMapDef.TYPE_MONSTER, s, fails)
		_expect_row_type(g, 8, RouteMapDef.TYPE_TREASURE, s, fails)
		_expect_row_type(g, def.rows - 1, RouteMapDef.TYPE_REST, s, fails)


static func _expect_row_type(g: RouteGraph, row_: int, expected: StringName, s: int, fails: Array[String]) -> void:
	var ns := g.get_nodes_at_row(row_)
	if ns.is_empty():
		fails.append("第 %d 行为空 seed=%d" % [row_, s])
		return
	for n in ns:
		if n.type_key != expected:
			fails.append("第 %d 行应为 %s，实为 %s (id=%d) seed=%d" % [row_, expected, n.type_key, n.id, s])


func _test_boss(fails: Array[String]) -> void:
	var def := _default_def()
	for s in SEEDS:
		var g := _gen(def, s)
		var top := g.get_nodes_at_row(def.rows)
		if top.size() != 1:
			fails.append("boss 数应为 1，实为 %d seed=%d" % [top.size(), s])
			continue
		if top[0].type_key != RouteMapDef.TYPE_BOSS:
			fails.append("顶层节点非 boss: %s seed=%d" % [top[0].type_key, s])
		if g.boss_id != top[0].id:
			fails.append("boss_id 与顶层节点不一致 seed=%d" % s)
		for n in g.get_nodes_at_row(def.rows - 1):
			if not n.next_ids.has(top[0].id):
				fails.append("顶层节点未连 boss: id=%d seed=%d" % [n.id, s])


func _test_no_crossing(fails: Array[String]) -> void:
	for s in SEEDS:
		var g := _gen(_default_def(), s)
		# 按起始行收集边 (col_from, col_to)。
		var edges := {}
		for id in g.nodes:
			var n: MapNodeState = g.nodes[id]
			for nid in n.next_ids:
				var c := g.get_node(nid)
				if c.row != n.row + 1:
					continue
				if not edges.has(n.row):
					edges[n.row] = []
				edges[n.row].append(Vector2i(n.col, c.col))
		for row in edges:
			var arr: Array = edges[row]
			for i in arr.size():
				for j in range(i + 1, arr.size()):
					var a: Vector2i = arr[i]
					var b: Vector2i = arr[j]
					if (a.x < b.x and a.y > b.y) or (a.x > b.x and a.y < b.y):
						fails.append("交叉边 行%d: %s vs %s seed=%d" % [row, a, b, s])


func _test_dag_and_connectivity(fails: Array[String]) -> void:
	for s in SEEDS:
		var g := _gen(_default_def(), s)
		for id in g.nodes:
			var n: MapNodeState = g.nodes[id]
			for nid in n.next_ids:
				if g.get_node(nid).row <= n.row:
					fails.append("边未严格上行/成环: %d(row%d)->%d seed=%d" % [id, n.row, nid, s])
		for e in g.get_entry_nodes():
			if not g.has_path(e.id, g.boss_id):
				fails.append("入口无路到 boss: id=%d col=%d seed=%d" % [e.id, e.col, s])


func _test_special_adjacency(fails: Array[String]) -> void:
	var def := _default_def()
	for s in SEEDS:
		var g := _gen(def, s)
		for id in g.nodes:
			var n: MapNodeState = g.nodes[id]
			for nid in n.next_ids:
				var c := g.get_node(nid)
				if n.type_key in def.special_types and c.type_key in def.special_types:
					fails.append("相邻特殊: %s(行%d) -> %s(行%d) seed=%d" % [n.type_key, n.row, c.type_key, c.row, s])


func _test_min_floors(fails: Array[String]) -> void:
	var def := _default_def()
	for s in SEEDS:
		var g := _gen(def, s)
		for id in g.nodes:
			var n: MapNodeState = g.nodes[id]
			if def.min_floors.has(n.type_key):
				var lo: int = def.min_floors[n.type_key]
				if n.row < lo:
					fails.append("行%d 出现 %s（下限%d）seed=%d" % [n.row, n.type_key, lo, s])


func _test_distribution(fails: Array[String]) -> void:
	var def := _default_def()
	var counts := {}
	var total := 0
	for s in range(DIST_SEEDS):
		var g := _gen(def, s + 1)
		for id in g.nodes:
			var n: MapNodeState = g.nodes[id]
			if def.fixed_floors.has(n.row) or n.type_key == RouteMapDef.TYPE_BOSS:
				continue
			counts[n.type_key] = int(counts.get(n.type_key, 0)) + 1
			total += 1
	if total < 100:
		fails.append("分布样本过少: %d" % total)
		return
	var monster_frac := float(counts.get(RouteMapDef.TYPE_MONSTER, 0)) / float(total)
	if monster_frac < 0.25 or monster_frac > 0.75:
		fails.append("monster 占比异常: %.2f" % monster_frac)
	for t: StringName in [RouteMapDef.TYPE_EVENT, RouteMapDef.TYPE_ELITE, RouteMapDef.TYPE_REST, RouteMapDef.TYPE_SHOP]:
		if int(counts.get(t, 0)) == 0:
			fails.append("类型从未出现: %s" % t)


func _test_unlock(fails: Array[String]) -> void:
	var g := _gen(_default_def(), SEEDS[0])
	var entries := g.get_entry_nodes()
	if entries.is_empty():
		fails.append("无入口节点")
		return
	for e in entries:
		if not g.can_enter(e.id):
			fails.append("入口不可进: id=%d" % e.id)
	# 初始未访问任何节点时，非入口一律不可进。
	for id in g.nodes:
		var n: MapNodeState = g.nodes[id]
		if not n.is_entry and g.can_enter(id):
			fails.append("初始可进未连通节点: id=%d row=%d" % [id, n.row])
	var e0 := entries[0]
	if not g.enter(e0.id):
		fails.append("进入入口失败")
		return
	if g.can_enter(e0.id):
		fails.append("已访问节点仍可进")
	var any_next := false
	for nid in e0.next_ids:
		if g.can_enter(nid):
			any_next = true
	if not any_next:
		fails.append("进入入口后无后继可进")
