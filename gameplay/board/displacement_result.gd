class_name DisplacementResult
extends RefCounted
## 一次位移（移动/击退/传送）的结果。承载构造表现层事件所需的数据：
##   UnitMoved(unit_id, from_cell -> to_cell)、CellExited(from_cell)、CellEntered(to_cell)。
## 本类不引用事件类型：事件类（GameEvent 子类）的归属是 §4 共享契约，待与 A 线确认后由集成层据本结果构造。

## 未移动原因（reason 取值，稳定键）。
const REASON_NONE := &""
const REASON_NO_UNIT := &"no_unit"
const REASON_SAME_CELL := &"same_cell"
const REASON_NO_PATH := &"no_path"
const REASON_OUT_OF_BUDGET := &"out_of_budget"
const REASON_WALL := &"wall"
const REASON_UNIT_BLOCK := &"unit_block"
const REASON_EDGE := &"edge"
const REASON_OUT_OF_BOUNDS := &"out_of_bounds"
const REASON_OCCUPIED := &"occupied"
const REASON_BAD_DIRECTION := &"bad_direction"

var moved: bool = false
var unit_id: int = -1
var from_cell: Vector2i = Vector2i(-1, -1)
var to_cell: Vector2i = Vector2i(-1, -1)

## 经过的格（含起点与终点）。击退为逐格路径，供表现层播放；失败时含起点。
var path: Array[Vector2i] = []

## moved=true 时为 REASON_NONE；否则为上面的稳定键，供本地化/调试。
var reason: StringName = REASON_NONE
