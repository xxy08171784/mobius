class_name RelicDef
extends Resource
## 遗物只读定义。计数器等运行数据必须放进 RelicState，不能写回 Resource。

@export var relic_id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var priority: int = 0
## 先冻结内容侧触发键与参数；运行时 RelicState 属于未来 RunState，本阶段不越界接入 BattleState。
@export var trigger_key: StringName = &""
@export var trigger_params: Dictionary = {}


func is_valid() -> bool:
	return not relic_id.is_empty()
