class_name Displacement
extends RefCounted
## 位移规则（combat_rules §9）：移动 / 击退 / 交换 / 传送。
## **唯一入口**：规则层改动单位位置一律走本类或 BoardState 原语，禁止散落 ad-hoc 改动。
## 纯静态函数，直接读写传入的 BoardState（调用方在工作副本上操作）。返回 DisplacementResult。
## 位移后射程/可移动性由下一次查询重算，不缓存（§9）。

## 移动：目标须可达且路径长度 ≤ move_points（在行动预算内）。
static func move(board: BoardState, unit_id: int, to_cell: Vector2i, move_points: int) -> DisplacementResult:
	var res := DisplacementResult.new()
	res.unit_id = unit_id
	var from_cell := board.get_unit_cell(unit_id)
	if from_cell == BoardState.INVALID_CELL:
		res.reason = DisplacementResult.REASON_NO_UNIT
		return res
	res.from_cell = from_cell
	if to_cell == from_cell:
		res.to_cell = from_cell
		res.path = [from_cell]
		res.reason = DisplacementResult.REASON_SAME_CELL
		return res
	var path := Pathfinder.find_path(board, from_cell, to_cell)
	if path.is_empty():
		res.reason = DisplacementResult.REASON_NO_PATH
		return res
	if path.size() - 1 > move_points:
		res.reason = DisplacementResult.REASON_OUT_OF_BUDGET
		return res
	board.move_unit(unit_id, to_cell)
	res.moved = true
	res.to_cell = to_cell
	res.path = path
	return res


## 击退 N 格：逐步推进，遇墙/单位/盘边即停在其前；**不**移出盘外（停在边缘）。
## 【建议默认】碰撞不造成伤害（可作变体）。方向须为 8 个单位方向之一。
static func push(board: BoardState, unit_id: int, direction: Vector2i, distance: int) -> DisplacementResult:
	var res := DisplacementResult.new()
	res.unit_id = unit_id
	var from_cell := board.get_unit_cell(unit_id)
	if from_cell == BoardState.INVALID_CELL:
		res.reason = DisplacementResult.REASON_NO_UNIT
		return res
	res.from_cell = from_cell
	if direction == Vector2i.ZERO or absi(direction.x) > 1 or absi(direction.y) > 1:
		res.reason = DisplacementResult.REASON_BAD_DIRECTION
		res.path = [from_cell]
		return res
	if distance <= 0:
		res.to_cell = from_cell
		res.path = [from_cell]
		res.reason = DisplacementResult.REASON_SAME_CELL
		return res
	var cur := from_cell
	var path: Array[Vector2i] = [from_cell]
	for _i in distance:
		var nxt := cur + direction
		if not board.is_inside(nxt):
			res.reason = DisplacementResult.REASON_EDGE
			break
		if not board.is_traversable(nxt):
			res.reason = DisplacementResult.REASON_WALL
			break
		if board.is_occupied(nxt):
			res.reason = DisplacementResult.REASON_UNIT_BLOCK
			break
		cur = nxt
		path.append(cur)
	res.path = path
	res.to_cell = cur
	if cur != from_cell:
		board.move_unit(unit_id, cur)
		res.moved = true
	return res


## 传送：目标在盘内且空格即生效，忽略路径与视线与地形可走性（§9 字面）。
static func teleport(board: BoardState, unit_id: int, to_cell: Vector2i) -> DisplacementResult:
	var res := DisplacementResult.new()
	res.unit_id = unit_id
	var from_cell := board.get_unit_cell(unit_id)
	if from_cell == BoardState.INVALID_CELL:
		res.reason = DisplacementResult.REASON_NO_UNIT
		return res
	res.from_cell = from_cell
	if to_cell == from_cell:
		res.to_cell = from_cell
		res.path = [from_cell]
		res.reason = DisplacementResult.REASON_SAME_CELL
		return res
	if not board.is_inside(to_cell):
		res.reason = DisplacementResult.REASON_OUT_OF_BOUNDS
		return res
	if board.is_occupied(to_cell):
		res.reason = DisplacementResult.REASON_OCCUPIED
		return res
	board.teleport_unit(unit_id, to_cell)
	res.moved = true
	res.to_cell = to_cell
	res.path = [from_cell, to_cell]
	return res


## 交换两格上的单位：不要求路径/射程，直接交换。
static func swap(board: BoardState, cell_a: Vector2i, cell_b: Vector2i) -> bool:
	return board.swap_units(cell_a, cell_b)
