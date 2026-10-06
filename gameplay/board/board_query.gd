class_name BoardQuery
extends RefCounted
## 规则层空间查询门面（静态纯函数，只读 BoardState）。空间决策见 combat_rules §9/§10。
## 位置/占用原语委托 BoardState；可达走 Pathfinder；本类新增射程与视线。
##
## （§10 三件事不得混用）
##   - 移动可达性：reachable_cells（可走路径）
##   - 技能射程：  get_target_cells（含可选 LoS）
##   - 视线：      has_line_of_sight（supercover，无穿角窥视）

## 射程度量：默认 Manhattan（正交步数）。对角步是否计入射程属数值调参，
## 改动时只改本函数并同步文档，不影响 LoS（LoS 独立按 supercover 判定）。
const METRIC_MANHATTAN := 0


## 射程形状（空间概念，归本类；EnemyActionDef.range_shape 引用本枚举）。
##   BOX       方框（切比雪夫）：3×3 = 半径 1、5×5 = 半径 2，**含对角**。
##   DIAMOND   菱形（曼哈顿）：正交步数（旧语义，卡牌/兼容入口默认）。
##   UNLIMITED 无视距离：全盘任意格。
enum RangeShape { BOX, DIAMOND, UNLIMITED }


## a->b 是否在给定形状与半径的射程内（UNLIMITED 恒真）。
static func within_range(shape: RangeShape, a: Vector2i, b: Vector2i, range_: int) -> bool:
	match shape:
		RangeShape.BOX:
			return maxi(absi(a.x - b.x), absi(a.y - b.y)) <= range_
		RangeShape.UNLIMITED:
			return true
		_:
			return absi(a.x - b.x) + absi(a.y - b.y) <= range_


## 按形状度量 a->b 的格距（UNLIMITED 记为 0）。用于"离目标最近/最远"的候选比较。
static func cell_distance(shape: RangeShape, a: Vector2i, b: Vector2i) -> int:
	match shape:
		RangeShape.BOX:
			return maxi(absi(a.x - b.x), absi(a.y - b.y))
		RangeShape.UNLIMITED:
			return 0
		_:
			return absi(a.x - b.x) + absi(a.y - b.y)


static func is_inside(board: BoardState, cell: Vector2i) -> bool:
	return board.is_inside(cell)


static func get_unit_at(board: BoardState, cell: Vector2i) -> int:
	return board.get_unit_at(cell)


static func get_unit_cell(board: BoardState, unit_id: int) -> Vector2i:
	return board.get_unit_cell(unit_id)


static func reachable_cells(board: BoardState, from_cell: Vector2i, move_points: int) -> Array[Vector2i]:
	return Pathfinder.reachable_cells(board, from_cell, move_points)


## from_cell 射程内的格（不含自身）。require_los=true 时过滤掉视线被挡的格。
## 射程内被单位占据的格**仍然返回**（那是攻击目标所在格）。
## 兼容入口：默认菱形（曼哈顿），旧语义不变。
static func get_target_cells(board: BoardState, from_cell: Vector2i, range_: int, require_los: bool) -> Array[Vector2i]:
	return get_target_cells_shaped(board, from_cell, range_, RangeShape.DIAMOND, require_los)


## 按形状取 from_cell 射程内的格（不含自身；含被单位占据的格）。
## UNLIMITED 返回全盘格（require_los 时按 LoS 过滤）。结果按 (y,x) 确定性排序。
static func get_target_cells_shaped(board: BoardState, from_cell: Vector2i, range_: int, shape: RangeShape, require_los: bool) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not board.is_inside(from_cell):
		return out
	for y in range(board.rows):
		for x in range(board.cols):
			var cell := Vector2i(x, y)
			if cell == from_cell:
				continue
			if not within_range(shape, from_cell, cell, range_):
				continue
			if require_los and not has_line_of_sight(board, from_cell, cell):
				continue
			out.append(cell)
	out.sort_custom(Pathfinder._by_y_then_x)
	return out


## 视线判定（supercover，§10）：
##   - 起点与终点格本身不阻挡。
##   - 连线经过的中间格任一 blocks_los 即阻挡（含穿角：经过格角的两侧都算经过）。
##   - 对称：has_line_of_sight(a,b) == has_line_of_sight(b,a)。
static func has_line_of_sight(board: BoardState, from_cell: Vector2i, to_cell: Vector2i) -> bool:
	if not board.is_inside(from_cell) or not board.is_inside(to_cell):
		return false
	if from_cell == to_cell:
		return true
	# 两方向的 supercover 取并集：穿角时两方向覆盖的相邻格不同，并集才是无穿的完整覆盖，且保证对称。
	var covered := _supercover_line(from_cell, to_cell)
	covered.append_array(_supercover_line(to_cell, from_cell))
	for cell: Vector2i in covered:
		if cell == from_cell or cell == to_cell:
			continue
		if board.blocks_los(cell):
			return false
	return true


## 两格中心连线的 supercover 格集合（含两端）。
## 采用标准 supercover：恰过格角时两轴各进一步、两格都入集合（无穿角窥视）。
static func _supercover_line(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = [from]
	var x := from.x
	var y := from.y
	var dx := to.x - from.x
	var dy := to.y - from.y
	var nx := absi(dx)
	var ny := absi(dy)
	if nx == 0 and ny == 0:
		return cells
	var sx := signi(dx)
	var sy := signi(dy)
	var ix := 0
	var iy := 0
	while ix < nx or iy < ny:
		var decision := (1 + 2 * ix) * ny - (1 + 2 * iy) * nx
		if decision == 0:
			x += sx
			ix += 1
			cells.append(Vector2i(x, y))
			y += sy
			iy += 1
			cells.append(Vector2i(x, y))
		elif decision < 0:
			x += sx
			ix += 1
			cells.append(Vector2i(x, y))
		else:
			y += sy
			iy += 1
			cells.append(Vector2i(x, y))
	return cells
