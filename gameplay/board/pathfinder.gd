class_name Pathfinder
extends RefCounted
## 8×8 等成本 BFS（MVP 用不到 A*）。只读 BoardState，纯函数，确定性输出。
## 规则（combat_rules §9）：
##   - 只走 4 邻（上下左右）；对角步不参与移动（与 LoS 的 8 向判定分开）。
##   - 不可走（traversable=false）与占用格（一格一单位）视作障碍，不可穿越。
## 返回集合/路径按确定性顺序（先 y 后 x）。

const ORTHO_DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]


## 从 from_cell 出发、在 move_points 步内可达的格（不含起点本身，按 y 后 x 排序）。
static func reachable_cells(board: BoardState, from_cell: Vector2i, move_points: int) -> Array[Vector2i]:
	if move_points <= 0 or not board.is_inside(from_cell):
		return []
	var dist: Dictionary[Vector2i, int] = {from_cell: 0}
	var queue: Array[Vector2i] = [from_cell]
	var head := 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		var d: int = dist[cur]
		if d >= move_points:
			continue
		for n: Vector2i in _walkable_neighbors(board, cur):
			if dist.has(n):
				continue
			dist[n] = d + 1
			queue.append(n)
	queue.erase(from_cell)
	queue.sort_custom(_by_y_then_x)
	return queue


## 从 from_cell 到 to_cell 的最短路（含两端；不可达/目标非法返回空）。
static func find_path(board: BoardState, from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	if from_cell == to_cell:
		return [from_cell]
	if not board.is_inside(to_cell) or not board.is_traversable(to_cell) or board.is_occupied(to_cell):
		return []
	var came_from: Dictionary[Vector2i, Vector2i] = {}
	var visited: Dictionary[Vector2i, bool] = {from_cell: true}
	var queue: Array[Vector2i] = [from_cell]
	var head := 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		if cur == to_cell:
			break
		for n: Vector2i in _walkable_neighbors(board, cur):
			if visited.has(n):
				continue
			visited[n] = true
			came_from[n] = cur
			queue.append(n)
	if not visited.has(to_cell):
		return []
	var path: Array[Vector2i] = [to_cell]
	var step: Vector2i = to_cell
	while step != from_cell:
		step = came_from[step]
		path.append(step)
	path.reverse()
	return path


## 可走进格：盘内 + 可走 + 未被占用。
static func _walkable_neighbors(board: BoardState, cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d: Vector2i in ORTHO_DIRS:
		var n := cell + d
		if not board.is_inside(n) or not board.is_traversable(n) or board.is_occupied(n):
			continue
		out.append(n)
	return out


static func _by_y_then_x(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or (a.y == b.y and a.x < b.x)
