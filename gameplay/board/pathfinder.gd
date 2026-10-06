class_name Pathfinder
extends RefCounted
## 8×8 等成本 A*（曼哈顿启发式，确定性）。只读 BoardState，纯函数。
## 规则（combat_rules §9）：
##   - 只走 4 邻（上下左右）；对角步不参与移动（与 LoS 的 8 向判定分开）。
##   - 不可走（traversable=false）与占用格（一格一单位）视作障碍，不可穿越。
## 平局裁决（取直）：同 f 先取 **g 更大**者（沿目标推进、少拐弯），再按 (y,x) 保证确定性。
## 可达集合（reachable_cells）仍用等成本 BFS 洪泛；路径（find_path）用 A*。

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


## 从 from_cell 到 to_cell 的 A* 最短路（含两端；不可达/目标非法返回空）。
## h = 曼哈顿（对 4 邻等成本步长可采纳且一致），故结果仍是最短路；取直裁决见类注释。
static func find_path(board: BoardState, from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	if from_cell == to_cell:
		return [from_cell]
	if not board.is_inside(to_cell) or not board.is_traversable(to_cell) or board.is_occupied(to_cell):
		return []
	var g_score: Dictionary[Vector2i, int] = {from_cell: 0}
	var came_from: Dictionary[Vector2i, Vector2i] = {}
	var open: Array[Vector2i] = [from_cell]
	var closed: Dictionary[Vector2i, bool] = {}
	while not open.is_empty():
		var current := _pop_lowest_f(open, g_score, to_cell)
		if current == to_cell:
			break
		closed[current] = true
		for n: Vector2i in _walkable_neighbors(board, current):
			if closed.has(n):
				continue
			var tentative := int(g_score[current]) + 1
			if not g_score.has(n) or tentative < int(g_score[n]):
				g_score[n] = tentative
				came_from[n] = current
				if not open.has(n):
					open.append(n)
	if not came_from.has(to_cell):
		return []
	var path: Array[Vector2i] = [to_cell]
	var step: Vector2i = to_cell
	while step != from_cell:
		step = came_from[step]
		path.append(step)
	path.reverse()
	return path


## 取 open 中 f = g + h 最小者并移除；同 f 取 **g 更大**者（朝目标取直、少拐弯）；再平手按 (y,x)。
static func _pop_lowest_f(open: Array[Vector2i], g_score: Dictionary, goal: Vector2i) -> Vector2i:
	var best_index := 0
	var best: Vector2i = open[0]
	var best_g := int(g_score[best])
	var best_f := best_g + _manhattan(best, goal)
	for i in range(1, open.size()):
		var cell: Vector2i = open[i]
		var gi := int(g_score[cell])
		var fi := gi + _manhattan(cell, goal)
		if fi < best_f or (fi == best_f and (gi > best_g or (gi == best_g and _precedes(cell, best)))):
			best_index = i
			best = cell
			best_g = gi
			best_f = fi
	open.remove_at(best_index)
	return best


## 可走进格：盘内 + 可走 + 未被占用。
static func _walkable_neighbors(board: BoardState, cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d: Vector2i in ORTHO_DIRS:
		var n := cell + d
		if not board.is_inside(n) or not board.is_traversable(n) or board.is_occupied(n):
			continue
		out.append(n)
	return out


static func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


static func _precedes(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or (a.y == b.y and a.x < b.x)


static func _by_y_then_x(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or (a.y == b.y and a.x < b.x)
