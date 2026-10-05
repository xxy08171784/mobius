class_name BoardState
extends RefCounted
## 棋盘权威状态：尺寸 + 每格地形 + cell↔unit 占用（MVP：一格一单位）。
## 位置只在 BoardState 查询，UnitState 不存坐标（combat_rules §9 硬约束）。
## 占用变更全部经 place_unit/remove_unit/move_unit 单一入口，双向索引 _unit_at / _cell_of_unit 恒一致。
## 未显式设置的格子视为"空旷地面"（可走、不挡视线），无需预先铺满全盘。
## 本类只提供数据结构与占用原语；可达性/射程/视线见 board_query.gd。

## 坐标轴：col = x ∈ [0, cols)，row = y ∈ [0, rows)。
var cols: int = 8
var rows: int = 8

## cell -> CellState（仅存非默认格；缺省 = 空旷地面）。
var _cells: Dictionary[Vector2i, CellState] = {}

## cell -> unit_id（占用）。-1 不存在。
var _unit_at: Dictionary[Vector2i, int] = {}

## unit_id -> cell（反查）。与 _unit_at 同步维护。
var _cell_of_unit: Dictionary[int, Vector2i] = {}


## 无效坐标/未放置的哨兵。与 TargetSpec.CellTarget 的"未解析"约定一致。
const INVALID_CELL := Vector2i(-1, -1)


func _init(cols_: int = 8, rows_: int = 8) -> void:
	cols = cols_
	rows = rows_


func is_inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < cols and cell.y >= 0 and cell.y < rows


## 返回显式设置的格状态；未设置返回 null（调用方按"空旷地面"处理）。
func get_cell(cell: Vector2i) -> CellState:
	return _cells.get(cell)


func set_cell(cell: Vector2i, cell_state: CellState) -> void:
	_cells[cell] = cell_state


func is_traversable(cell: Vector2i) -> bool:
	if not is_inside(cell):
		return false
	var cs := _cells.get(cell) as CellState
	return cs == null or cs.traversable


func blocks_los(cell: Vector2i) -> bool:
	var cs := _cells.get(cell) as CellState
	return cs != null and cs.blocks_los


func is_trap(cell: Vector2i) -> bool:
	var cs := _cells.get(cell) as CellState
	return cs != null and cs.trap


## 该格上的单位 ID；空格或盘外返回 -1。
func get_unit_at(cell: Vector2i) -> int:
	return _unit_at.get(cell, -1)


## 单位所在格；未放置返回 INVALID_CELL。
func get_unit_cell(unit_id: int) -> Vector2i:
	return _cell_of_unit.get(unit_id, INVALID_CELL)


func is_occupied(cell: Vector2i) -> bool:
	return _unit_at.has(cell)


func has_unit(unit_id: int) -> bool:
	return _cell_of_unit.has(unit_id)


## 能否把单位放到该格：在盘内、可走、且空格。已放置的同一单位视为不可再放（防隐式搬移）。
func can_place(unit_id: int, cell: Vector2i) -> bool:
	if not is_inside(cell) or not is_traversable(cell):
		return false
	if has_unit(unit_id):
		return false
	return not is_occupied(cell)


## 放置单位。失败（越界/不可走/占用/已放置）零副作用，返回 false。
func place_unit(unit_id: int, cell: Vector2i) -> bool:
	if not can_place(unit_id, cell):
		return false
	_unit_at[cell] = unit_id
	_cell_of_unit[unit_id] = cell
	return true


## 移除单位。未放置返回 false，零副作用。
func remove_unit(unit_id: int) -> bool:
	var cell: Vector2i = _cell_of_unit.get(unit_id, INVALID_CELL)
	if cell == INVALID_CELL:
		return false
	_unit_at.erase(cell)
	_cell_of_unit.erase(unit_id)
	return true


## 移动到目标格。失败（未放置/越界/不可走/目标被占）零副作用，返回 false。
## 这是位移的底层原语；击退/交换/传送的落点冲突规则在其上实现（combat_rules §9）。
func move_unit(unit_id: int, to_cell: Vector2i) -> bool:
	var from_cell: Vector2i = _cell_of_unit.get(unit_id, INVALID_CELL)
	if from_cell == INVALID_CELL:
		return false
	if to_cell == from_cell:
		return true
	if not is_inside(to_cell) or not is_traversable(to_cell) or is_occupied(to_cell):
		return false
	_unit_at.erase(from_cell)
	_unit_at[to_cell] = unit_id
	_cell_of_unit[unit_id] = to_cell
	return true


## 交换两格上的单位（combat_rules §9：不要求路径/射程）。两格须各有单位且互不相同。
func swap_units(cell_a: Vector2i, cell_b: Vector2i) -> bool:
	if cell_a == cell_b:
		return false
	var ua: int = get_unit_at(cell_a)
	var ub: int = get_unit_at(cell_b)
	if ua == -1 or ub == -1:
		return false
	_unit_at[cell_a] = ub
	_unit_at[cell_b] = ua
	_cell_of_unit[ua] = cell_b
	_cell_of_unit[ub] = cell_a
	return true


## 传送原语：仅要求盘内 + 空格，**忽略地形可走性**（combat_rules §9：传送忽略路径与视线）。
func teleport_unit(unit_id: int, to_cell: Vector2i) -> bool:
	var from_cell: Vector2i = _cell_of_unit.get(unit_id, INVALID_CELL)
	if from_cell == INVALID_CELL:
		return false
	if to_cell == from_cell:
		return true
	if not is_inside(to_cell) or is_occupied(to_cell):
		return false
	_unit_at.erase(from_cell)
	_unit_at[to_cell] = unit_id
	_cell_of_unit[unit_id] = to_cell
	return true


## 盘上全部单位 ID（排序，供确定性遍历/测试）。
func get_unit_ids() -> Array[int]:
	var ids: Array[int] = []
	for unit_id: int in _cell_of_unit:
		ids.append(unit_id)
	ids.sort()
	return ids
