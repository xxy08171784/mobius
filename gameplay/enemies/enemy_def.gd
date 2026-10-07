class_name EnemyDef
extends Resource
## 敌人定义：属性 + 行为 + 外观。只读。
## 数值经 UnitDef 提供（base_stats），行为经 BehaviorDef 提供。

@export var id: StringName = &""

## 关联的单位定义 ID（HP/攻击等基础属性）。
@export var unit_def_id: StringName = &""

## 行为规则表（.tres 外链，避免内联共享子资源被改动，见 architecture_review H8）。
@export var behavior: BehaviorDef = null

## 外观引用键（表现层槽位/场景键，不是节点路径）。
@export var appearance_key: StringName = &""

## 显示名（UI 数值面板用；空则由表现层回退到外观键）。
@export var display_name: String = ""

## 被动反应（死亡/受击触发，见 ReactionDef）。随战斗装配下发（不进 BattleState/存档）。
@export var reactions: Array[ReactionDef] = []
## 只影响棋子美术大小，不改变属性、占格或攻击距离。
@export_range(0.5, 2.0) var visual_scale: float = 1.0
