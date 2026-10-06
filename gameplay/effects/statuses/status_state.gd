class_name StatusState
extends RefCounted
## 单个运行中状态实例。B 线 UnitState 的 statuses 容器最终保存这个类型。

var instance_id: int = -1
var status_id: StringName = &""
var stacks: int = 1
var duration: int = 1
var source_unit_id: int = -1


func is_expired() -> bool:
	# duration < 0 表示持续到显式移除（飞刀标记等）。
	return duration == 0 or stacks <= 0


func decrease_duration(amount: int = 1) -> void:
	if duration > 0:
		duration = maxi(0, duration - maxi(0, amount))
