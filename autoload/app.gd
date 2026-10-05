extends Node
## 当前 Profile / Run 生命周期。autoload。
## 约束（architecture_review.md 中优先级）：只暴露 create_run/load_profile/end_run 等生命周期 API，
## 玩法方法一律不挂本类，防止变成 God Object。

var current_profile: RefCounted = null
var current_run: RefCounted = null


## 读取局外配置，生成一份确定的初始 RunState。
func create_run(_character_id: StringName) -> RefCounted:
	# TODO: 由 RunSession/MapGenerator 生成。
	return null


## 结束本局：结算永久货币/解锁，用 run ID 防重复发放。
func end_run(_result: RefCounted) -> void:
	# TODO
	pass
