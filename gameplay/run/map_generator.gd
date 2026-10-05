class_name MapGenerator
extends RefCounted
## 选关地图生成器。纯函数：generate(def, rng) -> RouteGraph，不改入参、不用全局随机。
## 确定性 = (def, rng 状态)：同输入必同输出，用于无头测试与存档回放。
## RNG 作为入参注入（未来由 RngStreams.route_rng() 提供；测试传普通 RandomNumberGenerator）。
## 算法合同见 docs/route_map_rules.md。


## 生成一张 StS 式 DAG 地图。
static func generate(def: RouteMapDef, rng: RandomNumberGenerator) -> RouteGraph:
	_validate(def)
	var graph := RouteGraph.new()
	graph.rows = def.rows
	graph.cols = def.cols

	# 1. 入口列：洗牌取前 path_count（保证入口互不相同、覆盖全宽）。
	for start_col in _shuffled_start_cols(def, rng):
		_walk_path(graph, def, rng, start_col)

	# 2. boss 单节点，连接顶层全部节点。
	_build_boss(graph, def)

	# 3. 类型分配（自上而下，固定行 + 加权抽签 + 相邻约束）。
	_assign_types(graph, def, rng)
	return graph


## 入口列 = [0..cols-1] 洗牌后取前 path_count。Fisher-Yates，确定性由 rng 决定。
static func _shuffled_start_cols(def: RouteMapDef, rng: RandomNumberGenerator) -> Array[int]:
	var cols: Array[int] = []
	for c in def.cols:
		cols.append(c)
	for i in range(cols.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := cols[i]
		cols[i] = cols[j]
		cols[j] = tmp
	var out: Array[int] = []
	for i in mini(def.path_count, cols.size()):
		out.append(cols[i])
	return out


## 一条路径从入口上行到顶层。每步列号 ±1（clamp 到盘内）。
## 目标步与既有边交叉则退回正上方（竖直边证明永不与同层其他边交叉），故路径不会中断。
static func _walk_path(graph: RouteGraph, def: RouteMapDef, rng: RandomNumberGenerator, start_col: int) -> void:
	var col := start_col
	var prev := graph.add_node(0, col, true)
	for row in range(1, def.rows):
		var next_col := clampi(col + rng.randi_range(-1, 1), 0, def.cols - 1)
		if _edge_crosses(graph, row - 1, col, next_col) and next_col != col:
			next_col = col  # 竖直边不与任何边交叉，必然可走
		var target := graph.add_node(row, next_col, false)
		graph.add_edge(prev.id, target.id)
		prev = target
		col = next_col


## 新边 (row -> row+1, 列 a->b) 是否与已存在的同层边 (c->d) 交叉（水平顺序翻转）。
## 共享端点不算交叉。竖直边 (a==b) 恒不交叉（对任意 c,d 均不可能同时 a<c 且 a>d）。
static func _edge_crosses(graph: RouteGraph, from_row: int, a: int, b: int) -> bool:
	for n: MapNodeState in graph.nodes.values():
		if n.row != from_row:
			continue
		for to_id in n.next_ids:
			var to_node := graph.get_node(to_id)
			if to_node.row != from_row + 1:
				continue
			var c: int = n.col
			var d: int = to_node.col
			if a == c:
				continue
			if (a < c and b > d) or (a > c and b < d):
				return true
	return false


static func _build_boss(graph: RouteGraph, def: RouteMapDef) -> void:
	var boss := graph.add_boss(def.rows)
	for n in graph.get_nodes_at_row(def.rows - 1):
		graph.add_edge(n.id, boss.id)


## 类型分配：自上而下（boss -> rows-1 .. 0）。固定行强制；其余按权重抽签，受下限与相邻约束。
static func _assign_types(graph: RouteGraph, def: RouteMapDef, rng: RandomNumberGenerator) -> void:
	if graph.boss_id != -1:
		graph.get_node(graph.boss_id).type_key = RouteMapDef.TYPE_BOSS
	for row in range(def.rows - 1, -1, -1):
		for n: MapNodeState in graph.get_nodes_at_row(row):
			n.type_key = _pick_type(graph, def, rng, n)


static func _pick_type(graph: RouteGraph, def: RouteMapDef, rng: RandomNumberGenerator, node: MapNodeState) -> StringName:
	if def.fixed_floors.has(node.row):
		return def.fixed_floors[node.row]

	# 相邻约束：任一子节点（高一行直连）为特殊类型 -> 本节点不得为特殊。
	var child_special := false
	for nid in node.next_ids:
		var child := graph.get_node(nid)
		if child != null and child.type_key in def.special_types:
			child_special = true
			break

	return _weighted_pick(def, rng, node.row, child_special)


## 加权抽签：过滤掉权重<=0、低于楼层下限、以及（相邻约束下）特殊类型。
## 按插入序遍历 def.weights（Godot Dictionary 保序），确定性。
static func _weighted_pick(def: RouteMapDef, rng: RandomNumberGenerator, row: int, exclude_special: bool) -> StringName:
	var total := 0.0
	var pool: Array[StringName] = []
	var cum: Array[float] = []
	for key: StringName in def.weights:
		var w: float = def.weights[key]
		if w <= 0.0:
			continue
		if def.min_floors.has(key) and row < int(def.min_floors[key]):
			continue
		if exclude_special and key in def.special_types:
			continue
		total += w
		pool.append(key)
		cum.append(total)
	if pool.is_empty():
		return _fallback(def, row)
	var r := rng.randf() * total
	for i in pool.size():
		if r < cum[i]:
			return pool[i]
	return pool[pool.size() - 1]


## 兜底：取 fallback_chain 中第一个满足楼层下限的类型。
static func _fallback(def: RouteMapDef, row: int) -> StringName:
	for key: StringName in def.fallback_chain:
		if def.min_floors.has(key) and row < int(def.min_floors[key]):
			continue
		return key
	return RouteMapDef.TYPE_MONSTER


static func _validate(def: RouteMapDef) -> void:
	assert(def.rows >= 2, "RouteMapDef.rows 必须 >= 2")
	assert(def.cols >= 1, "RouteMapDef.cols 必须 >= 1")
	assert(def.path_count >= 1, "RouteMapDef.path_count 必须 >= 1")
	assert(def.path_count <= def.cols, "RouteMapDef.path_count 不能超过 cols")
	for r in def.fixed_floors:
		assert(int(r) >= 0 and int(r) < def.rows, "fixed_floors 行号越界: %d" % int(r))
