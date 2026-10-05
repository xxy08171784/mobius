class_name IntentState
extends RefCounted
## 敌人已锁定的行动意图。字段冻结（development_split.md §4）：action_id / target / locked_cell（+ 影响范围）。
## ROUND_START 锁定并给 UI 预告；执行前若因玩家行动失效，按降级处理（is_fallback），**不重算**整轮意图（combat_rules §2）。
## UI 预告与执行**共用同一对象**（directory_structure §5 enemies）。

## 行动稳定键（指向行为表中的行动）。空 = 无意图（无行动/已降级为无）。
var action_id: StringName = &""

## 发起者（敌人）单位 ID。
var actor_id: int = -1

var target_policy: EnemyActionDef.TargetPolicy = EnemyActionDef.TargetPolicy.PLAYER

## 锁定的目标单位 ID；-1 = 无。
var locked_unit_id: int = -1

## 锁定的格子（APPROACH 的落点、ATTACK 的目标格）；(-1,-1) = 无。
var locked_cell: Vector2i = Vector2i(-1, -1)

## 影响范围（预告用；执行时按同一对象）。MVP 为单格。
var affected_cells: Array[Vector2i] = []

## 预告数值（伤害/护盾等），供 UI 显示。
var magnitude: int = 0

## 是否为降级意图（原意图失效后改用 fallback）。
var is_fallback: bool = false


func is_empty() -> bool:
	return action_id == &""


func has_target() -> bool:
	return locked_unit_id >= 0


func has_locked_cell() -> bool:
	return locked_cell != Vector2i(-1, -1)
