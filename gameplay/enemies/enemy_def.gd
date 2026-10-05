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
