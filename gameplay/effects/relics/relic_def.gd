class_name RelicDef
extends Resource
## 遗物只读定义。计数器等运行数据必须放进 RelicState，不能写回 Resource。

@export var relic_id: StringName = &""
@export var priority: int = 0


func is_valid() -> bool:
	return not relic_id.is_empty()
