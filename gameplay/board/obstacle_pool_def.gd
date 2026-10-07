class_name ObstaclePoolDef
extends Resource
## 障碍池（设计数据，只读）：一场战斗随机抽取障碍的稳定 ID 列表。
## 按幕命名 obstacle_pool.actN，由 EncounterDef / MonsterPoolDef 的 obstacle_pool_id 引用。

@export var id: StringName = &""
@export var obstacle_ids: Array[StringName] = []


func is_valid() -> bool:
	return not id.is_empty() and not obstacle_ids.is_empty()
