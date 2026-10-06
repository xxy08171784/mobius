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


## 拖拽：把目标朝 toward_cell（施法者）方向**直线拉** distance 格。碰撞处理同 push
## （遇墙/单位/盘边即停在其前，不移出盘外）。方向由目标→施法者推得（8 方向之一）。
static func pull(board: BoardState, unit_id: int, toward_cell: Vector2i, distance: int) -> DisplacementResult:
	var res := DisplacementResult.new()
	res.unit_id = unit_id
	var from_cell := board.get_unit_cell(unit_id)
	if from_cell == BoardState.INVALID_CELL:
		res.reason = DisplacementResult.REASON_NO_UNIT
		return res
	res.from_cell = from_cell
	if toward_cell == from_cell:
		res.to_cell = from_cell
		res.path = [from_cell]
		res.reason = DisplacementResult.REASON_SAME_CELL
		return res
	if not board.is_inside(toward_cell):
		res.to_cell = from_cell
		res.path = [from_cell]
		res.reason = DisplacementResult.REASON_BAD_DIRECTION
		return res
	var path := pull_path(board, from_cell, toward_cell, distance)
	res.path = path
	res.to_cell = path[path.size() - 1]
	if res.to_cell != from_cell:
		board.move_unit(unit_id, res.to_cell)
		res.moved = true
	return res


## 拖拽路径（纯函数，含起点；不改棋盘）。供计划阶段算步数、执行阶段算落点共用。
## 从 from_cell 朝 toward_cell 方向逐步推进至多 distance 格，遇墙/单位/盘边即停。
static func pull_path(board: BoardState, from_cell: Vector2i, toward_cell: Vector2i, distance: int) -> Array[Vector2i]:
	var path: Array[Vector2i] = [from_cell]
	var dir := Vector2i(signi(toward_cell.x - from_cell.x), signi(toward_cell.y - from_cell.y))
	if dir == Vector2i.ZERO or distance <= 0:
		return path
	var cur := from_cell
	for _i in distance:
		var nxt := cur + dir
		if not board.is_inside(nxt) or not board.is_traversable(nxt) or board.is_occupied(nxt):
			break
		cur = nxt
		path.append(cur)
	return path
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
