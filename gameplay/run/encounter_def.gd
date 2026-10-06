class_name EncounterDef
extends Resource
## 遭遇定义（设计数据，只读）。描述“一场战斗由哪些敌人、在什么棋盘上组成”。
## 不引用 RunState/BattleState；由 EncounterBuilder 转成 BattleFactory 的输入。

@export var id: StringName = &""

## 敌人内容 ID 列表（EnemyDef.id）。决定敌人组成与顺序（顺序 = 确定性稳定顺序）。
@export var enemy_ids: Array[StringName] = []

## 敌人出生格（按 index 对应 enemy_ids）。为空项/缺省时由 EncounterBuilder 用默认布局。
@export var enemy_spawns: Array[Vector2i] = []

@export var board_cols: int = 8
@export var board_rows: int = 8
@export var player_start: Vector2i = Vector2i(2, 5)

@export var hand_size: int = 5
@export var energy_per_round: int = 3
@export var move_points_per_round: int = 2

## 层级键：monster / elite / boss（校验、奖励池、地图类型映射用）。
@export var tier: StringName = &"monster"

## 战后奖励池 ID（第二轮 RewardSystem 使用；本轮留空）。
@export var reward_pool_id: StringName = &""

## 本遭遇可召唤的小怪内容 ID 池（Boss 每隔几回合刷新用；EncounterBuilder 解析成召唤池）。
@export var summon_enemy_ids: Array[StringName] = []


func is_valid() -> bool:
	return not id.is_empty() and not enemy_ids.is_empty()
