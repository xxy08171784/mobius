class_name RouteGraph
extends RefCounted
## 选关地图的有向无环图（StS 式：路径可汇合，边只向高行）。
## 持有节点数据与纯查询（解锁/可达）。生成与类型分配在 MapGenerator，本类只做查询与渐进状态。
## 未来接线点：RunState.map = 本图，RunState.current_node_id 指向当前节点。

## 正常楼层数（不含 boss 隐式行）。
var rows: int = 0
var cols: int = 0

## 节点 ID -> MapNodeState。
var nodes: Dictionary[int, MapNodeState] = {}

## 格 (col,row) -> 节点 ID。
var node_by_cell: Dictionary[Vector2i, int] = {}

## 第 0 行入口节点 ID（升序按 col 排）。
var entry_ids: Array[int] = []

## boss 节点 ID（-1 表示未生成）。
var boss_id: int = -1

var _next_id: int = 0


## 建节点；若该格已有节点则复用（DAG 汇合点）。row_ 为 0 时记入口。
func add_node(row_: int, col_: int, is_entry_: bool) -> MapNodeState:
	var cell := Vector2i(col_, row_)
	if node_by_cell.has(cell):
		return nodes[node_by_cell[cell]]
	var n := MapNodeState.new()
	n.id = _next_id
	_next_id += 1
	n.row = row_
	n.col = col_
	n.is_entry = is_entry_
	nodes[n.id] = n
	node_by_cell[cell] = n.id
	if is_entry_:
		entry_ids.append(n.id)
	return n


## 建 boss 节点（固定隐式行 row_，col 恒为 0）。
func add_boss(row_: int) -> MapNodeState:
	var n := MapNodeState.new()
	n.id = _next_id
	_next_id += 1
	n.row = row_
	n.col = 0
	n.type_key = RouteMapDef.TYPE_BOSS
	nodes[n.id] = n
	boss_id = n.id
	return n


## 加边 from_id -> to_id（去重，双向登记）。
func add_edge(from_id: int, to_id: int) -> void:
	var f := nodes[from_id]
	var t := nodes[to_id]
	f.add_next(to_id)
	t.add_prev(from_id)


func get_node(id: int) -> MapNodeState:
	return nodes.get(id)


func node_at(cell: Vector2i) -> MapNodeState:
	var id: int = node_by_cell.get(cell, -1)
	if id == -1:
		return null
	return nodes[id]


## 指定行的全部节点，按 col 升序。
func get_nodes_at_row(row_: int) -> Array[MapNodeState]:
	var out: Array[MapNodeState] = []
	for n: MapNodeState in nodes.values():
		if n.row == row_:
			out.append(n)
	out.sort_custom(func(a: MapNodeState, b: MapNodeState) -> bool:
		return a.col < b.col)
	return out


func get_entry_nodes() -> Array[MapNodeState]:
	var out: Array[MapNodeState] = []
	for id in entry_ids:
		out.append(nodes[id])
	out.sort_custom(func(a: MapNodeState, b: MapNodeState) -> bool:
		return a.col < b.col)
	return out


func get_next_ids(id: int) -> Array[int]:
	var n := get_node(id)
	if n == null:
		var empty: Array[int] = []
		return empty
	return n.next_ids


## StS 式解锁：只能沿当前已选路径上行，不能回退、不能横向跳到同层兄弟。
## current_id < 0 = 尚未进入任何节点（仅入口可选）；否则仅 current_id 的直接后继可选。
## 位置不在本类存储（防双份状态），由 RunState.current_node_id 经调用方传入。
## 已访问节点一律不可再进。
func can_enter(id: int, current_id: int = -1) -> bool:
	var n := get_node(id)
	if n == null or n.visited:
		return false
	if current_id < 0:
		return n.is_entry
	var cur := get_node(current_id)
	return cur != null and cur.next_ids.has(id)


## 尝试进入节点。成功则标记 visited 并返回 true；否则零副作用。
func enter(id: int, current_id: int = -1) -> bool:
	if not can_enter(id, current_id):
		return false
	nodes[id].visited = true
	return true


func mark_visited(id: int) -> void:
	var n := get_node(id)
	if n != null:
		n.visited = true


## 可达性：沿 next_ids 从 from_id 能否到达 to_id（边只向高行，天然无环）。
func has_path(from_id: int, to_id: int) -> bool:
	if from_id == to_id:
		return nodes.has(from_id)
	var seen: Dictionary[int, bool] = {}
	var stack: Array[int] = [from_id]
	while not stack.is_empty():
		var cur: int = stack.pop_back()
		if cur == to_id:
			return true
		if seen.has(cur):
			continue
		seen[cur] = true
		var n := get_node(cur)
		if n == null:
			continue
		for nx in n.next_ids:
			stack.append(nx)
	return false
