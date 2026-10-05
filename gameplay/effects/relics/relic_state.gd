class_name RelicState
extends RefCounted
## 一局游戏中的遗物运行状态。

var instance_id: int = -1
var relic_id: StringName = &""
var counters: Dictionary = {}


func get_counter(key: StringName, default_value: int = 0) -> int:
	return int(counters.get(key, default_value))


func set_counter(key: StringName, value: int) -> void:
	counters[key] = value


func add_counter(key: StringName, amount: int = 1) -> int:
	var value := get_counter(key) + amount
	counters[key] = value
	return value
