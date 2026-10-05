@abstract
class_name EffectDef
extends Resource
## 数据驱动效果定义的抽象基类。
## 普通卡牌只配置 type_key / params；真正规则由 handlers/ 中的处理器实现。

@export var type_key: StringName = &""
@export var params: Dictionary = {}

## 与 B1 共用的目标合同。具体合法性由 BoardQuery / ComboPlanner 判定。
var target_strategy: TargetSpec = null


func to_plan_item() -> Dictionary:
	return {
		"type_key": type_key,
		"params": params.duplicate(true),
		"target_strategy": target_strategy,
	}
