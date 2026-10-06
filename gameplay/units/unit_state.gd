class_name UnitState
extends RefCounted
## 单位运行状态（玩家与敌人共用）。**不存位置**——位置从 BoardState 查（§9 硬约束）。
## 只承载数据；伤害/护盾吸收等规则在结算管线（Track A），本类不实现。

enum Team { PLAYER, ENEMY }

## 战斗内稳定 ID（来自 BattleState.next_uid，随存档持久化）。
var unit_id: int = -1

## 指向 UnitDef 的稳定 ID（Def 只读，此处只存引用键）。
var def_id: StringName = &""

## 敌人内容 ID（EnemyDef.id）；玩家为空。表现层用它查显示名（ContentDB.get_enemy）。
var enemy_id: StringName = &""

var team: Team = Team.ENEMY

var hp: int = 1
var max_hp: int = 1

## 护盾：吸收伤害（§6），拥有者下个回合开始时清零（§8）。
var block: int = 0

## 资源（能量/行动点等）。键为稳定 StringName。
var resources: Dictionary[StringName, int] = {}

## 状态实例容器。A1 已落地 StatusState，键使用稳定 instance_id。
## status_id 本身保存在 StatusState 内，允许同一状态定义存在多个独立实例。
var statuses: Dictionary[int, StatusState] = {}


static func create(unit_id_: int, def_id_: StringName, team_: Team, max_hp_: int) -> UnitState:
	var u := UnitState.new()
	u.unit_id = unit_id_
	u.def_id = def_id_
	u.team = team_
	u.max_hp = max_hp_
	u.hp = max_hp_
	return u


func is_alive() -> bool:
	return hp > 0


func is_player() -> bool:
	return team == Team.PLAYER


func clear_block() -> void:
	block = 0


func get_resource(key: StringName) -> int:
	return resources.get(key, 0)


func set_resource(key: StringName, value: int) -> void:
	resources[key] = value


func add_resource(key: StringName, delta: int) -> void:
	resources[key] = get_resource(key) + delta


func has_status(instance_id: int) -> bool:
	return statuses.has(instance_id)


func get_status(instance_id: int) -> StatusState:
	return statuses.get(instance_id)


func set_status(instance_id: int, status: StatusState) -> void:
	statuses[instance_id] = status


func remove_status(instance_id: int) -> void:
	statuses.erase(instance_id)


## 状态实例 ID 升序（供确定性遍历/触发排序）。
func status_ids() -> Array[int]:
	var ids: Array[int] = []
	for id: int in statuses:
		ids.append(id)
	ids.sort()
	return ids
