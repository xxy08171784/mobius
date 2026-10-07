class_name ObstacleGenerator
extends RefCounted
## 随机障碍生成（纯函数、确定性）：在棋盘内部格随机摆障碍，并保证开放格始终连通。
## 由 EncounterBuilder / DemoBattleSetup 调用；不引用 SceneTree。
## 玩家起点在外圈、障碍只在内部，故摆放不依赖玩家起点（部署预览与实战同 seed 同结果）。

## content 为 ContentDB 型“鸭子对象”，需提供 get_obstacle(id)。
## board 会被就地 set_cell 修改；rng 为 encounter 流（确定性）。
static func place_obstacles(
	board: BoardState,
	pool: ObstaclePoolDef,
	count: int,
	rng: RandomNumberGenerator,
	content: Object
) -> void:
	if board == null or pool == null or pool.obstacle_ids.is_empty() or count <= 0 or rng == null:
		return
	var candidates := _interior_cells(board)
	_shuffle(candidates, rng)
	var placed := 0
	for cell: Vector2i in candidates:
		if placed >= count:
			break
		if board.is_occupied(cell) or not board.is_traversable(cell):
			continue
		if _would_disconnect(board, cell) or _boxes_unit(board, cell):
			continue
		var obstacle_id: StringName = pool.obstacle_ids[rng.randi_range(0, pool.obstacle_ids.size() - 1)]
		if content != null:
			var obstacle: ObstacleDef = content.get_obstacle(obstacle_id)
			if obstacle == null:
				continue
			board.set_cell(cell, obstacle.to_cell_state())
			placed += 1
	return


## 把 cell 设为障碍后，其余开放格是否仍全部互相连通（防止把单位围死）。
static func _would_disconnect(board: BoardState, cell: Vector2i) -> bool:
	var open: Array[Vector2i] = []
	for row in range(board.rows):
		for col in range(board.cols):
			var c := Vector2i(col, row)
			if c != cell and board.is_traversable(c) and not board.is_occupied(c):
				open.append(c)
	if open.is_empty():
		return true
	var visited: Dictionary = {open[0]: true}
	_bfs(board, cell, open[0], visited)
	for c: Vector2i in open:
		if not visited.has(c):
			return true
	return false


## 若把 cell 变成障碍，是否会让盘上任意单位（含敌人）失去**最后一个可走邻居**（被围死）。
## 连通性只保证开放格相连，不保证单位不被包围；这里补上"单位必须保留 ≥1 出路"。
static func _boxes_unit(board: BoardState, cell: Vector2i) -> bool:
	for unit_id: int in board.get_unit_ids():
		var unit_cell := board.get_unit_cell(unit_id)
		if unit_cell == BoardState.INVALID_CELL:
			continue
		var free_neighbors := 0
		for d: Vector2i in _DIRS:
			var n := unit_cell + d
			if n == cell:
				continue  # 该格即将成为障碍，不算出路
			if board.is_inside(n) and board.is_traversable(n) and not board.is_occupied(n):
				free_neighbors += 1
		if free_neighbors == 0:
			return true
	return false


const _DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]


static func _bfs(board: BoardState, blocked: Vector2i, start: Vector2i, visited: Dictionary) -> void:
	var stack: Array[Vector2i] = [start]
	while not stack.is_empty():
		var cur: Vector2i = stack.pop_back()
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nxt := cur + d
			if not board.is_inside(nxt) or nxt == blocked or visited.has(nxt):
				continue
			if not board.is_traversable(nxt) or board.is_occupied(nxt):
				continue
			visited[nxt] = true
			stack.append(nxt)


## 内部格 = 不贴棋盘最外圈（玩家只在最外圈进场，障碍只在内部）。
static func _interior_cells(board: BoardState) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in range(1, board.rows - 1):
		for x in range(1, board.cols - 1):
			cells.append(Vector2i(x, y))
	return cells


## Fisher-Yates 就地洗牌（确定性来自传入 rng）。
static func _shuffle(cells: Array[Vector2i], rng: RandomNumberGenerator) -> void:
	for i in range(cells.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := cells[i]
		cells[i] = cells[j]
		cells[j] = tmp
