class_name MonsterPoolDef
extends Resource
## 怪物池定义（设计数据，只读）。与 EncounterDef 的区别：
##   EncounterDef = 一场战斗**固定**的敌人组成；
##   MonsterPoolDef = 一个**池**，进入战斗时按 battle_index 从中抽取 2~4 只（见 MonsterPool）。
## 棋盘/回合参数与 EncounterDef 同名同义：抽到的敌人按此模板组装成临时 EncounterDef。

@export var id: StringName = &""

## 层级键：monster / elite / boss（与 EncounterDef.tier 同义）。
@export var tier: StringName = &"monster"

## 可抽取的怪物内容 ID（EnemyDef.id）。**有放回**均匀抽（允许同种重复）。
@export var enemy_ids: Array[StringName] = []

## 棋盘模板。
@export var board_cols: int = 8
@export var board_rows: int = 8
@export var player_start: Vector2i = Vector2i(2, 5)

## 回合参数。
@export var hand_size: int = 5
@export var energy_per_round: int = 3
@export var move_points_per_round: int = 2

## 随机障碍：池 ID 与数量（拷进临时 EncounterDef，见 MonsterPool._compose）。
@export var obstacle_pool_id: StringName = &""
@export var obstacle_count: int = 0


func is_valid() -> bool:
	return not id.is_empty() and not enemy_ids.is_empty()
