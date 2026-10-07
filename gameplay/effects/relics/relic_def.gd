class_name RelicDef
extends Resource
## 遗物只读定义。计数器等运行数据必须放进 RelicState，不能写回 Resource。

@export var relic_id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var priority: int = 0
## 退役定义保留稳定 ID 供旧档读取，但不再掉落、显示或触发。
@export var enabled: bool = true
## 触发键与参数由 RelicSystem 消费；计数保存在 RelicState / BattleState，定义只读。
@export var trigger_key: StringName = &""
@export var trigger_params: Dictionary = {}


func is_valid() -> bool:
	return not relic_id.is_empty()
