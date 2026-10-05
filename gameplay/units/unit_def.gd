class_name UnitDef
extends Resource
## 单位只读定义：基础属性 + 外观引用。运行时禁止修改（不变量：Def 永不被运行时改动）。
## 玩家与敌人共用。位置**不在**本类也不在 UnitState——位置权威在 BoardState（§9）。

@export var id: StringName = &""

## 基础属性：StatSystem.STAT_* -> 基础值。有效值由 StatSystem 按修饰计算。
@export var base_stats: Dictionary[StringName, int] = {}

## 外观引用键（表现层槽位/场景键，不是节点路径）。
@export var appearance_key: StringName = &""


func base_stat(key: StringName) -> int:
	return base_stats.get(key, 0)
