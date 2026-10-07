class_name ObstacleDef
extends Resource
## 棋盘障碍/装饰定义（设计数据，只读）。规则读布尔标志，美术按 appearance_key 查表。
## 落到棋盘时由 ObstacleGenerator 转成 CellState（见 to_cell_state）。

## 稳定内容 ID（obstacle.actN.*）。存档契约，发行后不要改名。
@export var id: StringName = &""

@export var display_name: String = ""

## 美术键：assets/textures/obstacles/<appearance_key>.png。
@export var appearance_key: StringName = &""

## 渲染等比缩放（1.0 = 按目标高度归一化后的额外放大/缩小）。
@export_range(0.3, 3.0) var visual_scale: float = 1.0

## 阻挡移动（立式物件默认 true）。
@export var traversable: bool = false

## 阻挡视线（高柱/雕像/树为 true；低矮废墟为 false）。
@export var blocks_los: bool = true

## 可进入并触发效果（本轮未实现触发逻辑，保留字段）。
@export var trap: bool = false


func is_valid() -> bool:
	return not id.is_empty() and not appearance_key.is_empty()


## 该障碍占据某格时的地形状态。
func to_cell_state() -> CellState:
	var cell_state := CellState.new()
	cell_state.terrain_key = id
	cell_state.traversable = traversable
	cell_state.blocks_los = blocks_los
	cell_state.trap = trap
	return cell_state
