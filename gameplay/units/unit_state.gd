class_name UnitState
extends RefCounted
## 单位运行状态（玩家与敌人共用）。**不存位置**——位置从 BoardState 查（§9 硬约束）。
## 只承载数据；伤害/护盾吸收等规则在结算管线（Track A），本类不实现。

enum Team { PLAYER, ENEMY }

## 战斗内稳定 ID（来自 BattleState.next_uid，随存档持久化）。
var unit_id: int = -1

## 指向 UnitDef 的稳定 ID（Def 只读，此处只存引用键）。
var def_id: StringName = &""

var team: Team = Team.ENEMY

var hp: int = 1
var max_hp: int = 1

## 护盾：吸收伤害（§6），拥有者下个回合开始时清零（§8）。
var block: int = 0

## 资源（能量/行动点等）。键为稳定 StringName。
var resources: Dictionary[StringName, int] = {}

## 状态实例容器。§4 约定：**先用 Dictionary[int, RefCounted] 占位**，
## 等 Track A 的 StatusState 命名落地后收紧值类型（顺序/生命周期见 §7/§8）。
## 键 = 状态定义 ID（int）。
var statuses: Dictionary[int, RefCounted] = {}


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


func has_status(status_id: int) -> bool:
	return statuses.has(status_id)


func get_status(status_id: int) -> RefCounted:
	return statuses.get(status_id)


func set_status(status_id: int, status: RefCounted) -> void:
	statuses[status_id] = status


func remove_status(status_id: int) -> void:
	statuses.erase(status_id)


## 状态 ID 升序（供确定性遍历/触发排序）。
func status_ids() -> Array[int]:
	var ids: Array[int] = []
	for id: int in statuses:
		ids.append(id)
	ids.sort()
	return ids
